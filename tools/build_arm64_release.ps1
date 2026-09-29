param([string]$FlutterPath = '', [string]$AndroidSdk = '', [string]$HistoricalApk = '', [string]$ExpectedVersion = '', [switch]$AllowHistoricalDebugSigning, [switch]$SplitPerAbi)
$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
if (!$FlutterPath) { $FlutterPath = Join-Path $root '.toolcache/flutter/bin/flutter.bat' }
if (!$AndroidSdk) {
    $line = (Get-Content 'android/local.properties' | Select-String '^sdk.dir=').Line
    $AndroidSdk = ($line -replace '^sdk.dir=', '') -replace '\\\\','\'
}
$dart = Join-Path (Split-Path $FlutterPath -Parent) 'dart.bat'
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
$report = Join-Path $root "build/optimization_report/$stamp"
New-Item -ItemType Directory -Path $report -Force | Out-Null
$version = ((Get-Content 'pubspec.yaml' | Select-String '^version:').Line -replace '^version:\s*', '').Trim()
$baselineFile = Join-Path $report 'version.json'
@{version=$version;applicationId='com.mkdjj.whisnya'} | ConvertTo-Json | Set-Content $baselineFile
function Run([string]$name, [string]$exe, [string[]]$arguments) {
    & $exe @arguments *> (Join-Path $report "$name.log")
    $code = $LASTEXITCODE
    "exit=$code" | Add-Content (Join-Path $report "$name.log")
    if ($code -ne 0) { throw "$name failed (exit $code). See $report/$name.log" }
}
$priorArm64 = [Environment]::GetEnvironmentVariable('ORG_GRADLE_PROJECT_whisnyaArm64Only')
try {
    if ($AllowHistoricalDebugSigning -and !$HistoricalApk) { throw 'Historical APK is required for explicitly approved legacy signing.' }
    $originalBaseline = Join-Path $root 'build/optimization_report/baseline.json'
    if ($ExpectedVersion) {
        if ($version -cne $ExpectedVersion) { throw 'Version does not match the explicitly requested release.' }
    } elseif (Test-Path -LiteralPath $originalBaseline) {
        & "$PSScriptRoot/assert_version.ps1" -Baseline $originalBaseline
    }
    & "$PSScriptRoot/assert_version.ps1" -Baseline $baselineFile
    Run 'pub-get' $FlutterPath @('pub','get')
    Run 'format' $dart @('format','--output=none','--set-exit-if-changed','lib','test','tool')
    Run 'analyze' $FlutterPath @('analyze')
    Run 'test' $FlutterPath @('test')
    if (!(Test-Path -LiteralPath 'android/key.properties')) {
        throw 'SIGNING BLOCKED: android/key.properties is absent. No APK was built or copied.'
    }
    $abiArgs = @()
    $expectedCode = [int]$version.Split('+')[1]
    if ($SplitPerAbi) {
        $env:ORG_GRADLE_PROJECT_whisnyaArm64Only = 'false'
        $abiArgs = @('--split-per-abi')
        $expectedCode += 2000
        $output = Join-Path $root 'build/app/outputs/flutter-apk/app-arm64-v8a-release.apk'
    } else {
        $env:ORG_GRADLE_PROJECT_whisnyaArm64Only = 'true'
        $abiArgs = @('--android-project-arg=whisnyaArm64Only=true', '--android-project-arg=disable-abi-filtering=true')
        $output = Join-Path $root 'build/app/outputs/flutter-apk/app-release.apk'
    }
    $started = Get-Date
    Run 'baseline-release' $FlutterPath (@('build','apk','--release','--target-platform=android-arm64','--analyze-size',"--code-size-directory=$report/baseline-size") + $abiArgs)
    if (!(Test-Path $output) -or (Get-Item $output).LastWriteTime -lt $started) { throw 'No fresh baseline APK.' }
    $baselineBytes = (Get-Item $output).Length
    Copy-Item -LiteralPath $output -Destination (Join-Path $report 'baseline.apk')
    $symbols = Join-Path $report 'symbols'
    $started = Get-Date
    # Flutter 3.44 rejects combining --analyze-size and --split-debug-info.
    Run 'final-release' $FlutterPath (@('build','apk','--release','--target-platform=android-arm64',"--split-debug-info=$symbols") + $abiArgs)
    if (!(Test-Path $output) -or (Get-Item $output).LastWriteTime -lt $started) { throw 'No fresh final APK.' }
    & "$PSScriptRoot/assert_version.ps1" -Baseline $baselineFile
    $buildTools = Get-ChildItem (Join-Path $AndroidSdk 'build-tools') -Directory | Sort-Object { [version]$_.Name } -Descending | Select-Object -First 1
    $signer = Join-Path $buildTools.FullName 'apksigner.bat'
    $analyzer = Join-Path $AndroidSdk 'cmdline-tools/latest/bin/apkanalyzer.bat'
    Run 'signature' $signer @('verify','--verbose','--print-certs',$output)
    $signature = Get-Content (Join-Path $report 'signature.log') -Raw
    if ($signature -match 'CN=Android Debug' -and !$AllowHistoricalDebugSigning) { throw 'Debug certificate requires explicit approval and a matching historical APK.' }
    $signatureNote = 'Historical signature not compared: no historical APK supplied.'
    if ($HistoricalApk) {
        Run 'historical-signature' $signer @('verify','--verbose','--print-certs',$HistoricalApk)
        $oldSignature = Get-Content (Join-Path $report 'historical-signature.log') -Raw
        $digestPattern = 'certificate SHA-256 digest: ([a-fA-F0-9]+)'
        $newDigest = [regex]::Match($signature, $digestPattern).Groups[1].Value
        $oldDigest = [regex]::Match($oldSignature, $digestPattern).Groups[1].Value
        if (!$newDigest -or !$oldDigest -or $newDigest -cne $oldDigest) {
            throw 'Certificate differs from historical APK; data-preserving upgrade is not verified.'
        }
        $signatureNote = 'Historical APK certificate matches.'
        Run 'historical-version-code' $analyzer @('manifest','version-code',$HistoricalApk)
        $historicalCode = ((Get-Content (Join-Path $report 'historical-version-code.log') | Where-Object { $_ -notlike 'exit=*' }) -join '').Trim()
        if ($expectedCode -lt [long]$historicalCode) {
            throw "APK versionCode $expectedCode is lower than historical versionCode $historicalCode; refusing downgrade package."
        }
        $signatureNote += " VersionCode checked: $historicalCode -> $expectedCode."
    }
    foreach ($property in @('version-name','version-code','application-id','debuggable')) {
        Run "manifest-$property" $analyzer @('manifest',$property,$output)
    }
    $name = (Get-Content (Join-Path $report 'manifest-version-name.log') | Where-Object { $_ -notlike 'exit=*' }) -join ''
    $code = (Get-Content (Join-Path $report 'manifest-version-code.log') | Where-Object { $_ -notlike 'exit=*' }) -join ''
    $app = (Get-Content (Join-Path $report 'manifest-application-id.log') | Where-Object { $_ -notlike 'exit=*' }) -join ''
    $debug = (Get-Content (Join-Path $report 'manifest-debuggable.log') | Where-Object { $_ -notlike 'exit=*' }) -join ''
    if ($name.Trim() -ne $version.Split('+')[0] -or $code.Trim() -ne "$expectedCode" -or $app.Trim() -ne 'com.mkdjj.whisnya' -or $debug.Trim() -ne 'false') { throw 'APK manifest does not match version/application/release baseline.' }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $zip = [IO.Compression.ZipFile]::OpenRead($output)
    try {
        $native = @($zip.Entries | Where-Object { $_.FullName -match '^lib/.+\.so$' })
        if (@($zip.Entries | Where-Object { $_.FullName -match '(?i)(^|/)(key\.properties|[^/]+\.(jks|keystore|log))$|(^|/)(backups|test_data)/' }).Count -gt 0) { throw 'Unexpected sensitive/debug data in APK.' }
        if (@($native | Where-Object { $_.FullName -notmatch '^lib/arm64-v8a/' }).Count -gt 0) { throw 'Unexpected APK ABI.' }
        foreach ($lib in @('libflutter.so','libapp.so')) { if (!($native.FullName -contains "lib/arm64-v8a/$lib")) { throw "Missing $lib" } }
        $sizes = $zip.Entries | Group-Object { if ($_.FullName -eq 'lib/arm64-v8a/libapp.so') {'Dart AOT'} elseif ($_.FullName.StartsWith('lib/')) {'Native libraries'} else {'Resources and metadata'} } | ForEach-Object { "$($_.Name): $(($_.Group | Measure-Object CompressedLength -Sum).Sum) compressed bytes" }
        foreach ($entry in $zip.Entries) { $stream=$entry.Open(); try { $stream.CopyTo([IO.Stream]::Null) } finally { $stream.Dispose() } }
    } finally { $zip.Dispose() }
    $dist = Join-Path $root "dist/arm64-$stamp"
    New-Item -ItemType Directory -Path $dist | Out-Null
    $target = Join-Path $dist "Whisnya_${version}_arm64_$stamp.apk"
    Copy-Item -LiteralPath $output -Destination $target
    Copy-Item -LiteralPath $symbols -Destination (Join-Path $dist 'symbols') -Recurse
    $hash=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
    "$hash  $([IO.Path]::GetFileName($target))" | Set-Content (Join-Path $dist 'SHA256SUMS.txt')
    $bytes=(Get-Item $target).Length
    @("APK: $target", "Version: $version", "ABI: arm64-v8a", "Bytes: $bytes", "MiB: $([math]::Round($bytes/1MB,3))", "Baseline bytes: $baselineBytes", "Reduction bytes: $($baselineBytes-$bytes)", "Logs: $report", $signatureNote, $sizes, (Get-Content (Join-Path $report 'signature.log'))) | Set-Content (Join-Path $dist 'BUILD_REPORT.txt')
    Write-Output $target
} catch {
    $_.Exception.Message | Set-Content (Join-Path $report 'BLOCKED.txt')
    throw
} finally {
    [Environment]::SetEnvironmentVariable('ORG_GRADLE_PROJECT_whisnyaArm64Only', $priorArm64)
}

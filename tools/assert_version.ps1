param([string]$Baseline = (Join-Path $PSScriptRoot '../build/optimization_report/baseline.json'))
$ErrorActionPreference = 'Stop'
$expected = Get-Content -LiteralPath $Baseline -Raw | ConvertFrom-Json
$actual = ((Get-Content (Join-Path $PSScriptRoot '../pubspec.yaml') | Select-String '^version:').Line -replace '^version:\s*', '').Trim()
if ($actual -cne $expected.version) { throw "Version changed: expected $($expected.version), actual $actual" }
$gradle = Get-Content (Join-Path $PSScriptRoot '../android/app/build.gradle.kts') -Raw
if ($gradle -notmatch 'versionCode = flutter.versionCode' -or $gradle -notmatch 'versionName = flutter.versionName') { throw 'Android version mapping changed.' }
Write-Output "Version unchanged: $actual"

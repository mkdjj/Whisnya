$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
Set-Location $root
$report = Join-Path $root 'build/optimization_report'
New-Item -ItemType Directory -Force -Path $report | Out-Null
if (Test-Path -LiteralPath (Join-Path $report 'baseline.json')) {
    throw 'Baseline already exists; preserve the original baseline for this optimization run.'
}
$flutter = Join-Path $root '.toolcache/flutter/bin/flutter.bat'
$dart = Join-Path $root '.toolcache/flutter/bin/dart.bat'
$version = ((Get-Content 'pubspec.yaml' | Select-String '^version:').Line -replace '^version:\s*', '').Trim()
@{version=$version;applicationId='com.mkdjj.whisnya';commit=(git rev-parse HEAD);signingConfigPresent=(Test-Path 'android/key.properties')} | ConvertTo-Json | Set-Content (Join-Path $report 'baseline.json') -Encoding utf8
git status --short | Set-Content (Join-Path $report 'git-status.txt')
foreach ($entry in @(@('flutter-version',$flutter,@('--version')), @('dart-version',$dart,@('--version')), @('flutter-doctor',$flutter,@('doctor','-v')), @('apk-help',$flutter,@('build','apk','--help')))) {
    $commandArgs = $entry[2]
    & $entry[1] @commandArgs *> (Join-Path $report ($entry[0]+'.log'))
    "exit=$LASTEXITCODE" | Add-Content (Join-Path $report ($entry[0]+'.log'))
}
Get-Content (Join-Path $report 'baseline.json')

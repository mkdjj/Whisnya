[CmdletBinding(SupportsShouldProcess = $true)]
param()

$ErrorActionPreference = 'Stop'
$taskRoot = [IO.Path]::GetFullPath((Split-Path $PSScriptRoot -Parent))
if ($taskRoot -ne 'E:\AIChat') { throw 'This script is only for E:\AIChat.' }

$taskTargets = @()
$taskBuild = Join-Path $taskRoot 'build'
if (Test-Path -LiteralPath $taskBuild) {
    $taskTargets += Get-ChildItem -LiteralPath $taskBuild -Force |
        Where-Object { $_.Name -notin @('removed-tests-20261011', 'optimization_report') }
}
$taskReports = Join-Path $taskBuild 'optimization_report'
if (Test-Path -LiteralPath $taskReports) {
    $taskTargets += Get-ChildItem -LiteralPath $taskReports -Force |
        Where-Object { $_.Name -ne 'baseline.json' -and $_.Extension -ne '.md' }
}

$taskDist = Join-Path $taskRoot 'dist'
if (Test-Path -LiteralPath $taskDist) {
    $taskPackages = @(Get-ChildItem -LiteralPath $taskDist -Force)
    $taskKeep = @($taskPackages | Where-Object { $_.PSIsContainer -and $_.Name -like 'arm64-*' } |
        Sort-Object Name -Descending | Select-Object -First 2 -ExpandProperty FullName)
    $taskKeep += @($taskPackages | Where-Object { -not $_.PSIsContainer -and $_.Name -like '*windows*.zip' } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1 -ExpandProperty FullName)
    $taskTargets += $taskPackages | Where-Object {
        $_.FullName -notin $taskKeep -and (
            ($_.PSIsContainer -and ($_.Name -like 'arm64-*' -or $_.Name -match '^v\d+\.\d+\.\d+$')) -or
            (-not $_.PSIsContainer -and $_.Name -like 'Whisnya*.zip')
        )
    }
}

foreach ($taskRelative in @('.dart_tool\flutter_build', 'flutter_01.log', 'windows-build-elevated.log')) {
    $taskPath = Join-Path $taskRoot $taskRelative
    if (Test-Path -LiteralPath $taskPath) { $taskTargets += Get-Item -LiteralPath $taskPath -Force }
}

$taskCount = 0
foreach ($taskTarget in $taskTargets) {
    $taskPath = (Resolve-Path -LiteralPath $taskTarget.FullName).Path
    if (-not $taskPath.StartsWith($taskRoot + '\', [StringComparison]::OrdinalIgnoreCase) -or
        ($taskTarget.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
        throw "Unsafe cleanup target: $taskPath"
    }
    if ($PSCmdlet.ShouldProcess($taskPath, 'Permanently delete generated files or old packages')) {
        Remove-Item -LiteralPath $taskPath -Recurse -Force -ErrorAction Stop
        Write-Host "Deleted: $taskPath"
        $taskCount++
    }
}
Write-Host "Done. Deleted targets: $taskCount"

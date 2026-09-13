#Requires -Version 7.0
[CmdletBinding()]
param(
    [string]$GodotExe = '',
    [ValidateSet('Editor', 'Exported')][string]$HostMode = 'Editor'
)

$ErrorActionPreference = 'Stop'
$projectRoot = $PSScriptRoot
$testRoot = Join-Path ([IO.Path]::GetTempPath()) ('roguetown-patch-smoke-' + [Guid]::NewGuid().ToString('N'))
$testProject = Join-Path $testRoot 'project'
$testClient = Join-Path $testRoot 'client.exe'
$jobs = [Collections.Generic.List[object]]::new()

function Start-Probe([string]$Name, [string]$Exe, [string[]]$Arguments, [string]$Data) {
    $info = [Diagnostics.ProcessStartInfo]::new($Exe)
    $info.UseShellExecute = $false
    $info.CreateNoWindow = $true
    $info.RedirectStandardOutput = $true
    $info.RedirectStandardError = $true
    $info.WorkingDirectory = $testRoot
    $info.ArgumentList.Add('--log-file')
    $info.ArgumentList.Add((Join-Path $testRoot ($Name + '.godot.log')))
    foreach ($argument in $Arguments) { $info.ArgumentList.Add($argument) }
    if ($Data -ne '') { $info.Environment['APPDATA'] = Join-Path $testRoot $Data }
    $info.Environment['ROGUETOWN_PATCH_TEST_ROOT'] = $testRoot
    $info.Environment.Remove('CODEX_VALIDATE_IMPORTS') | Out-Null
    $process = [Diagnostics.Process]::Start($info)
    $job = @{ Name = $Name; Process = $process; Output = $process.StandardOutput.ReadToEndAsync(); Errors = $process.StandardError.ReadToEndAsync() }
    $jobs.Add($job)
    return $job
}

function Wait-Probe($Job) {
    if (-not $Job.Process.WaitForExit(180000)) { throw "$($Job.Name) timed out." }
    $output = $Job.Output.Result + $Job.Errors.Result
    if ($Job.Process.ExitCode -ne 0 -or $output -match '(?m)^(SCRIPT ERROR:|ERROR:)') {
        throw "$($Job.Name) failed (exit code $($Job.Process.ExitCode)):`n$output"
    }
}

function Wait-Result([string]$Name) {
    $deadline = [DateTime]::UtcNow.AddSeconds(180)
    while (-not (Test-Path -LiteralPath (Join-Path $testRoot $Name))) {
        if (Test-Path -LiteralPath (Join-Path $testRoot 'failure.json')) {
            throw (Get-Content -LiteralPath (Join-Path $testRoot 'failure.json') -Raw)
        }
        if ([DateTime]::UtcNow -gt $deadline) { throw "Timed out waiting for $Name." }
        Start-Sleep -Milliseconds 200
    }
}

try {
    if ($GodotExe -eq '') {
        $projectConfig = Get-Content -LiteralPath (Join-Path $projectRoot 'project.godot') -Raw
        if ($projectConfig -notmatch 'config/features=PackedStringArray\("([0-9]+\.[0-9]+)"') { throw 'Cannot determine Godot version.' }
        $engineVersion = $Matches[1]
        $projectParent = Split-Path -Parent $projectRoot
        $desktop = Split-Path -Parent $projectParent
        $candidates = @(
            (Join-Path $projectParent "Godot_v$engineVersion-stable_win64.exe"),
            (Join-Path $desktop "Godot_v$engineVersion-stable_win64.exe"),
            (Join-Path $desktop "godot $engineVersion\Godot_v$engineVersion-stable_win64.exe")
        )
        $GodotExe = $candidates | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    }
    if (-not $GodotExe -or -not (Test-Path -LiteralPath $GodotExe)) { throw 'Pass -GodotExe with the matching Godot editor executable.' }
    New-Item -ItemType Directory -Path $testRoot -Force | Out-Null
    & robocopy $projectRoot $testProject /E /XD .git (Join-Path $projectRoot '.godot\editor') (Join-Path $projectRoot '.godot\shader_cache') /XF export_credentials.cfg /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -gt 7) { throw 'Could not copy the isolated test project.' }
    # Keep the test source stable while exporting; do not stamp its version.
    $configPath = Join-Path $testProject 'project.godot'
    $config = Get-Content -LiteralPath $configPath -Raw
    $config = $config -replace '(?m)^enabled=PackedStringArray\([^\r\n]*\)', 'enabled=PackedStringArray()'
    [IO.File]::WriteAllText($configPath, $config)
    $obsolete = Join-Path $testProject 'scripts\tools\patch_smoke_obsolete.gd'
    'extends RefCounted' | Set-Content -LiteralPath $obsolete
    Write-Host 'Exporting the baseline client with standard Godot templates...'
    Wait-Probe (Start-Probe 'import-base' $GodotExe @('--headless', '--path', $testProject, '--editor', '--import') '')
    Wait-Probe (Start-Probe 'export-base' $GodotExe @('--headless', '--path', $testProject, '--export-release', 'Windows Desktop', $testClient) '')

    # Change an early autoload, add a global class/resource/imported texture,
    # and remove a file after exporting, to catch stale export remaps/caches.
    @'
class_name PatchSmokeAddedData
extends Resource
@export var label: String
@export var texture: Texture2D
'@ | Set-Content -LiteralPath (Join-Path $testProject 'scripts\tools\patch_smoke_added_data.gd')
    '<svg xmlns="http://www.w3.org/2000/svg" width="8" height="8"><rect width="8" height="8" fill="#e3524a"/></svg>' | Set-Content -LiteralPath (Join-Path $testProject 'assets\patch_smoke_icon.svg')
    @'
[gd_resource type="Resource" script_class="PatchSmokeAddedData" load_steps=3 format=3]
[ext_resource type="Script" path="res://scripts/tools/patch_smoke_added_data.gd" id="1"]
[ext_resource type="Texture2D" path="res://assets/patch_smoke_icon.svg" id="2"]
[resource]
script = ExtResource("1")
label = "new class from patch"
texture = ExtResource("2")
'@ | Set-Content -LiteralPath (Join-Path $testProject 'scripts\tools\patch_smoke_resource.tres')
    Remove-Item -LiteralPath $obsolete
    if (Test-Path -LiteralPath ($obsolete + '.uid')) { Remove-Item -LiteralPath ($obsolete + '.uid') }
    Wait-Probe (Start-Probe 'import-update' $GodotExe @('--headless', '--path', $testProject, '--editor', '--import') '')
    $registryPath = Join-Path $testProject 'objects\item_registry.gd'
    $registry = (Get-Content -LiteralPath $registryPath -Raw).Replace('extends Node', "extends Node`nconst PATCH_SMOKE_RESOURCE = preload(`"res://scripts/tools/patch_smoke_resource.tres`")")
    [IO.File]::WriteAllText($registryPath, $registry)

    $serverExe = $GodotExe
    $serverArgs = @('--headless', '--path', $testProject, '--', '--patch-smoke-server')
    if ($HostMode -eq 'Exported') {
        $serverExe = Join-Path $testRoot 'server.exe'
        Wait-Probe (Start-Probe 'export-update' $GodotExe @('--headless', '--path', $testProject, '--export-release', 'Windows Desktop', $serverExe) '')
        $serverArgs = @('--headless', '--', '--patch-smoke-server')
    }

    $socket = [Net.Sockets.UdpClient]::new(0)
    $port = $socket.Client.LocalEndPoint.Port
    $socket.Dispose()
    [string]$port | Set-Content -LiteralPath (Join-Path $testRoot 'port.txt')
    $server = Start-Probe 'server' $serverExe $serverArgs 'server-data'
    Wait-Result 'server_ready.json'
    $socket = [Net.Sockets.UdpClient]::new(0)
    $basePort = $socket.Client.LocalEndPoint.Port
    $socket.Dispose()
    [string]$basePort | Set-Content -LiteralPath (Join-Path $testRoot 'base_port.txt')
    $baseServer = Start-Probe 'base-server' $testClient @('--headless', '--', '--patch-smoke-base-server') 'base-server-data'
    Wait-Result 'base_server_ready.json'
    Write-Host 'Testing download, early patch loading and automatic reconnect...'
    $client = Start-Probe 'client-initial' $testClient @('--headless', '--', '--patch-smoke-client') 'client-data'
    Wait-Result 'client_pass_2.json'
    Wait-Probe $client
    $replacement = Get-Content -LiteralPath (Join-Path $testRoot 'client_pass_2.json') -Raw | ConvertFrom-Json
    try { [Diagnostics.Process]::GetProcessById([int]$replacement.pid).WaitForExit(10000) | Out-Null } catch [ArgumentException] { }
    Write-Host 'Testing ordinary startup ignores the cached update and stale reconnect requests...'
    $stateFile = Get-ChildItem -LiteralPath (Join-Path $testRoot 'client-data') -Recurse -Filter active_patch.json -File | Select-Object -First 1
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
    $reconnectFile = Join-Path $stateFile.DirectoryName 'pending_reconnect.json'
    $state | ConvertTo-Json | Set-Content -LiteralPath $reconnectFile
    Wait-Probe (Start-Probe 'client-idle' $testClient @('--headless', '--', '--patch-smoke-idle') 'client-data')
    Wait-Probe (Start-Probe 'client-stale-token' $testClient @('--headless', '--', '--patch-smoke-idle', '--patch-reconnect=stale-token') 'client-data')
    Write-Host 'Testing cached reconnect, then switching to an older server restores the base game...'
    $clientAgain = Start-Probe 'client-reconnect' $testClient @('--headless', '--', '--patch-smoke-client') 'client-data'
    Wait-Result 'client_pass_5.json'
    Wait-Probe $clientAgain
    $replacement = Get-Content -LiteralPath (Join-Path $testRoot 'client_pass_5.json') -Raw | ConvertFrom-Json
    try { [Diagnostics.Process]::GetProcessById([int]$replacement.pid).WaitForExit(10000) | Out-Null } catch [ArgumentException] { }
    # Wait for the intermediate patched process to acknowledge its base restart.
    $replacement = Get-Content -LiteralPath (Join-Path $testRoot 'client_pass_4.json') -Raw | ConvertFrom-Json
    try { [Diagnostics.Process]::GetProcessById([int]$replacement.pid).WaitForExit(10000) | Out-Null } catch [ArgumentException] { }
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
    Wait-Probe (Start-Probe 'client-consumed-token' $testClient @('--headless', '--', '--patch-smoke-idle', ('--patch-reconnect=' + $state.token)) 'client-data')
    Write-Host 'Testing the original server address now hosting an older game version...'
    $server.Process.Kill($true)
    $server.Process.WaitForExit()
    $baseServer.Process.Kill($true)
    $baseServer.Process.WaitForExit()
    [string]$port | Set-Content -LiteralPath (Join-Path $testRoot 'base_port.txt')
    Remove-Item -LiteralPath (Join-Path $testRoot 'base_server_ready.json')
    $baseServer = Start-Probe 'older-server' $testClient @('--headless', '--', '--patch-smoke-base-server') 'base-server-data'
    Wait-Result 'base_server_ready.json'
    Wait-Probe (Start-Probe 'client-older-server' $testClient @('--headless', '--', '--patch-smoke-older-client') 'client-data')
    Write-Host 'Testing damaged and missing saved updates fall back to the base game...'
    $state = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
    $wrongServer = Get-Content -LiteralPath $stateFile.FullName -Raw | ConvertFrom-Json
    $wrongServer.ip = '192.0.2.1'
    $wrongServer | ConvertTo-Json | Set-Content -LiteralPath $reconnectFile
    Wait-Probe (Start-Probe 'client-wrong-server' $testClient @('--headless', '--', '--patch-smoke-invalid', ('--patch-reconnect=' + $state.token)) 'client-data')
    $savedPack = [IO.Path]::GetFullPath($state.pack_path)
    if (-not $savedPack.StartsWith($testRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'The saved test pack is outside the isolated test directory.' }
    $stream = [IO.File]::Open($savedPack, 'Open', 'Write', 'None')
    try { $stream.WriteByte(0) } finally { $stream.Dispose() }
    Wait-Probe (Start-Probe 'client-corrupt-idle' $testClient @('--headless', '--', '--patch-smoke-idle') 'client-data')
    $state | ConvertTo-Json | Set-Content -LiteralPath $reconnectFile
    Wait-Probe (Start-Probe 'client-corrupt' $testClient @('--headless', '--', '--patch-smoke-invalid', ('--patch-reconnect=' + $state.token)) 'client-data')
    Remove-Item -LiteralPath $savedPack
    Wait-Probe (Start-Probe 'client-missing-idle' $testClient @('--headless', '--', '--patch-smoke-idle') 'client-data')
    $state | ConvertTo-Json | Set-Content -LiteralPath $reconnectFile
    Wait-Probe (Start-Probe 'client-missing' $testClient @('--headless', '--', '--patch-smoke-invalid', ('--patch-reconnect=' + $state.token)) 'client-data')
    Write-Host 'PASSED: patch download, one-shot reconnect, clean ordinary startup, cached reconnect, server/version isolation, early script/class/texture loading, removed files and invalid-update recovery.' -ForegroundColor Green
}
finally {
    foreach ($job in $jobs) {
        if (-not $job.Process.HasExited) { $job.Process.Kill($true); $job.Process.WaitForExit() }
        $job.Output.Result | Set-Content -LiteralPath (Join-Path $testRoot ($job.Name + '.log'))
        $job.Errors.Result | Set-Content -LiteralPath (Join-Path $testRoot ($job.Name + '.errors.log'))
    }
    # Restarted children outlive the initial process; match only this test's EXE.
    Get-CimInstance Win32_Process | Where-Object { $_.ExecutablePath -eq $testClient } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }
    Write-Host "Test logs: $testRoot"
}

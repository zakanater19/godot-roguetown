[CmdletBinding()]
param(
	[switch]$NoPause
)

$ErrorActionPreference = "Stop"

$exitCode = 1
$proc = $null
$projectRoot = ""
$godotExe = ""
$godotExeName = ""
$logPath = ""

function Resolve-GodotExecutable {
	param(
		[string]$ProjectRoot
	)

	$projectParent = Split-Path -Parent $ProjectRoot
	$desktopParent = Split-Path -Parent $projectParent
	$candidates = @(
		(Join-Path $projectParent "Godot_v4.5-stable_win64.exe"),
		(Join-Path $desktopParent "Godot_v4.5-stable_win64.exe")
	)

	foreach ($candidate in $candidates) {
		if (Test-Path -LiteralPath $candidate -PathType Leaf) {
			return (Resolve-Path -LiteralPath $candidate).Path
		}
	}

	$command = Get-Command "Godot_v4.5-stable_win64.exe" -ErrorAction SilentlyContinue
	if ($null -ne $command) {
		return $command.Source
	}

	throw "Godot_v4.5-stable_win64.exe was not found beside the project folder, on the Desktop, or on PATH."
}

function Stop-ProcessTree {
	param(
		[int]$RootId
	)

	if ($RootId -le 0) {
		return
	}

	$childIds = Get-CimInstance Win32_Process -Filter "ParentProcessId = $RootId" -ErrorAction SilentlyContinue |
		Select-Object -ExpandProperty ProcessId

	foreach ($childId in $childIds) {
		Stop-ProcessTree -RootId $childId
	}

	Stop-Process -Id $RootId -Force -ErrorAction SilentlyContinue
}

function Get-SmokeGodotProcesses {
	if ([string]::IsNullOrWhiteSpace($godotExe) -or [string]::IsNullOrWhiteSpace($projectRoot)) {
		return
	}

	Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
		Where-Object {
			$commandLine = $_.CommandLine
			if ([string]::IsNullOrWhiteSpace($commandLine)) {
				return $false
			}

			$matchesExe = $false
			if (-not [string]::IsNullOrWhiteSpace($_.ExecutablePath)) {
				$matchesExe = [string]::Equals([System.IO.Path]::GetFullPath($_.ExecutablePath), $godotExe, [System.StringComparison]::OrdinalIgnoreCase)
			}
			if (-not $matchesExe) {
				$matchesExe = [string]::Equals($_.Name, $godotExeName, [System.StringComparison]::OrdinalIgnoreCase)
			}

			$matchesExe -and
			$commandLine -match '(?i)(^|\s)--headless(\s|$)' -and
			$commandLine -match '(?i)(^|\s)--path(\s|$)' -and
			$commandLine.Contains($projectRoot)
		}
}

function Stop-SmokeGodotProcesses {
	$procs = @(Get-SmokeGodotProcesses | Sort-Object ProcessId -Unique)
	foreach ($projectProc in $procs) {
		Stop-ProcessTree -RootId ([int]$projectProc.ProcessId)
	}
}

try {
	$projectRoot = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
	$logPath = Join-Path $projectRoot "import_smoke_test.log"
	$godotExe = Resolve-GodotExecutable -ProjectRoot $projectRoot
	$godotExeName = Split-Path -Leaf $godotExe

	Write-Host ""
	Write-Host "============================================================"
	Write-Host "  ROGUETOWN SMOKE TEST" -ForegroundColor Cyan
	Write-Host "============================================================"
	Write-Host "  Running Godot headless..." -ForegroundColor DarkGray
	Write-Host ""

	$env:CODEX_VALIDATE_IMPORTS = "1"
	Stop-SmokeGodotProcesses
	Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
	$quotedProjectRoot = '"' + $projectRoot + '"'
	$proc = Start-Process -FilePath $godotExe -ArgumentList @("--headless", "--path", $quotedProjectRoot) -NoNewWindow -PassThru
	$proc.WaitForExit()
	$exitCode = $proc.ExitCode
}
catch {
	Write-Host ""
	Write-Host "Smoke test launcher failed: $($_.Exception.Message)" -ForegroundColor Red
	$exitCode = 1
}
finally {
	if ($proc -ne $null -and -not $proc.HasExited) {
		Stop-ProcessTree -RootId $proc.Id
		$proc.WaitForExit()
	}
	if (-not [string]::IsNullOrWhiteSpace($godotExe)) {
		Stop-SmokeGodotProcesses
	}
	if (-not [string]::IsNullOrWhiteSpace($logPath)) {
		Remove-Item -LiteralPath $logPath -Force -ErrorAction SilentlyContinue
	}
	Remove-Item Env:CODEX_VALIDATE_IMPORTS -ErrorAction SilentlyContinue

	Write-Host ""
	if (-not $NoPause) {
		Read-Host "Press Enter to close"
	}
}

exit $exitCode

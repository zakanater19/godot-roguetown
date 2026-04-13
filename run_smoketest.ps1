[CmdletBinding()]
param(
	[switch]$NoPause
)

$ErrorActionPreference = "Stop"

$projectRoot = (Resolve-Path (Split-Path -Parent $MyInvocation.MyCommand.Path)).Path
$godotExe = Join-Path (Split-Path -Parent $projectRoot) "Godot_v4.5-stable_win64.exe"

if (-not (Test-Path -LiteralPath $godotExe)) {
	Write-Error "Godot executable not found at '$godotExe'."
}

$godotExe = (Resolve-Path -LiteralPath $godotExe).Path
$godotExeName = Split-Path -Leaf $godotExe

Write-Host ""
Write-Host "============================================================"
Write-Host "  ROGUETOWN SMOKE TEST" -ForegroundColor Cyan
Write-Host "============================================================"
Write-Host "  Running Godot headless..." -ForegroundColor DarkGray
Write-Host ""

$env:CODEX_VALIDATE_IMPORTS = "1"
$exitCode = 1
$proc = $null

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
	Stop-SmokeGodotProcesses
	$proc = Start-Process -FilePath $godotExe -ArgumentList @("--headless", "--path", $projectRoot) -NoNewWindow -PassThru
	$proc.WaitForExit()
	$exitCode = $proc.ExitCode
}
finally {
	if ($proc -ne $null -and -not $proc.HasExited) {
		Stop-ProcessTree -RootId $proc.Id
		$proc.WaitForExit()
	}
	Stop-SmokeGodotProcesses
	Remove-Item Env:CODEX_VALIDATE_IMPORTS -ErrorAction SilentlyContinue
}

# Replay the log file with colors
$logPath = Join-Path $projectRoot "import_smoke_test.log"
if (Test-Path -LiteralPath $logPath) {
	Write-Host ""
	Write-Host "============================================================" -ForegroundColor DarkGray
	Write-Host "  RESULTS" -ForegroundColor White
	Write-Host "============================================================" -ForegroundColor DarkGray
	foreach ($line in Get-Content -LiteralPath $logPath) {
		if ($line -match "^\[ PASS \]") {
			Write-Host $line -ForegroundColor Green
		} elseif ($line -match "^\[ FAIL \]") {
			Write-Host $line -ForegroundColor Red
		} elseif ($line -match "^ERROR:") {
			Write-Host $line -ForegroundColor Red
		} elseif ($line -match "^WARN:") {
			Write-Host $line -ForegroundColor Yellow
		} elseif ($line -match "^PASSED") {
			Write-Host ""
			Write-Host $line -ForegroundColor Green
		} elseif ($line -match "^FAILED") {
			Write-Host ""
			Write-Host $line -ForegroundColor Red
		} elseif ($line -match "^[=\-]{10,}") {
			Write-Host $line -ForegroundColor DarkGray
		} else {
			Write-Host $line
		}
	}
}

Write-Host ""
if (-not $NoPause) {
	Read-Host "Press Enter to close"
}
exit $exitCode

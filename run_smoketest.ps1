$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotExe = Join-Path (Split-Path -Parent $projectRoot) "Godot_v4.5-stable_win64.exe"

if (-not (Test-Path -LiteralPath $godotExe)) {
	Write-Error "Godot executable not found at '$godotExe'."
}

Write-Host ""
Write-Host "============================================================"
Write-Host "  ROGUETOWN SMOKE TEST" -ForegroundColor Cyan
Write-Host "============================================================"
Write-Host "  Running Godot headless..." -ForegroundColor DarkGray
Write-Host ""

$env:CODEX_VALIDATE_IMPORTS = "1"
$exitCode = 1
try {
	$proc = Start-Process -FilePath $godotExe -ArgumentList @("--headless", "--path", $projectRoot) -Wait -NoNewWindow -PassThru
	$exitCode = $proc.ExitCode
}
finally {
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
Read-Host "Press Enter to close"
exit $exitCode

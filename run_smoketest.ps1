$ErrorActionPreference = "Stop"

$projectRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$godotExe = Join-Path (Split-Path -Parent $projectRoot) "Godot_v4.5-stable_win64.exe"

if (-not (Test-Path -LiteralPath $godotExe)) {
	Write-Error "Godot executable not found at '$godotExe'."
}

$env:CODEX_VALIDATE_IMPORTS = "1"
$exitCode = 1
try {
	$proc = Start-Process -FilePath $godotExe -ArgumentList @("--headless", "--path", $projectRoot) -Wait -NoNewWindow -PassThru
	$exitCode = $proc.ExitCode
}
finally {
	Remove-Item Env:CODEX_VALIDATE_IMPORTS -ErrorAction SilentlyContinue
}

if ($exitCode -eq 0) {
	Write-Host ""
	Write-Host "Smoke test finished successfully."
} else {
	Write-Host ""
	Write-Host "Smoke test failed with exit code $exitCode."
}

Read-Host "Press Enter to close"
exit $exitCode

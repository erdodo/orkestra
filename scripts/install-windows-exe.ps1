# Orkestra -- Windows Agent (EXE) Kurulum
# GitHub Releases'ten hazir exe indirir, Task Scheduler'a ekler.
# Hicbir derleme veya yonetici yetkisi gerekmez.
#
# Kullanim:
#   PowerShell -ExecutionPolicy Bypass -File scripts\install-windows-exe.ps1
#
# WAN sunucusu icin:
#   $env:ORKESTRA_SERVER = "ws://orkestra.erdoganyesil.org:3081/agent"

$ErrorActionPreference = "Stop"

$ReleaseUrl = "https://github.com/erdodo/orkestra/releases/latest/download/agent.exe"
$InstallDir = "$env:LOCALAPPDATA\Orkestra"
$AgentBin   = "$InstallDir\orkestra-agent.exe"
$TaskName   = "OrchestraAgent"
$ServerUrl  = if ($env:ORKESTRA_SERVER) { $env:ORKESTRA_SERVER } else { "ws://192.168.1.50:3081/agent" }

function Write-Ok   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== Orkestra -- Windows Agent Kurulum ===" -ForegroundColor Cyan
Write-Host ""

# -- 1. Dizin -----------------------------------------------------------------
New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null

# -- 2. Calisiyorsa durdur ----------------------------------------------------
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Warn "Eski surum durduruluyor..."
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
}

# -- 3. EXE indir -------------------------------------------------------------
Write-Warn "Indiriliyor: $ReleaseUrl"
Invoke-WebRequest -Uri $ReleaseUrl -OutFile $AgentBin -UseBasicParsing
if (-not (Test-Path $AgentBin)) { Write-Err "Indirme basarisiz." }
Write-Ok "Binary: $AgentBin"

# -- 4. Task Scheduler --------------------------------------------------------
if ($existingTask) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

[System.Environment]::SetEnvironmentVariable("ORKESTRA_SERVER", $ServerUrl, "User")

$action   = New-ScheduledTaskAction -Execute $AgentBin -Argument "--server-url `"$ServerUrl`""
$trigger  = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
$settings = New-ScheduledTaskSettingsSet `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Seconds 10) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable
$principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
    -Settings $settings -Principal $principal `
    -Description "Orkestra agent -- $ServerUrl" | Out-Null

# -- 5. Baslat ----------------------------------------------------------------
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2
$state = (Get-ScheduledTask -TaskName $TaskName).State
Write-Ok "Agent baslatildi: $state"

# -- Ozet ---------------------------------------------------------------------
Write-Host ""
Write-Host "=== Kurulum Tamamlandi ===" -ForegroundColor Green
Write-Host "  Sunucu : $ServerUrl"
Write-Host "  Durdur : Stop-ScheduledTask -TaskName $TaskName"
Write-Host ""

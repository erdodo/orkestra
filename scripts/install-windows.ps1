# Orkestra — Windows Agent Kurulum / Güncelleme Scripti
# Yönetici olarak çalıştırın:
#   PowerShell -ExecutionPolicy Bypass -File install-windows.ps1
# Kuruluysa günceller ve yeniden başlatır.

#Requires -RunAsAdministrator
$ErrorActionPreference = "Stop"

$RepoUrl    = "git@github.com:erdodo/orkestra.git"
$InstallDir = "$env:LOCALAPPDATA\Orkestra"
$AgentBin   = "$InstallDir\agent\target\release\agent.exe"
$TaskName   = "OrchestraAgent"
$ServerUrl  = if ($env:ORKESTRA_SERVER) { $env:ORKESTRA_SERVER } else { "ws://192.168.1.50:3081/agent" }
$LogFile    = "$env:LOCALAPPDATA\Orkestra\agent.log"

function Write-Ok   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "╔══════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   Orkestra — Windows Agent Setup    ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# ── 1. Winget / Scoop paket yöneticisi ──────────────────────────────────────
$UseWinget = $false
if (Get-Command winget -ErrorAction SilentlyContinue) {
    $UseWinget = $true
}

# ── 2. Rust / cargo ─────────────────────────────────────────────────────────
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Warn "Rust kuruluyor..."
    if ($UseWinget) {
        winget install --id Rustlang.Rustup -e --silent --accept-package-agreements
    } else {
        $rustupUrl = "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-msvc/rustup-init.exe"
        Invoke-WebRequest -Uri $rustupUrl -OutFile "$env:TEMP\rustup-init.exe"
        & "$env:TEMP\rustup-init.exe" -y --quiet
        Remove-Item "$env:TEMP\rustup-init.exe"
    }
    # PATH'i güncelle
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    [System.Environment]::SetEnvironmentVariable("PATH", $env:PATH, "User")
    Write-Ok "Rust kuruldu"
} else {
    Write-Ok "Rust zaten yüklü: $(rustc --version)"
}
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"

# ── 3. Git ───────────────────────────────────────────────────────────────────
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn "Git kuruluyor..."
    if ($UseWinget) {
        winget install --id Git.Git -e --silent --accept-package-agreements
        $env:PATH = "C:\Program Files\Git\cmd;$env:PATH"
    } else {
        Write-Err "Git bulunamadı. https://git-scm.com adresinden kurun."
    }
}

# ── 4. Repo klonla / güncelle ────────────────────────────────────────────────
if (Test-Path "$InstallDir\.git") {
    Write-Warn "Mevcut kurulum güncelleniyor..."
    Push-Location $InstallDir
    git pull --rebase
    Pop-Location
} else {
    Write-Warn "Repo klonlanıyor: $RepoUrl"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    # SSH yoksa HTTPS'e fallback
    try {
        git clone $RepoUrl $InstallDir
    } catch {
        Write-Warn "SSH başarısız, HTTPS deneniyor..."
        $HttpsUrl = $RepoUrl -replace "git@github.com:", "https://github.com/"
        git clone $HttpsUrl $InstallDir
    }
}

# ── 5. Agent derle ───────────────────────────────────────────────────────────
Write-Ok "Agent derleniyor (release)..."
Push-Location "$InstallDir\agent"
cargo build --release 2>&1 | Select-String -Pattern "error|Finished|Compiling agent"
Pop-Location

if (-not (Test-Path $AgentBin)) {
    Write-Err "Derleme başarısız: $AgentBin bulunamadı"
}
Write-Ok "Binary: $AgentBin"

# ── 6. Görev Zamanlayıcısı (Task Scheduler) ─────────────────────────────────
# Önce çalışıyorsa durdur
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Warn "Mevcut görev kaldırılıyor..."
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

$action = New-ScheduledTaskAction `
    -Execute $AgentBin `
    -Argument "--server-url `"$ServerUrl`""

# Oturum açıldığında başlat, bilgisayar uyandığında da çalışsın
$trigger = @(
    (New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME),
    (New-ScheduledTaskTrigger -AtStartup)
)

$settings = New-ScheduledTaskSettingsSet `
    -RestartCount 999 `
    -RestartInterval (New-TimeSpan -Seconds 10) `
    -ExecutionTimeLimit (New-TimeSpan -Hours 0) `
    -StartWhenAvailable `
    -RunOnlyIfNetworkAvailable

$principal = New-ScheduledTaskPrincipal `
    -UserId $env:USERNAME `
    -LogonType Interactive `
    -RunLevel Highest

Register-ScheduledTask `
    -TaskName $TaskName `
    -Action $action `
    -Trigger $trigger[0] `
    -Settings $settings `
    -Principal $principal `
    -Description "Orkestra cihaz ajanı — sunucu: $ServerUrl" | Out-Null

# Ortam değişkeni ekle (servis için)
$taskXml = (Export-ScheduledTask -TaskName $TaskName)
$taskXml = $taskXml -replace "</Exec>", "<EnvironmentVariables><ORKESTRA_SERVER>$ServerUrl</ORKESTRA_SERVER></EnvironmentVariables></Exec>"
# Not: EnvironmentVariables XML Task Scheduler'da doğrudan desteklenmez,
# bu yüzden registry'ye yazar ve agent env'den okur.
[System.Environment]::SetEnvironmentVariable("ORKESTRA_SERVER", $ServerUrl, "User")

# ── 7. Servisi başlat ────────────────────────────────────────────────────────
Write-Ok "Görev başlatılıyor..."
Start-ScheduledTask -TaskName $TaskName

Start-Sleep -Seconds 2
$taskInfo = Get-ScheduledTask -TaskName $TaskName
$lastResult = (Get-ScheduledTaskInfo -TaskName $TaskName).LastTaskResult

if ($taskInfo.State -eq "Running") {
    Write-Ok "Servis çalışıyor"
} else {
    Write-Warn "Servis durumu: $($taskInfo.State) (son kod: $lastResult)"
    Write-Warn "Log dosyası: $LogFile"
}

# ── 8. Windows Firewall ──────────────────────────────────────────────────────
# Agent outbound bağlantı yapar, inbound kural gerekmez.
# Eğer proxy (gost) çalışacaksa 1080 açılır:
# New-NetFirewallRule -DisplayName "Orkestra Proxy" -Direction Inbound -Protocol TCP -LocalPort 1080 -Action Allow

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║               Kurulum Tamamlandı!                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║  Sunucu:  " + $ServerUrl.PadRight(42) + "║") -ForegroundColor Cyan
Write-Host ("║  Log:     " + $LogFile.PadRight(42) + "║") -ForegroundColor Cyan
Write-Host ("║  Durdur:  Stop-ScheduledTask -TaskName " + $TaskName.PadRight(14) + "║") -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Farklı sunucu için:" -ForegroundColor Yellow
Write-Host "  `$env:ORKESTRA_SERVER = 'wss://orkestra.erdoganyesil.org/agent'"
Write-Host "  PowerShell -ExecutionPolicy Bypass -File install-windows.ps1"

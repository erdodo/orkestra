# Orkestra -- Windows Agent Kurulum / Guncelleme Scripti
# Yonetici olarak calistirin:
#   PowerShell -ExecutionPolicy Bypass -File scripts\install-windows.ps1
# WAN sunucusu icin onceden set edin:
#   $env:ORKESTRA_SERVER = "ws://orkestra.erdoganyesil.org:3081/agent"
# Kuruluysa gunceller ve yeniden baslatir.

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/erdodo/orkestra.git"
$InstallDir = "$env:LOCALAPPDATA\Orkestra"
$AgentBin   = "$InstallDir\agent\target\x86_64-pc-windows-gnu\release\agent.exe"
$TaskName   = "OrchestraAgent"
$ServerUrl  = if ($env:ORKESTRA_SERVER) { $env:ORKESTRA_SERVER } else { "ws://192.168.1.50:3081/agent" }

function Write-Ok   { param($msg) Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Warn { param($msg) Write-Host "[!]  $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "[X]  $msg" -ForegroundColor Red; exit 1 }

Write-Host ""
Write-Host "=== Orkestra -- Windows Agent Kurulum ===" -ForegroundColor Cyan
Write-Host ""

# -- 1. Rust (GNU toolchain -- yonetici yetkisi gerekmez) ---------------------
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
if (-not (Get-Command cargo -ErrorAction SilentlyContinue)) {
    Write-Warn "Rust kuruluyor..."
    $rustupExe = "$env:TEMP\rustup-init.exe"
    Invoke-WebRequest -Uri "https://static.rust-lang.org/rustup/dist/x86_64-pc-windows-gnu/rustup-init.exe" -OutFile $rustupExe
    & $rustupExe -y --quiet --default-toolchain stable --default-host x86_64-pc-windows-gnu
    Remove-Item $rustupExe -ErrorAction SilentlyContinue
    $env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
    [System.Environment]::SetEnvironmentVariable("PATH", "$env:USERPROFILE\.cargo\bin;" + [System.Environment]::GetEnvironmentVariable("PATH","User"), "User")
    Write-Ok "Rust kuruldu (GNU)"
} else {
    Write-Ok "Rust: $(rustc --version)"
}

# -- 2. GNU linker (gcc) -- winget veya scoop ile kullanici dizinine ----------
$gccOk = Get-Command gcc -ErrorAction SilentlyContinue
if (-not $gccOk) {
    Write-Warn "GCC (MinGW) kuruluyor..."

    # Scoop varsa (kullanici yetkisiyle calisir)
    if (Get-Command scoop -ErrorAction SilentlyContinue) {
        scoop install mingw
    } else {
        # Scoop'u once kur (kullanici dizinine, yonetici gerektirmez)
        Write-Warn "Scoop kuruluyor..."
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
        scoop install mingw
    }
    $env:PATH = "$env:USERPROFILE\scoop\apps\mingw\current\bin;$env:PATH"
    Write-Ok "GCC kuruldu"
} else {
    Write-Ok "GCC mevcut: $($gccOk.Source)"
}

# Rust'in GNU target'ini aktif et
$env:PATH = "$env:USERPROFILE\.cargo\bin;$env:PATH"
rustup target add x86_64-pc-windows-gnu 2>$null | Out-Null
rustup toolchain install stable-x86_64-pc-windows-gnu --no-self-update 2>$null | Out-Null

# -- 3. Git -------------------------------------------------------------------
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    Write-Warn "Git kuruluyor (scoop)..."
    if (-not (Get-Command scoop -ErrorAction SilentlyContinue)) {
        Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser -Force
        Invoke-RestMethod -Uri https://get.scoop.sh | Invoke-Expression
        $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
    }
    scoop install git
    $env:PATH = "$env:USERPROFILE\scoop\shims;$env:PATH"
}

# -- 4. Repo klonla / guncelle ------------------------------------------------
if (Test-Path "$InstallDir\.git") {
    Write-Warn "Guncelleniyor..."
    Push-Location $InstallDir
    git pull --rebase
    Pop-Location
} else {
    Write-Warn "Klonlaniyor -> $InstallDir"
    New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    git clone $RepoUrl $InstallDir
    if ($LASTEXITCODE -ne 0) { Write-Err "git clone basarisiz oldu." }
}

# -- 4. Agent derle -----------------------------------------------------------
Write-Ok "Agent derleniyor (bu birkas dakika surebilir)..."
Push-Location "$InstallDir\agent"
$ErrorActionPreference = "Continue"
cargo build --release --target x86_64-pc-windows-gnu
$buildExit = $LASTEXITCODE
$ErrorActionPreference = "Stop"
Pop-Location

if ($buildExit -ne 0) { Write-Err "cargo build basarisiz (exit $buildExit)" }
if (-not (Test-Path $AgentBin)) { Write-Err "Binary bulunamadi: $AgentBin" }
Write-Ok "Binary: $AgentBin"

# -- 5. Task Scheduler --------------------------------------------------------
$existingTask = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($existingTask) {
    Write-Warn "Eski gorev kaldiriliyor..."
    Stop-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
}

[System.Environment]::SetEnvironmentVariable("ORKESTRA_SERVER", $ServerUrl, "User")

$action = New-ScheduledTaskAction -Execute $AgentBin -Argument "--server-url `"$ServerUrl`""
$trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
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

Write-Ok "Gorev olusturuldu, baslatiliyor..."
Start-ScheduledTask -TaskName $TaskName
Start-Sleep -Seconds 2

$state = (Get-ScheduledTask -TaskName $TaskName).State
Write-Ok "Gorev durumu: $state"

# -- Ozet ---------------------------------------------------------------------
Write-Host ""
Write-Host "=== Kurulum Tamamlandi ===" -ForegroundColor Green
Write-Host "  Sunucu : $ServerUrl" -ForegroundColor White
Write-Host "  Durdur : Stop-ScheduledTask -TaskName $TaskName" -ForegroundColor White
Write-Host ""

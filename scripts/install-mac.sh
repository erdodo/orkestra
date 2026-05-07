#!/usr/bin/env bash
# Orkestra — macOS Agent Kurulum / Güncelleme Scripti
# Kullanım: bash install-mac.sh
# Yüklüyse günceller ve yeniden başlatır.

set -euo pipefail

REPO_URL="git@github.com:erdodo/orkestra.git"
INSTALL_DIR="$HOME/.local/share/orkestra"
AGENT_BIN="$HOME/.local/bin/orkestra-agent"
PLIST_LABEL="org.erdoganyesil.orkestra-agent"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
SERVER_URL="${ORKESTRA_SERVER:-ws://192.168.1.50:3081/agent}"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║     Orkestra — macOS Agent Setup    ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Rust / cargo ─────────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
  warn "Rust kuruluyor..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
  source "$HOME/.cargo/env"
  info "Rust $(rustc --version) kuruldu"
else
  info "Rust $(rustc --version) zaten yüklü"
fi
source "$HOME/.cargo/env" 2>/dev/null || true

# ── 2. Git ───────────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  error "git bulunamadı. Xcode Command Line Tools kurun: xcode-select --install"
fi

# ── 3. Repo klonla / güncelle ────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Mevcut kurulum güncelleniyor..."
  git -C "$INSTALL_DIR" pull --rebase
else
  warn "Repo klonlanıyor..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# ── 4. Agent derle ───────────────────────────────────────────────────────────
info "Agent derleniyor (release)..."
cargo build --release --manifest-path "$INSTALL_DIR/agent/Cargo.toml"

# ── 5. Binary kopyala ────────────────────────────────────────────────────────
mkdir -p "$HOME/.local/bin"
cp "$INSTALL_DIR/agent/target/release/agent" "$AGENT_BIN"
chmod +x "$AGENT_BIN"
info "Binary: $AGENT_BIN"

# ── 6. LaunchAgent plist ────────────────────────────────────────────────────
# Önce çalışıyorsa durdur
if launchctl list "$PLIST_LABEL" &>/dev/null; then
  warn "Önceki servis durduruluyor..."
  launchctl unload "$PLIST_PATH" 2>/dev/null || true
fi

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>${PLIST_LABEL}</string>

  <key>ProgramArguments</key>
  <array>
    <string>${AGENT_BIN}</string>
    <string>--server-url</string>
    <string>${SERVER_URL}</string>
  </array>

  <key>EnvironmentVariables</key>
  <dict>
    <key>ORKESTRA_SERVER</key>
    <string>${SERVER_URL}</string>
  </dict>

  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>

  <key>StandardOutPath</key>
  <string>${HOME}/Library/Logs/orkestra-agent.log</string>
  <key>StandardErrorPath</key>
  <string>${HOME}/Library/Logs/orkestra-agent.log</string>

  <key>ThrottleInterval</key>
  <integer>10</integer>
</dict>
</plist>
EOF

# ── 7. Servisi başlat ────────────────────────────────────────────────────────
launchctl load -w "$PLIST_PATH"
sleep 1

if launchctl list "$PLIST_LABEL" &>/dev/null; then
  STATUS=$(launchctl list "$PLIST_LABEL" | awk '/PID/{print $1}')
  info "Servis çalışıyor (PID: ${STATUS:-bilinmiyor})"
else
  warn "Servis başlatılamadı. Log: $HOME/Library/Logs/orkestra-agent.log"
fi

echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║               Kurulum Tamamlandı!                   ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Sunucu:  %-42s║\n" "$SERVER_URL"
printf "║  Log:     tail -f ~/Library/Logs/%-20s║\n" "orkestra-agent.log"
printf "║  Durdur:  launchctl unload %-26s║\n" "$PLIST_PATH"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
echo "Farklı sunucu için:"
echo "  ORKESTRA_SERVER=wss://orkestra.erdoganyesil.org/agent bash install-mac.sh"

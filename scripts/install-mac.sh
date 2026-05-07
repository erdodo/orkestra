#!/usr/bin/env bash
# Orkestra — macOS Agent Kurulum / Güncelleme Scripti
# Kullanım: bash scripts/install-mac.sh
# Kuruluysa günceller ve yeniden başlatır.
# WAN sunucusu için: ORKESTRA_SERVER=ws://orkestra.erdoganyesil.org:3081/agent bash scripts/install-mac.sh

set -euo pipefail

REPO_URL="https://github.com/erdodo/orkestra.git"
INSTALL_DIR="$HOME/.local/share/orkestra"
AGENT_BIN="$HOME/.local/bin/orkestra-agent"
PLIST_LABEL="org.erdoganyesil.orkestra-agent"
PLIST_PATH="$HOME/Library/LaunchAgents/${PLIST_LABEL}.plist"
SERVER_URL="${ORKESTRA_SERVER:-ws://192.168.1.50:3081/agent}"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║    Orkestra — macOS Agent Kurulum   ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Rust ──────────────────────────────────────────────────────────────────
if ! command -v cargo &>/dev/null; then
  warn "Rust kuruluyor..."
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --quiet
fi
source "$HOME/.cargo/env" 2>/dev/null || true
command -v cargo &>/dev/null || error "cargo bulunamadı, terminali yeniden başlatıp tekrar deneyin."
info "Rust $(rustc --version)"

# ── 2. Git ───────────────────────────────────────────────────────────────────
command -v git &>/dev/null || error "git bulunamadı: xcode-select --install"

# ── 3. Repo klonla / güncelle ────────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Güncelleniyor..."
  git -C "$INSTALL_DIR" pull --rebase
else
  warn "Klonlanıyor..."
  mkdir -p "$(dirname "$INSTALL_DIR")"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

# ── 4. Derle ─────────────────────────────────────────────────────────────────
info "Agent derleniyor..."
cargo build --release --manifest-path "$INSTALL_DIR/agent/Cargo.toml"

mkdir -p "$HOME/.local/bin"
cp "$INSTALL_DIR/agent/target/release/agent" "$AGENT_BIN"
chmod +x "$AGENT_BIN"
info "Binary: $AGENT_BIN"

# ── 5. LaunchAgent ───────────────────────────────────────────────────────────
launchctl unload "$PLIST_PATH" 2>/dev/null || true

mkdir -p "$HOME/Library/LaunchAgents"
cat > "$PLIST_PATH" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN"
  "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>          <string>${PLIST_LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${AGENT_BIN}</string>
    <string>--server-url</string>
    <string>${SERVER_URL}</string>
  </array>
  <key>RunAtLoad</key>      <true/>
  <key>KeepAlive</key>      <true/>
  <key>ThrottleInterval</key><integer>10</integer>
  <key>StandardOutPath</key> <string>${HOME}/Library/Logs/orkestra-agent.log</string>
  <key>StandardErrorPath</key><string>${HOME}/Library/Logs/orkestra-agent.log</string>
</dict>
</plist>
EOF

launchctl load -w "$PLIST_PATH"
sleep 1

# ── Özet ─────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║            Kurulum Tamamlandı!                      ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Sunucu: %-43s║\n" "$SERVER_URL"
printf "║  Log:    tail -f ~/Library/Logs/orkestra-agent.log  ║\n"
printf "║  Durdur: launchctl unload ~/Library/LaunchAgents/   ║\n"
printf "║          %-43s║\n" "${PLIST_LABEL}.plist"
echo "╚══════════════════════════════════════════════════════╝"

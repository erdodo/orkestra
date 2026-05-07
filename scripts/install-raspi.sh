#!/usr/bin/env bash
# Orkestra — Raspberry Pi Kurulum / Güncelleme Scripti
# Kullanım: bash scripts/install-raspi.sh   (sudo OLMADAN çalıştır)
# /home/erdogan/orkestra altına kurar, yalnızca systemd için sudo ister.

set -euo pipefail

REPO_URL="https://github.com/erdodo/orkestra.git"
INSTALL_DIR="$HOME/orkestra"
SERVICE_NAME="orkestra"
PORT=3081
NODE_VERSION="22"

GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; NC='\033[0m'
info() { echo -e "${GREEN}[✓]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

[[ "$(id -u)" == "0" ]] && error "sudo olmadan çalıştır: bash scripts/install-raspi.sh"

echo ""
echo "=== Orkestra — Raspi Kurulum ==="
echo "Dizin: $INSTALL_DIR"
echo ""

# ── 1. Node.js ───────────────────────────────────────────────────────────────
if ! command -v node &>/dev/null; then
  warn "Node.js $NODE_VERSION kuruluyor..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
fi
info "Node.js $(node --version)"

# ── 2. Git ───────────────────────────────────────────────────────────────────
command -v git &>/dev/null || sudo apt-get install -y git

# ── 3. Repo klonla / güncelle ────────────────────────────────────────────────
FIRST_INSTALL=false
if [[ -d "$INSTALL_DIR/.git" ]]; then
  warn "Güncelleniyor..."
  git -C "$INSTALL_DIR" pull --rebase
else
  warn "Klonlanıyor → $INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
  FIRST_INSTALL=true
fi

cd "$INSTALL_DIR/server"

# ── 4. Bağımlılıklar ─────────────────────────────────────────────────────────
info "npm bağımlılıkları..."
if [[ "$FIRST_INSTALL" == true ]]; then
  npm ci
else
  npm install --prefer-offline
fi

# ── 5. .env ──────────────────────────────────────────────────────────────────
if [[ ! -f ".env" ]]; then
  printf 'DATABASE_URL="file:./dev.db"\nPORT=%s\nNODE_ENV=production\n' "$PORT" > .env
  info ".env oluşturuldu"
fi
grep -q "^PORT=" .env && sed -i "s/^PORT=.*/PORT=$PORT/" .env || echo "PORT=$PORT" >> .env

# ── 6. Veritabanı ────────────────────────────────────────────────────────────
info "Veritabanı migration..."
node node_modules/.bin/prisma migrate deploy

# ── 7. Prisma generate + Build ───────────────────────────────────────────────
info "Prisma client üretiliyor..."
node node_modules/.bin/prisma generate

info "Next.js build alınıyor..."
npm run build

# ── 8. systemd ───────────────────────────────────────────────────────────────
NODE_BIN="$(which node)"
CURRENT_USER="$(whoami)"

sudo tee /etc/systemd/system/${SERVICE_NAME}.service > /dev/null << EOF
[Unit]
Description=Orkestra Server
After=network.target

[Service]
Type=simple
User=${CURRENT_USER}
WorkingDirectory=${INSTALL_DIR}/server
ExecStart=${NODE_BIN} node_modules/.bin/tsx server.ts
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=${PORT}
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable "$SERVICE_NAME"

if sudo systemctl is-active --quiet "$SERVICE_NAME"; then
  sudo systemctl restart "$SERVICE_NAME"
else
  sudo systemctl start "$SERVICE_NAME"
fi

# ── 9. Firewall ──────────────────────────────────────────────────────────────
command -v ufw &>/dev/null && sudo ufw allow "$PORT/tcp" comment "Orkestra" 2>/dev/null || true

# ── Özet ─────────────────────────────────────────────────────────────────────
echo ""
echo "=== Kurulum Tamamlandı! ==="
echo "  Yerel : http://192.168.1.50:${PORT}/dashboard"
echo "  WAN   : http://orkestra.erdoganyesil.org:${PORT}/dashboard"
echo "  Log   : journalctl -u orkestra -f"
echo "  Dizin : $INSTALL_DIR"
echo ""
info "Servis: $(sudo systemctl is-active $SERVICE_NAME)"

#!/usr/bin/env bash
# Orkestra — Raspberry Pi Tek Adım Kurulum Scripti
# Kullanım: curl -fsSL https://raw.githubusercontent.com/erdodo/orkestra/main/scripts/install-raspi.sh | bash
# veya: bash install-raspi.sh

set -euo pipefail

REPO_URL="git@github.com:erdodo/orkestra.git"
INSTALL_DIR="/opt/orkestra"
SERVICE_NAME="orkestra"
PORT=3081
NODE_VERSION="22"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
error() { echo -e "${RED}[✗]${NC} $1"; exit 1; }

echo ""
echo "╔══════════════════════════════════════╗"
echo "║       Orkestra — Raspi Kurulum       ║"
echo "╚══════════════════════════════════════╝"
echo ""

# ── 1. Node.js ──────────────────────────────────────────────────────────────
if command -v node &>/dev/null && [[ $(node -e "process.exit(parseInt(process.version.slice(1)) >= 22 ? 0 : 1)" 2>/dev/null; echo $?) -eq 0 ]]; then
  info "Node.js $(node --version) zaten yüklü"
else
  warn "Node.js $NODE_VERSION kuruluyor..."
  curl -fsSL "https://deb.nodesource.com/setup_${NODE_VERSION}.x" | sudo -E bash -
  sudo apt-get install -y nodejs
  info "Node.js $(node --version) kuruldu"
fi

# ── 2. Git ───────────────────────────────────────────────────────────────────
if ! command -v git &>/dev/null; then
  warn "git kuruluyor..."
  sudo apt-get install -y git
fi

# ── 3. Repo klonla / güncelle ─────────────────────────────────────────────
if [[ -d "$INSTALL_DIR/.git" ]]; then
  info "Mevcut kurulum güncelleniyor..."
  sudo -u "${SUDO_USER:-pi}" git -C "$INSTALL_DIR" pull --rebase
else
  warn "Repo klonlanıyor: $REPO_URL → $INSTALL_DIR"
  sudo mkdir -p "$INSTALL_DIR"
  sudo chown "${SUDO_USER:-pi}:${SUDO_USER:-pi}" "$INSTALL_DIR"
  git clone "$REPO_URL" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR/server"

# ── 4. npm bağımlılıkları ────────────────────────────────────────────────────
info "npm bağımlılıkları yükleniyor..."
npm ci --prefer-offline 2>/dev/null || npm install

# ── 5. .env ──────────────────────────────────────────────────────────────────
if [[ ! -f ".env" ]]; then
  cp .env.example .env
  info ".env oluşturuldu (varsayılan ayarlar)"
fi

# PORT satırını zorla güncelle
if grep -q "^PORT=" .env; then
  sed -i "s/^PORT=.*/PORT=$PORT/" .env
else
  echo "PORT=$PORT" >> .env
fi

# ── 6. Prisma migrate ─────────────────────────────────────────────────────────
info "Veritabanı migration'ları çalıştırılıyor..."
node node_modules/.bin/prisma migrate deploy

# ── 7. Next.js build ─────────────────────────────────────────────────────────
info "Next.js production build alınıyor... (bu birkaç dakika sürebilir)"
npm run build

# ── 8. systemd servis ────────────────────────────────────────────────────────
NODE_BIN="$(which node)"
CURRENT_USER="${SUDO_USER:-pi}"

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
  info "Servis yeniden başlatılıyor..."
  sudo systemctl restart "$SERVICE_NAME"
else
  sudo systemctl start "$SERVICE_NAME"
fi

# ── 9. cloudflared (opsiyonel) ────────────────────────────────────────────────
echo ""
read -rp "Cloudflare Tunnel kurulsun mu? [e/H] " install_cf
if [[ "$install_cf" =~ ^[Ee]$ ]]; then
  ARCH=$(uname -m)
  CF_ARCH="arm64"
  [[ "$ARCH" == "armv7l" ]] && CF_ARCH="arm"
  [[ "$ARCH" == "x86_64" ]] && CF_ARCH="amd64"

  curl -fsSL "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${CF_ARCH}" \
    -o /tmp/cloudflared
  sudo install -m 755 /tmp/cloudflared /usr/local/bin/cloudflared

  echo ""
  warn "Cloudflare hesabına giriş yapılıyor..."
  cloudflared tunnel login
  cloudflared tunnel create orkestra || true
  cloudflared tunnel route dns orkestra orkestra.erdoganyesil.org || true

  TUNNEL_ID=$(cloudflared tunnel list --output json 2>/dev/null | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
  CF_CRED_FILE="$HOME/.cloudflared/${TUNNEL_ID}.json"

  mkdir -p "$HOME/.cloudflared"
  cat > "$HOME/.cloudflared/config.yml" << CFEOF
tunnel: ${TUNNEL_ID}
credentials-file: ${CF_CRED_FILE}

ingress:
  - hostname: orkestra.erdoganyesil.org
    service: http://localhost:${PORT}
  - service: http_status:404
CFEOF

  sudo cloudflared service install
  sudo systemctl start cloudflared

  info "Cloudflare Tunnel aktif → https://orkestra.erdoganyesil.org"
fi

# ── 10. Firewall ─────────────────────────────────────────────────────────────
if command -v ufw &>/dev/null; then
  sudo ufw allow "$PORT/tcp" comment "Orkestra" 2>/dev/null || true
  info "Firewall: port $PORT açıldı"
fi

# ── Özet ──────────────────────────────────────────────────────────────────────
echo ""
echo "╔══════════════════════════════════════════════════════╗"
echo "║               Kurulum Tamamlandı!                   ║"
echo "╠══════════════════════════════════════════════════════╣"
printf "║  Yerel:  http://%-36s║\n" "192.168.1.50:${PORT}/dashboard"
printf "║  Tünel:  https://%-35s║\n" "orkestra.erdoganyesil.org/dashboard"
printf "║  Log:    sudo journalctl -u %-25s║\n" "${SERVICE_NAME} -f"
echo "╚══════════════════════════════════════════════════════╝"
echo ""
info "Servis durumu: $(sudo systemctl is-active $SERVICE_NAME)"

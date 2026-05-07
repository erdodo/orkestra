# Orkestra — Kurulum Kılavuzu

## Mimari

```
┌──────────────────────────────────────────┐
│       Raspberry Pi — 192.168.1.50        │
│       orkestra.erdoganyesil.org:3081     │
│                                          │
│  Next.js 16 + WebSocket  :3081           │
│  Prisma 7 + SQLite                       │
│  systemd servisi                         │
└─────────────────┬────────────────────────┘
                  │
        ┌─────────┴─────────┐
        │                   │
┌───────▼──────┐   ┌────────▼─────┐
│ MacBook Air  │   │  Windows PC  │
│ Rust Agent   │   │  Rust Agent  │
└──────────────┘   └──────────────┘
```

**LAN:** `ws://192.168.1.50:3081/agent`
**WAN:** `ws://orkestra.erdoganyesil.org:3081/agent` (router'da 3081 → 192.168.1.50:3081 port yönlendirmesi yapıldı)

---

## Port Tablosu

| Port | Kullanım |
|------|---------|
| **3081** | Next.js sunucu + WebSocket (`/agent`, `/ui`) — router'da WAN'a yönlendirildi |
| **1080** | SOCKS5 proxy (gost, agent tarafında açılır) |

---

## 1. Raspberry Pi Kurulumu

> Tek adımda kurmak için: `bash scripts/install-raspi.sh`

Manuel adımlar:

```bash
# Node.js 22
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs git

# Projeyi çek
git clone https://github.com/erdodo/orkestra.git /opt/orkestra
cd /opt/orkestra/server

# Bağımlılıklar + DB + Build
npm install
node node_modules/.bin/prisma migrate deploy
npm run build

# .env
cp .env.example .env   # içeriği: DATABASE_URL="file:./dev.db"  PORT=3081
```

**systemd servisi:**

```bash
sudo tee /etc/systemd/system/orkestra.service > /dev/null << 'EOF'
[Unit]
Description=Orkestra Server
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/opt/orkestra/server
ExecStart=/usr/bin/node node_modules/.bin/tsx server.ts
Restart=always
RestartSec=5
Environment=NODE_ENV=production
Environment=PORT=3081

[Install]
WantedBy=multi-user.target
EOF

sudo systemctl daemon-reload
sudo systemctl enable --now orkestra
sudo journalctl -u orkestra -f
```

Dashboard: `http://192.168.1.50:3081/dashboard`

---

## 2. macOS Agent

> Tek adımda kurmak için: `bash scripts/install-mac.sh`
>
> Script kuruluysa günceller, LaunchAgent ile oturum açıldığında otomatik başlar.

---

## 3. Windows Agent

> Tek adımda kurmak için (Yönetici PowerShell):
> `PowerShell -ExecutionPolicy Bypass -File scripts\install-windows.ps1`
>
> Script kuruluysa günceller, Task Scheduler ile otomatik başlar.

---

## 4. Agent Ayarları

| Env Değişkeni | Varsayılan | Açıklama |
|---------------|------------|---------|
| `ORKESTRA_SERVER` | `ws://192.168.1.50:3081/agent` | Sunucu WebSocket adresi |
| `ORKESTRA_API_KEY` | *(boş)* | API anahtarı (ileride) |

WAN üzerinden bağlanmak için:

```bash
ORKESTRA_SERVER=ws://orkestra.erdoganyesil.org:3081/agent bash scripts/install-mac.sh
```

---

## 5. Geliştirme (Yerel)

```bash
# Terminal 1
cd server && npm run dev

# Terminal 2
cd agent && cargo build && ./target/debug/agent --heartbeat-interval 30

# Dashboard
open http://localhost:3081/dashboard
```

---

## 6. Sorun Giderme

| Belirti | Çözüm |
|---------|-------|
| `no such table: Device` | `node node_modules/.bin/prisma migrate deploy` |
| Agent bağlanamıyor | Router'da 3081 port yönlendirmesini kontrol et |
| `MODULE_NOT_FOUND @/app/generated/prisma` | `npm run db:generate` |

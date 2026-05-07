# Orkestra — Kurulum Kılavuzu

## Mimari Özet

```
┌──────────────────────────────────────────┐
│       Raspberry Pi — 192.168.1.50        │
│                                          │
│  Next.js 16 + WebSocket Server           │
│  Port 3081 (HTTP + WS)                   │
│                                          │
│  Prisma 7 + SQLite (./dev.db)            │
│                                          │
│  Cloudflare Tunnel → orkestra.erdoganyesil.org │
└─────────────────┬────────────────────────┘
                  │ ws://192.168.1.50:3081/agent  (LAN)
                  │ wss://orkestra.erdoganyesil.org/agent  (WAN)
         ┌────────┴────────┐
         │                 │
┌────────▼─────┐  ┌────────▼─────┐
│ MacBook Air  │  │  Windows PC  │
│ Rust Agent   │  │  Rust Agent  │
│ (macos ARM)  │  │  (windows)   │
└──────────────┘  └──────────────┘
```

---

## Port Tablosu

| Port | Protokol | Kullanım |
|------|----------|---------|
| **3081** | HTTP + WS | Next.js sunucu + WebSocket (`/agent`, `/ui`) |
| **1080** | TCP (SOCKS5) | `gost` proxy sunucusu (agent tarafında) |
| **3389** | TCP | RustDesk relay (isteğe bağlı, yerel) |
| **21116** | TCP/UDP | RustDesk sinyal sunucusu (isteğe bağlı) |
| **7070** | UDP | Opus ses köprüsü (ilerleyen aşamada) |

> Cloudflare Tunnel **sadece 3081 portunu** → `orkestra.erdoganyesil.org` olarak dışarıya açar. Diğer portlar LAN'da kalır.

---

## 1. Raspberry Pi — Native Kurulum (Önerilen)

### Neden Docker değil?

- Raspberry Pi 4/5 üzerinde Docker ek overhead yaratır (~100-200 MB RAM).
- SQLite dosyası volume mount gerektirip karmaşıklaşır.
- `systemd` servisi daha hafif, otomatik restart ve log yönetimi sunar.
- **Docker tercih edilir durum:** Birden fazla servis (RustDesk relay, gost sunucu) aynı makinede çalışacaksa.

---

### 1.1 Node.js Kurulumu (Raspi OS / Debian)

```bash
curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash -
sudo apt-get install -y nodejs git
node --version   # v22.x
```

### 1.2 Projeyi Klonla

```bash
git clone https://github.com/<kullanici>/orkestra.git /opt/orkestra
cd /opt/orkestra/server
npm install
```

### 1.3 Veritabanı Hazırla

```bash
node node_modules/.bin/prisma migrate deploy
# Tablolar oluşturulur: Device, Session, SyncJob, ProxyConfig
```

### 1.4 Ortam Değişkenleri

```bash
cp .env.example .env
# .env içeriği:
# DATABASE_URL="file:./dev.db"
# PORT=3081
# NODE_ENV=production
```

### 1.5 Production Build + Çalıştırma

```bash
npm run build
npm run start
# → Orkestra sunucu çalışıyor: http://0.0.0.0:3081
```

### 1.6 systemd Servis (Otomatik Başlatma)

```bash
sudo nano /etc/systemd/system/orkestra.service
```

```ini
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
```

```bash
sudo systemctl daemon-reload
sudo systemctl enable orkestra
sudo systemctl start orkestra
sudo journalctl -u orkestra -f   # logları izle
```

---

## 2. Cloudflare Tunnel (Global Erişim)

Cloudflare Tunnel, sabit IP veya port yönlendirmesi olmadan internetten erişim sağlar.

### 2.1 cloudflared Kurulumu (Raspi)

```bash
curl -L https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64 \
  -o /usr/local/bin/cloudflared
chmod +x /usr/local/bin/cloudflared
cloudflared --version
```

### 2.2 Tunnel Oluştur

```bash
cloudflared tunnel login          # tarayıcıda auth
cloudflared tunnel create orkestra
cloudflared tunnel route dns orkestra orkestra.erdoganyesil.org
```

### 2.3 Tunnel Yapılandırması

```yaml
# ~/.cloudflared/config.yml
tunnel: <TUNNEL_ID>
credentials-file: /home/pi/.cloudflared/<TUNNEL_ID>.json

ingress:
  - hostname: orkestra.erdoganyesil.org
    service: http://localhost:3081
  - service: http_status:404
```

### 2.4 Tunnel'ı systemd ile Çalıştır

```bash
sudo cloudflared service install
sudo systemctl start cloudflared
```

> **Agent URL'i:** Tunnel aktifken agentlar `wss://orkestra.erdoganyesil.org/agent` adresine bağlanır.
> LAN içindeyken `ws://192.168.1.50:3081/agent` daha düşük gecikmeyle çalışır.

---

## 3. Rust Agent — Kurulum

### 3.1 macOS (ARM)

```bash
cd /path/to/orkestra/agent
cargo build --release

# Çalıştır:
ORKESTRA_SERVER=ws://192.168.1.50:3081/agent \
  ./target/release/agent

# Veya tunnel üzerinden:
ORKESTRA_SERVER=wss://orkestra.erdoganyesil.org/agent \
  ./target/release/agent
```

### 3.2 Windows

```powershell
cd C:\path\to\orkestra\agent
cargo build --release --target x86_64-pc-windows-msvc

# Çalıştır:
$env:ORKESTRA_SERVER = "ws://192.168.1.50:3081/agent"
.\target\release\agent.exe

# Autostart (Task Scheduler veya NSSM):
nssm install OrchestraAgent "C:\orkestra\agent\target\release\agent.exe"
nssm set OrchestraAgent AppEnvironmentExtra "ORKESTRA_SERVER=ws://192.168.1.50:3081/agent"
nssm start OrchestraAgent
```

### 3.3 Agent Parametreleri

| Parametre | Env Değişkeni | Varsayılan |
|-----------|---------------|------------|
| `--server-url` | `ORKESTRA_SERVER` | `ws://192.168.1.50:3081/agent` |
| `--api-key` | `ORKESTRA_API_KEY` | *(boş)* |
| `--heartbeat-interval` | — | `5` saniye |
| `--reconnect-delay` | — | `3` saniye |
| `--max-reconnect-delay` | — | `30` saniye |

---

## 4. Docker Kurulumu (İsteğe Bağlı)

RustDesk relay veya gost gibi ek servisler çalıştırmak istersen:

### `docker-compose.yml`

```yaml
version: "3.9"

services:
  orkestra:
    build:
      context: ./server
      dockerfile: Dockerfile
    ports:
      - "3081:3081"
    volumes:
      - orkestra_db:/app/dev.db
    environment:
      - NODE_ENV=production
      - PORT=3081
      - DATABASE_URL=file:/app/dev.db
    restart: unless-stopped

  gost:
    image: gogost/gost:3
    ports:
      - "1080:1080"
    command: "-L socks5://:1080"
    restart: unless-stopped

  cloudflared:
    image: cloudflare/cloudflared:latest
    command: tunnel --no-autoupdate run
    volumes:
      - ~/.cloudflared:/etc/cloudflared:ro
    restart: unless-stopped
```

### `server/Dockerfile`

```dockerfile
FROM node:22-alpine AS base
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev

FROM base AS builder
COPY . .
RUN npm run build

FROM node:22-alpine AS runner
WORKDIR /app
COPY --from=builder /app/.next ./.next
COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/package.json ./package.json
COPY --from=builder /app/server.ts ./server.ts
COPY --from=builder /app/lib ./lib
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/app/generated ./app/generated

ENV NODE_ENV=production
EXPOSE 3081
CMD ["node", "node_modules/.bin/tsx", "server.ts"]
```

```bash
docker compose up -d
docker compose logs -f orkestra
```

---

## 5. Bağlantı Topolojisi Özeti

```
[MacBook / Windows]                  [Raspberry Pi]
      │                                    │
      │  LAN: ws://192.168.1.50:3081/agent │
      ├────────────────────────────────────►│
      │                                    │ :3081
      │  WAN: wss://orkestra.erdoganyesil.org/agent │
      ├────────────────────────────────────►│
                                           │
                                    Cloudflare Tunnel
                                           │
                                    İnternet (443/HTTPS)
```

- **Heartbeat:** Agent → Server, 5s aralıkla CPU/RAM/VPN durumu
- **Komutlar:** Dashboard → Server (REST) → Agent (WebSocket)
- **Sonuçlar:** Agent → Server (WS) → Dashboard (WS `/ui`)
- **Tunnel URL:** Agent → Server (WS `TUNNEL_URL`) → Dashboard

---

## 6. Geliştirme Ortamı (Yerel Test)

```bash
# Terminal 1 — Server
cd server
~/.nvm/versions/node/v22.22.1/bin/node node_modules/.bin/tsx server.ts

# Terminal 2 — Agent (düşük heartbeat ile test)
cd agent
cargo build
./target/debug/agent --heartbeat-interval 30

# Dashboard
open http://localhost:3081/dashboard
```

---

## 7. Güvenlik Notları (Auth Eklemeden Önce)

- Şu an **kimlik doğrulama yok** — sadece LAN veya güvenilen Cloudflare Tunnel üzerinden kullan.
- `ORKESTRA_API_KEY` alanı schema'da mevcut, ileride WS handshake'e eklenecek.
- Dashboard'a erişimi kısıtlamak için Cloudflare Access kullanılabilir (ücretsiz).

---

## 8. Sorun Giderme

| Belirti | Çözüm |
|---------|-------|
| `no such table: Device` | `node node_modules/.bin/prisma migrate deploy` çalıştır |
| Agent bağlanamıyor | Port 3081'in firewall'da açık olduğunu kontrol et |
| `MODULE_NOT_FOUND @/app/generated/prisma` | `npm run db:generate` çalıştır |
| MacBook crash (yüksek CPU) | `--heartbeat-interval 30` ile başlat, `check_vpn_active` process spawn içermez |
| Cloudflare Tunnel bağlanamıyor | `cloudflared tunnel list` ile tunnel ID'yi doğrula |

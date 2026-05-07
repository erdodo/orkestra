import { WebSocketServer, WebSocket } from "ws";
import { IncomingMessage } from "http";
import { db } from "./db";

export interface AgentMessage {
  type: string;
  [key: string]: unknown;
}

export interface ConnectedAgent {
  ws: WebSocket;
  deviceId: string;
  hostname: string;
}

const agents = new Map<string, ConnectedAgent>();

let wss: WebSocketServer | null = null;

export function getAgents() {
  return agents;
}

export function broadcastToUI(data: unknown) {
  const json = JSON.stringify(data);
  wss?.clients.forEach((client) => {
    if (
      client.readyState === WebSocket.OPEN &&
      !(client as WebSocket & { isAgent?: boolean }).isAgent
    ) {
      client.send(json);
    }
  });
}

export function sendToAgent(hostname: string, payload: unknown): boolean {
  const agent = agents.get(hostname);
  if (!agent || agent.ws.readyState !== WebSocket.OPEN) return false;
  agent.ws.send(JSON.stringify(payload));
  return true;
}

export function sendToAgentById(deviceId: string, payload: unknown): boolean {
  for (const agent of agents.values()) {
    if (agent.deviceId === deviceId) {
      if (agent.ws.readyState !== WebSocket.OPEN) return false;
      agent.ws.send(JSON.stringify(payload));
      return true;
    }
  }
  return false;
}

async function handleAgentMessage(
  ws: WebSocket & { isAgent?: boolean; hostname?: string },
  raw: string
) {
  let msg: AgentMessage;
  try {
    msg = JSON.parse(raw);
  } catch {
    return;
  }

  switch (msg.type) {
    case "REGISTER": {
      const { hostname, platform, local_ip } = msg as {
        hostname: string;
        platform: string;
        local_ip?: string;
        type: string;
      };

      let device = await db.device.findUnique({ where: { hostname } });
      if (!device) {
        device = await db.device.create({
          data: { hostname, platform, localIp: local_ip },
        });
      } else {
        device = await db.device.update({
          where: { hostname },
          data: {
            online: true,
            localIp: local_ip ?? device.localIp,
            platform,
          },
        });
      }

      ws.isAgent = true;
      ws.hostname = hostname;
      agents.set(hostname, { ws, deviceId: device.id, hostname });

      ws.send(
        JSON.stringify({
          type: "REGISTERED",
          device_id: device.id,
          api_key: device.apiKey,
        })
      );

      broadcastToUI({ type: "DEVICE_ONLINE", device });
      console.log(`[WS] Agent kayıtlı: ${hostname} (${platform})`);
      break;
    }

    case "HEARTBEAT": {
      const { cpu, ram, vpn_active, proxy_port, rustdesk_id, hostname } =
        msg as {
          cpu: number;
          ram: number;
          vpn_active?: boolean;
          proxy_port?: number;
          rustdesk_id?: string;
          hostname: string;
          type: string;
        };

      const host = ws.hostname ?? hostname;
      if (!host) break;

      const device = await db.device.update({
        where: { hostname: host },
        data: {
          online: true,
          cpu,
          ram,
          vpnActive: vpn_active ?? false,
          proxyPort: proxy_port,
          rustdeskId: rustdesk_id,
        },
      });

      broadcastToUI({
        type: "HEARTBEAT",
        device_id: device.id,
        hostname: host,
        cpu,
        ram,
        vpn_active: vpn_active ?? false,
        proxy_port,
        rustdesk_id,
      });
      break;
    }

    case "CMD_RESULT": {
      broadcastToUI(msg);
      break;
    }

    case "VPN_STATUS": {
      const { connected, proxy_port } = msg as {
        connected: boolean;
        proxy_port?: number;
        type: string;
      };
      const host = ws.hostname;
      if (host) {
        await db.device.update({
          where: { hostname: host },
          data: { vpnActive: connected, proxyPort: proxy_port },
        });
      }
      broadcastToUI(msg);
      break;
    }

    case "SYNC_STATUS": {
      broadcastToUI(msg);
      break;
    }

    case "TUNNEL_URL": {
      broadcastToUI(msg);
      break;
    }

    case "AUDIO_STATUS": {
      broadcastToUI(msg);
      break;
    }

    default:
      broadcastToUI(msg);
  }
}

export function initWebSocketServer(server: import("http").Server) {
  wss = new WebSocketServer({ noServer: true });

  server.on("upgrade", (req, socket, head) => {
    const pathname = req.url ?? "";
    if (pathname === "/agent" || pathname === "/ui") {
      wss!.handleUpgrade(req, socket as import("net").Socket, head, (ws) => {
        wss!.emit("connection", ws, req);
      });
    }
  });

  wss.on(
    "connection",
    (ws: WebSocket & { isAgent?: boolean; hostname?: string }, req: IncomingMessage) => {
      const ip = req.socket.remoteAddress;
      const path = req.url ?? "";
      console.log(`[WS] Yeni bağlantı: ${ip} (${path})`);

      ws.on("message", (data) => {
        handleAgentMessage(ws, data.toString());
      });

      ws.on("close", async () => {
        if (ws.isAgent && ws.hostname) {
          agents.delete(ws.hostname);
          try {
            const device = await db.device.update({
              where: { hostname: ws.hostname },
              data: { online: false },
            });
            broadcastToUI({ type: "DEVICE_OFFLINE", device });
          } catch {}
          console.log(`[WS] Agent çevrimdışı: ${ws.hostname}`);
        }
      });

      ws.on("error", (err) => {
        console.error("[WS] Hata:", err.message);
      });
    }
  );

  console.log("[WS] WebSocket sunucu başlatıldı");
  return wss;
}

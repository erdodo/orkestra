"use client";

import { useState, useCallback, useEffect } from "react";
import { useOrkestraWS } from "@/app/hooks/useOrkestraWS";
import { DeviceCard, DeviceData } from "@/app/components/DeviceCard";
import { CommandLog, LogEntry } from "@/app/components/CommandLog";
import { OrchestraPanel } from "@/app/components/OrchestraPanel";
import { Activity, Server, Layers } from "lucide-react";

type WSMessage = {
  type: string;
  [key: string]: unknown;
};

export default function DashboardPage() {
  const [devices, setDevices] = useState<DeviceData[]>([]);
  const [logs, setLogs] = useState<LogEntry[]>([]);
  const [tunnelUrls, setTunnelUrls] = useState<Record<string, string>>({});
  const [wsConnected, setWsConnected] = useState(false);

  const handleMessage = useCallback((msg: WSMessage) => {
    switch (msg.type) {
      case "DEVICE_ONLINE": {
        const d = msg.device as DeviceData;
        setDevices((prev) => {
          const idx = prev.findIndex((x) => x.id === d.id);
          if (idx >= 0) {
            const next = [...prev];
            next[idx] = { ...next[idx], ...d, online: true };
            return next;
          }
          return [...prev, { ...d, online: true }];
        });
        break;
      }
      case "DEVICE_OFFLINE": {
        const d = msg.device as DeviceData;
        setDevices((prev) =>
          prev.map((x) => (x.id === d.id ? { ...x, online: false } : x))
        );
        break;
      }
      case "HEARTBEAT": {
        const { device_id, cpu, ram, vpn_active, proxy_port, rustdesk_id } = msg as {
          device_id: string;
          cpu: number;
          ram: number;
          vpn_active: boolean;
          proxy_port?: number;
          rustdesk_id?: string;
          type: string;
        };
        setDevices((prev) =>
          prev.map((x) =>
            x.id === device_id
              ? {
                  ...x,
                  cpu,
                  ram,
                  vpnActive: vpn_active,
                  proxyPort: proxy_port ?? x.proxyPort,
                  rustdeskId: rustdesk_id ?? x.rustdeskId,
                }
              : x
          )
        );
        break;
      }
      case "CMD_RESULT": {
        const { device_id, cmd, stdout, stderr, exit_code } = msg as {
          device_id: string;
          cmd: string;
          stdout?: string;
          stderr?: string;
          exit_code?: number;
          type: string;
        };
        const device = devices.find((d) => d.id === device_id);
        setLogs((prev) => [
          ...prev,
          {
            id: `${Date.now()}-${Math.random()}`,
            deviceId: device_id,
            hostname: device?.hostname ?? device_id,
            cmd,
            stdout,
            stderr,
            exit_code,
            ts: Date.now(),
          },
        ]);
        break;
      }
      case "TUNNEL_URL": {
        const { device_id, url } = msg as { device_id: string; url: string; type: string };
        setTunnelUrls((prev) => ({ ...prev, [device_id]: url }));
        break;
      }
    }
  }, [devices]);

  const wsRef = useOrkestraWS(handleMessage);

  const checkWsConnected = () => {
    setWsConnected(wsRef.current?.readyState === WebSocket.OPEN);
  };

  useEffect(() => {
    const interval = setInterval(checkWsConnected, 2000);
    fetch("/api/devices")
      .then((r) => r.json())
      .then((data: DeviceData[]) => setDevices(data))
      .catch(() => {});
    return () => clearInterval(interval);
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  async function sendCommand(deviceId: string, cmd: string, payload?: string) {
    console.log("[UI] sendCommand:", { deviceId, cmd, payload });
    const res = await fetch("/api/command", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId, cmd, payload }),
    });
    const data = await res.json();
    console.log("[UI] sendCommand sonuç:", res.status, data);
  }

  async function handleProxy(sourceId: string, targetId: string, action: "enable" | "disable") {
    console.log("[UI] handleProxy:", { sourceId, targetId, action });
    const res = await fetch("/api/proxy", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source_device_id: sourceId, target_device_id: targetId, action }),
    });
    const data = await res.json();
    console.log("[UI] handleProxy sonuç:", res.status, data);
  }

  async function handleAudio(sourceId: string, targetId: string, action: "start" | "stop") {
    await fetch("/api/audio", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ source_device_id: sourceId, target_device_id: targetId, action }),
    });
  }

  async function handleTunnel(deviceId: string, action: "start" | "stop") {
    console.log("[UI] handleTunnel:", { deviceId, action });
    const res = await fetch("/api/tunnel", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ device_id: deviceId, action }),
    });
    const data = await res.json();
    console.log("[UI] handleTunnel sonuç:", res.status, data);
  }

  async function handleDevSession(config: {
    local_device_id: string;
    remote_device_id: string;
    sync_source_path: string;
    sync_target_path: string;
    proxy_source_id?: string;
  }) {
    await fetch("/api/dev-session", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(config),
    });
  }

  async function handleSyncCreate(sourceId: string, targetId: string, sourcePath: string, targetPath: string) {
    await fetch("/api/sync", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        source_id: sourceId,
        target_id: targetId,
        source_path: sourcePath,
        target_path: targetPath,
      }),
    });
  }

  const onlineCount = devices.filter((d) => d.online).length;

  return (
    <div className="min-h-screen bg-[#0d0f14]">
      <header className="border-b border-slate-800/60 bg-[#0d0f14]/80 backdrop-blur-sm sticky top-0 z-10">
        <div className="max-w-7xl mx-auto px-4 py-3 flex items-center justify-between">
          <div className="flex items-center gap-3">
            <div className="w-8 h-8 rounded-lg bg-blue-600 flex items-center justify-center">
              <Layers size={16} className="text-white" />
            </div>
            <div>
              <h1 className="text-sm font-bold text-slate-100 leading-tight">Orkestra</h1>
              <p className="text-xs text-slate-500">Cihaz Yönetim Paneli</p>
            </div>
          </div>
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-2 text-xs text-slate-400">
              <Server size={12} />
              <span>{onlineCount}/{devices.length} çevrimiçi</span>
            </div>
            <div className="flex items-center gap-1.5 text-xs">
              <div
                className={`w-1.5 h-1.5 rounded-full ${
                  wsConnected ? "bg-green-400 animate-pulse" : "bg-red-500"
                }`}
              />
              <span className={wsConnected ? "text-green-400" : "text-red-400"}>
                {wsConnected ? "Bağlı" : "Bağlanıyor..."}
              </span>
            </div>
          </div>
        </div>
      </header>

      <main className="max-w-7xl mx-auto px-4 py-6 space-y-6">
        <div className="flex items-center gap-2 text-xs text-slate-500">
          <Activity size={12} />
          <span>
            {devices.length === 0
              ? "Henüz kayıtlı cihaz yok. Agent başlatıldığında otomatik görünür."
              : `${devices.length} kayıtlı cihaz`}
          </span>
        </div>

        <div className="grid grid-cols-1 md:grid-cols-2 xl:grid-cols-3 gap-4">
          {devices.map((device) => (
            <DeviceCard
              key={device.id}
              device={device}
              allDevices={devices}
              onCommand={sendCommand}
              onProxyToggle={handleProxy}
              onAudioToggle={handleAudio}
              onTunnel={handleTunnel}
              tunnelUrl={tunnelUrls[device.id]}
            />
          ))}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-4">
          <OrchestraPanel
            devices={devices}
            onDevSession={handleDevSession}
            onSyncCreate={handleSyncCreate}
          />
          <CommandLog entries={logs} onClear={() => setLogs([])} />
        </div>
      </main>
    </div>
  );
}

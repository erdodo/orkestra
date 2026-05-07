"use client";

import {
    Cpu,
    MemoryStick,
    Shield,
    ShieldOff,
    Monitor,
    Apple,
    Terminal,
    Copy,
    ChevronDown,
    ChevronUp,
    Mic,
    Network,
} from "lucide-react";
import { useState } from "react";

export interface DeviceData {
  id: string;
  hostname: string;
  platform: string;
  localIp: string | null;
  online: boolean;
  cpu: number;
  ram: number;
  vpnActive: boolean;
  proxyPort: number | null;
  rustdeskId: string | null;
  proxyConfig?: { enabled: boolean; proxyHost: string | null; proxyPort: number | null } | null;
}

interface DeviceCardProps {
  device: DeviceData;
  allDevices: DeviceData[];
  onCommand: (deviceId: string, cmd: string, payload?: string) => Promise<void>;
  onProxyToggle: (sourceId: string, targetId: string, action: "enable" | "disable") => Promise<void>;
  onAudioToggle: (sourceId: string, targetId: string, action: "start" | "stop") => Promise<void>;
  onTunnel: (deviceId: string, action: "start" | "stop") => Promise<void>;
  tunnelUrl?: string;
}

function GaugeBar({ value, color }: { value: number; color: string }) {
  return (
    <div className="w-full bg-slate-800 rounded-full h-1.5 overflow-hidden">
      <div
        className={`h-1.5 rounded-full transition-all duration-700 ${color}`}
        style={{ width: `${Math.min(value, 100)}%` }}
      />
    </div>
  );
}

function Badge({ online }: { online: boolean }) {
  return (
    <span
      className={`inline-flex items-center gap-1.5 px-2 py-0.5 rounded-full text-xs font-medium ${
        online
          ? "bg-green-500/15 text-green-400 ring-1 ring-green-500/30"
          : "bg-slate-700/50 text-slate-400 ring-1 ring-slate-600/30"
      }`}
    >
      <span
        className={`w-1.5 h-1.5 rounded-full ${online ? "bg-green-400 animate-pulse" : "bg-slate-500"}`}
      />
      {online ? "Çevrimiçi" : "Çevrimdışı"}
    </span>
  );
}

export function DeviceCard({
  device,
  allDevices,
  onCommand,
  onProxyToggle,
  onAudioToggle,
  onTunnel,
  tunnelUrl,
}: DeviceCardProps) {
  const [expanded, setExpanded] = useState(false);
  const [cmdInput, setCmdInput] = useState("");
  const [loading, setLoading] = useState<string | null>(null);

  const otherOnlineDevices = allDevices.filter(
    (d) => d.id !== device.id && d.online
  );

  const proxyEnabled = device.proxyConfig?.enabled ?? false;
  const cpuColor =
    device.cpu > 80 ? "bg-red-500" : device.cpu > 60 ? "bg-yellow-500" : "bg-blue-500";
  const ramColor =
    device.ram > 80 ? "bg-red-500" : device.ram > 60 ? "bg-yellow-500" : "bg-green-500";

  const platformIcon =
    device.platform === "macos" ? (
      <Apple size={16} className="text-slate-400" />
    ) : (
      <Monitor size={16} className="text-slate-400" />
    );

  async function withLoading(key: string, fn: () => Promise<void>) {
    setLoading(key);
    try {
      await fn();
    } finally {
      setLoading(null);
    }
  }

  return (
    <div
      className={`rounded-xl border bg-[#161b26] transition-all ${
        device.online ? "border-slate-700/60" : "border-slate-800/40 opacity-60"
      }`}
    >
      <div className="p-4">
        <div className="flex items-start justify-between mb-3">
          <div className="flex items-center gap-2">
            {platformIcon}
            <div>
              <h3 className="font-semibold text-slate-100 text-sm leading-tight">
                {device.hostname}
              </h3>
              {device.localIp && (
                <p className="text-xs text-slate-500 mt-0.5">{device.localIp}</p>
              )}
            </div>
          </div>
          <Badge online={device.online} />
        </div>

        <div className="space-y-2 mb-3">
          <div className="flex items-center justify-between text-xs text-slate-400 mb-0.5">
            <span className="flex items-center gap-1">
              <Cpu size={11} /> CPU
            </span>
            <span className="font-mono">{device.cpu.toFixed(1)}%</span>
          </div>
          <GaugeBar value={device.cpu} color={cpuColor} />

          <div className="flex items-center justify-between text-xs text-slate-400 mb-0.5">
            <span className="flex items-center gap-1">
              <MemoryStick size={11} /> RAM
            </span>
            <span className="font-mono">{device.ram.toFixed(1)}%</span>
          </div>
          <GaugeBar value={device.ram} color={ramColor} />
        </div>

        <div className="flex items-center gap-2 flex-wrap">
          {device.vpnActive ? (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-blue-500/15 text-blue-400 ring-1 ring-blue-500/30">
              <Shield size={10} /> VPN Aktif
            </span>
          ) : (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-slate-700/30 text-slate-500 ring-1 ring-slate-700/30">
              <ShieldOff size={10} /> VPN Yok
            </span>
          )}
          {proxyEnabled && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-purple-500/15 text-purple-400 ring-1 ring-purple-500/30">
              <Network size={10} /> Proxy
            </span>
          )}
          {device.proxyPort && (
            <span className="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs bg-indigo-500/15 text-indigo-400 ring-1 ring-indigo-500/30">
              :{device.proxyPort}
            </span>
          )}
        </div>

        {device.rustdeskId && (
          <div className="mt-3 p-2 rounded-lg bg-slate-800/60 flex items-center justify-between">
            <div>
              <p className="text-xs text-slate-500">RustDesk ID</p>
              <p className="font-mono text-xs text-slate-200">{device.rustdeskId}</p>
            </div>
            <button
              onClick={() => navigator.clipboard.writeText(device.rustdeskId!)}
              className="p-1 rounded hover:bg-slate-700 text-slate-400 hover:text-slate-200 transition-colors"
            >
              <Copy size={12} />
            </button>
          </div>
        )}

        {tunnelUrl && (
          <div className="mt-2 p-2 rounded-lg bg-slate-800/60">
            <p className="text-xs text-slate-500 mb-1">VS Code Tunnel</p>
            <a
              href={tunnelUrl}
              target="_blank"
              rel="noopener noreferrer"
              className="text-xs text-blue-400 hover:text-blue-300 underline break-all"
            >
              {tunnelUrl}
            </a>
          </div>
        )}
      </div>

      {device.online && (
        <div className="border-t border-slate-800/60 p-3 space-y-2">
          <div className="flex gap-2">
            <button
              onClick={() => withLoading("tunnel_start", () => onTunnel(device.id, "start"))}
              disabled={loading !== null}
              className="flex-1 px-2 py-1.5 rounded-lg text-xs bg-blue-600/20 text-blue-400 hover:bg-blue-600/30 border border-blue-600/30 transition-colors disabled:opacity-50"
            >
              {loading === "tunnel_start" ? "..." : "VS Code Tunnel"}
            </button>
            <button
              onClick={() => withLoading("tunnel_stop", () => onTunnel(device.id, "stop"))}
              disabled={loading !== null}
              className="px-2 py-1.5 rounded-lg text-xs bg-slate-700/40 text-slate-400 hover:bg-slate-700/60 border border-slate-700/40 transition-colors disabled:opacity-50"
            >
              Durdur
            </button>
          </div>

          {otherOnlineDevices.length > 0 && (
            <div className="flex gap-2">
              <select
                id={`proxy-target-${device.id}`}
                className="flex-1 px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                {otherOnlineDevices.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.hostname}
                  </option>
                ))}
              </select>
              <button
                onClick={() => {
                  const sel = document.getElementById(`proxy-target-${device.id}`) as HTMLSelectElement;
                  withLoading("proxy", () =>
                    onProxyToggle(
                      device.id,
                      sel.value,
                      proxyEnabled ? "disable" : "enable"
                    )
                  );
                }}
                disabled={loading !== null}
                className={`px-2 py-1.5 rounded-lg text-xs border transition-colors disabled:opacity-50 ${
                  proxyEnabled
                    ? "bg-purple-600/20 text-purple-400 border-purple-600/30 hover:bg-purple-600/30"
                    : "bg-slate-700/40 text-slate-400 border-slate-700/40 hover:bg-slate-700/60"
                }`}
              >
                {loading === "proxy" ? "..." : proxyEnabled ? "Proxy Kapat" : "Proxy Aç"}
              </button>
            </div>
          )}

          {otherOnlineDevices.length > 0 && (
            <div className="flex gap-2">
              <select
                id={`audio-target-${device.id}`}
                className="flex-1 px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                {otherOnlineDevices.map((d) => (
                  <option key={d.id} value={d.id}>
                    {d.hostname}
                  </option>
                ))}
              </select>
              <button
                onClick={() => {
                  const sel = document.getElementById(`audio-target-${device.id}`) as HTMLSelectElement;
                  withLoading("audio", () =>
                    onAudioToggle(device.id, sel.value, "start")
                  );
                }}
                disabled={loading !== null}
                className="px-2 py-1.5 rounded-lg text-xs bg-slate-700/40 text-slate-400 hover:bg-slate-700/60 border border-slate-700/40 transition-colors disabled:opacity-50 flex items-center gap-1"
              >
                <Mic size={10} />
                {loading === "audio" ? "..." : "Ses Köprüsü"}
              </button>
            </div>
          )}

          <button
            onClick={() => setExpanded((v) => !v)}
            className="w-full flex items-center justify-center gap-1 px-2 py-1.5 rounded-lg text-xs text-slate-500 hover:text-slate-300 hover:bg-slate-800/40 transition-colors"
          >
            <Terminal size={11} />
            Komut Satırı
            {expanded ? <ChevronUp size={11} /> : <ChevronDown size={11} />}
          </button>

          {expanded && (
            <div className="flex gap-2 pt-1">
              <input
                value={cmdInput}
                onChange={(e) => setCmdInput(e.target.value)}
                onKeyDown={(e) => {
                  if (e.key === "Enter" && cmdInput.trim()) {
                    withLoading("exec", () =>
                      onCommand(device.id, "EXEC", cmdInput.trim())
                    );
                    setCmdInput("");
                  }
                }}
                placeholder="Komut girin..."
                className="flex-1 px-2 py-1.5 rounded-lg text-xs bg-slate-900 text-slate-200 border border-slate-700/40 placeholder-slate-600 focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
              />
              <button
                onClick={() => {
                  if (cmdInput.trim()) {
                    withLoading("exec", () =>
                      onCommand(device.id, "EXEC", cmdInput.trim())
                    );
                    setCmdInput("");
                  }
                }}
                disabled={loading !== null || !cmdInput.trim()}
                className="px-3 py-1.5 rounded-lg text-xs bg-blue-600/80 text-white hover:bg-blue-600 transition-colors disabled:opacity-40"
              >
                Çalıştır
              </button>
            </div>
          )}
        </div>
      )}
    </div>
  );
}

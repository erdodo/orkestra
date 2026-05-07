"use client";

import { useState } from "react";
import { Play, RefreshCw } from "lucide-react";
import { DeviceData } from "./DeviceCard";

interface OrchestraPanelProps {
  devices: DeviceData[];
  onDevSession: (config: {
    local_device_id: string;
    remote_device_id: string;
    sync_source_path: string;
    sync_target_path: string;
    proxy_source_id?: string;
  }) => Promise<void>;
  onSyncCreate: (sourceId: string, targetId: string, sourcePath: string, targetPath: string) => Promise<void>;
}

export function OrchestraPanel({ devices, onDevSession, onSyncCreate }: OrchestraPanelProps) {
  const onlineDevices = devices.filter((d) => d.online);
  const [localId, setLocalId] = useState("");
  const [remoteId, setRemoteId] = useState("");
  const [proxyId, setProxyId] = useState("");
  const [sourcePath, setSourcePath] = useState("/home/user/project");
  const [targetPath, setTargetPath] = useState("/home/user/project");
  const [loading, setLoading] = useState(false);

  async function handleDevSession() {
    if (!localId || !remoteId) return;
    setLoading(true);
    try {
      await onDevSession({
        local_device_id: localId,
        remote_device_id: remoteId,
        sync_source_path: sourcePath,
        sync_target_path: targetPath,
        proxy_source_id: proxyId || undefined,
      });
    } finally {
      setLoading(false);
    }
  }

  async function handleSyncOnly() {
    if (!localId || !remoteId) return;
    setLoading(true);
    try {
      await onSyncCreate(localId, remoteId, sourcePath, targetPath);
    } finally {
      setLoading(false);
    }
  }

  const vpnDevices = onlineDevices.filter((d) => d.vpnActive);

  return (
    <div className="rounded-xl border border-slate-700/60 bg-[#161b26] p-4 space-y-4">
      <h2 className="text-sm font-semibold text-slate-300 flex items-center gap-2">
        <span className="w-2 h-2 rounded-full bg-blue-500" />
        Orkestra Merkezi
      </h2>

      {onlineDevices.length < 2 ? (
        <p className="text-xs text-slate-500 text-center py-4">
          En az 2 çevrimiçi cihaz gerekli
        </p>
      ) : (
        <div className="space-y-3">
          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="block text-xs text-slate-500 mb-1">Yerel Cihaz</label>
              <select
                value={localId}
                onChange={(e) => setLocalId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                <option value="">Seçin...</option>
                {onlineDevices.map((d) => (
                  <option key={d.id} value={d.id}>{d.hostname}</option>
                ))}
              </select>
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">Uzak Cihaz</label>
              <select
                value={remoteId}
                onChange={(e) => setRemoteId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                <option value="">Seçin...</option>
                {onlineDevices.filter((d) => d.id !== localId).map((d) => (
                  <option key={d.id} value={d.id}>{d.hostname}</option>
                ))}
              </select>
            </div>
          </div>

          <div className="grid grid-cols-2 gap-2">
            <div>
              <label className="block text-xs text-slate-500 mb-1">Kaynak Yol</label>
              <input
                value={sourcePath}
                onChange={(e) => setSourcePath(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
              />
            </div>
            <div>
              <label className="block text-xs text-slate-500 mb-1">Hedef Yol</label>
              <input
                value={targetPath}
                onChange={(e) => setTargetPath(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50 font-mono"
              />
            </div>
          </div>

          {vpnDevices.length > 0 && (
            <div>
              <label className="block text-xs text-slate-500 mb-1">VPN Proxy Cihazı (isteğe bağlı)</label>
              <select
                value={proxyId}
                onChange={(e) => setProxyId(e.target.value)}
                className="w-full px-2 py-1.5 rounded-lg text-xs bg-slate-800 text-slate-300 border border-slate-700/40 focus:outline-none focus:ring-1 focus:ring-blue-500/50"
              >
                <option value="">Yok</option>
                {vpnDevices.map((d) => (
                  <option key={d.id} value={d.id}>{d.hostname} (VPN)</option>
                ))}
              </select>
            </div>
          )}

          <div className="flex gap-2">
            <button
              onClick={handleDevSession}
              disabled={loading || !localId || !remoteId}
              className="flex-1 flex items-center justify-center gap-2 px-3 py-2 rounded-lg text-xs bg-blue-600 text-white hover:bg-blue-500 transition-colors disabled:opacity-40 font-medium"
            >
              <Play size={11} />
              {loading ? "Başlatılıyor..." : "Dev Oturumu Başlat"}
            </button>
            <button
              onClick={handleSyncOnly}
              disabled={loading || !localId || !remoteId}
              className="flex items-center justify-center gap-1 px-3 py-2 rounded-lg text-xs bg-slate-700/60 text-slate-300 hover:bg-slate-700 transition-colors disabled:opacity-40 border border-slate-700/40"
            >
              <RefreshCw size={11} />
              Sync
            </button>
          </div>
        </div>
      )}
    </div>
  );
}

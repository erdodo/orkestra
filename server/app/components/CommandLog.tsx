"use client";

import { useEffect, useRef } from "react";
import { Terminal } from "lucide-react";

export interface LogEntry {
  id: string;
  deviceId: string;
  hostname: string;
  cmd: string;
  stdout?: string;
  stderr?: string;
  exit_code?: number;
  ts: number;
}

interface CommandLogProps {
  entries: LogEntry[];
  onClear: () => void;
}

export function CommandLog({ entries, onClear }: CommandLogProps) {
  const bottomRef = useRef<HTMLDivElement>(null);

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [entries]);

  return (
    <div className="rounded-xl border border-slate-700/60 bg-[#161b26] overflow-hidden">
      <div className="flex items-center justify-between px-4 py-2.5 border-b border-slate-800/60">
        <div className="flex items-center gap-2 text-slate-400 text-sm">
          <Terminal size={14} />
          <span>Komut Çıktıları</span>
          {entries.length > 0 && (
            <span className="px-1.5 py-0.5 rounded-full text-xs bg-slate-700/60 text-slate-400">
              {entries.length}
            </span>
          )}
        </div>
        {entries.length > 0 && (
          <button
            onClick={onClear}
            className="text-xs text-slate-500 hover:text-slate-300 transition-colors"
          >
            Temizle
          </button>
        )}
      </div>
      <div className="h-64 overflow-y-auto p-3 space-y-2 font-mono text-xs">
        {entries.length === 0 ? (
          <p className="text-slate-600 text-center mt-8">Henüz komut çalıştırılmadı</p>
        ) : (
          entries.map((entry) => (
            <div key={entry.id} className="space-y-1">
              <div className="flex items-center gap-2 text-slate-500">
                <span className="text-blue-400">{entry.hostname}</span>
                <span>$</span>
                <span className="text-slate-300">{entry.cmd}</span>
                {entry.exit_code !== undefined && (
                  <span
                    className={`ml-auto px-1.5 py-0.5 rounded text-xs ${
                      entry.exit_code === 0
                        ? "bg-green-500/15 text-green-400"
                        : "bg-red-500/15 text-red-400"
                    }`}
                  >
                    {entry.exit_code === 0 ? "✓" : `✗ ${entry.exit_code}`}
                  </span>
                )}
              </div>
              {entry.stdout && (
                <pre className="pl-4 text-slate-300 whitespace-pre-wrap break-all">
                  {entry.stdout}
                </pre>
              )}
              {entry.stderr && (
                <pre className="pl-4 text-red-400 whitespace-pre-wrap break-all">
                  {entry.stderr}
                </pre>
              )}
            </div>
          ))
        )}
        <div ref={bottomRef} />
      </div>
    </div>
  );
}

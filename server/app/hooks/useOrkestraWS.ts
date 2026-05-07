"use client";

import { useEffect, useRef, useCallback } from "react";

type WSMessage = {
  type: string;
  [key: string]: unknown;
};

type MessageHandler = (msg: WSMessage) => void;

export function useOrkestraWS(onMessage: MessageHandler) {
  const wsRef = useRef<WebSocket | null>(null);
  const reconnectTimer = useRef<ReturnType<typeof setTimeout> | null>(null);
  const handlerRef = useRef(onMessage);
  const connectRef = useRef<(() => void) | null>(null);

  useEffect(() => {
    handlerRef.current = onMessage;
  });

  const connect = useCallback(() => {
    const protocol = window.location.protocol === "https:" ? "wss" : "ws";
    const url = `${protocol}://${window.location.host}/ui`;
    const ws = new WebSocket(url);
    wsRef.current = ws;

    ws.onopen = () => {
      console.log("[WS] Bağlantı kuruldu");
    };

    ws.onmessage = (event) => {
      try {
        const msg = JSON.parse(event.data) as WSMessage;
        handlerRef.current(msg);
      } catch {}
    };

    ws.onclose = () => {
      console.log("[WS] Bağlantı kesildi, yeniden bağlanılıyor...");
      reconnectTimer.current = setTimeout(() => {
        connectRef.current?.();
      }, 3000);
    };

    ws.onerror = () => {
      ws.close();
    };
  }, []);

  useEffect(() => {
    connectRef.current = connect;
  }, [connect]);

  useEffect(() => {
    connect();
    return () => {
      if (reconnectTimer.current) clearTimeout(reconnectTimer.current);
      wsRef.current?.close();
    };
  }, [connect]);

  return wsRef;
}

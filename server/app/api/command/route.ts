import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { device_id, cmd, payload } = body as {
    device_id: string;
    cmd: string;
    payload?: string;
  };

  console.log("[API /command] İstek:", { device_id, cmd, payload });

  if (!device_id || !cmd) {
    console.log("[API /command] HATA: Eksik param");
    return NextResponse.json({ error: "device_id ve cmd zorunlu" }, { status: 400 });
  }

  const { getAgents } = await import("@/lib/websocket-server");
  const agents = getAgents();
  console.log("[API /command] Bağlı agent'lar:", [...agents.entries()].map(([h, a]) => `${h}=${a.deviceId}`));

  const sent = sendToAgentById(device_id, { cmd, payload, device_id });
  console.log("[API /command] Gönderildi mi:", sent);

  if (!sent) {
    return NextResponse.json({ error: "Cihaz çevrimdışı veya bulunamadı", device_id, agents: [...agents.keys()] }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}

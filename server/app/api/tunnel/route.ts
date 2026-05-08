import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  console.log("[API /tunnel] İstek:", JSON.stringify(body));

  const { device_id, action } = body as {
    device_id: string;
    action: "start" | "stop";
  };

  if (!device_id) {
    console.log("[API /tunnel] HATA: device_id eksik");
    return NextResponse.json({ error: "device_id zorunlu" }, { status: 400 });
  }

  const { getAgents } = await import("@/lib/websocket-server");
  const agents = getAgents();
  console.log("[API /tunnel] Bağlı agent'lar:", [...agents.entries()].map(([h, a]) => `${h}=${a.deviceId}`));
  console.log("[API /tunnel] Aranan device_id:", device_id);

  const sent = sendToAgentById(device_id, {
    cmd: action === "start" ? "VSCODE_TUNNEL_START" : "VSCODE_TUNNEL_STOP",
  });

  console.log("[API /tunnel] Gönderildi mi:", sent);

  if (!sent) {
    console.log("[API /tunnel] HATA: Cihaz bulunamadı veya çevrimdışı, device_id:", device_id);
    return NextResponse.json({ error: "Cihaz çevrimdışı", device_id, agents: [...agents.keys()] }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}

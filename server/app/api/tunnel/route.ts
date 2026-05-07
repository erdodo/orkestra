import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { device_id, action } = body as {
    device_id: string;
    action: "start" | "stop";
  };

  if (!device_id) {
    return NextResponse.json({ error: "device_id zorunlu" }, { status: 400 });
  }

  const sent = sendToAgentById(device_id, {
    cmd: action === "start" ? "VSCODE_TUNNEL_START" : "VSCODE_TUNNEL_STOP",
  });

  if (!sent) {
    return NextResponse.json({ error: "Cihaz çevrimdışı" }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}

import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { device_id, cmd, payload } = body as {
    device_id: string;
    cmd: string;
    payload?: string;
  };

  if (!device_id || !cmd) {
    return NextResponse.json({ error: "device_id ve cmd zorunlu" }, { status: 400 });
  }

  const sent = sendToAgentById(device_id, { cmd, payload, device_id });
  if (!sent) {
    return NextResponse.json({ error: "Cihaz çevrimdışı veya bulunamadı" }, { status: 404 });
  }

  return NextResponse.json({ ok: true });
}

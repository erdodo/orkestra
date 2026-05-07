import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { source_device_id, target_device_id, action } = body as {
    source_device_id: string;
    target_device_id: string;
    action: "start" | "stop";
  };

  if (!source_device_id || !target_device_id) {
    return NextResponse.json({ error: "Eksik parametreler" }, { status: 400 });
  }

  if (action === "start") {
    sendToAgentById(source_device_id, {
      cmd: "AUDIO_START",
      role: "sender",
      peer_device_id: target_device_id,
    });
    sendToAgentById(target_device_id, {
      cmd: "AUDIO_START",
      role: "receiver",
      peer_device_id: source_device_id,
    });
  } else {
    sendToAgentById(source_device_id, { cmd: "AUDIO_STOP" });
    sendToAgentById(target_device_id, { cmd: "AUDIO_STOP" });
  }

  return NextResponse.json({ ok: true });
}

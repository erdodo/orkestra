import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { sendToAgentById } from "@/lib/websocket-server";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { source_device_id, target_device_id, action } = body as {
    source_device_id: string;
    target_device_id: string;
    action: "enable" | "disable";
  };

  const sourceDevice = await db.device.findUnique({ where: { id: source_device_id } });
  const targetDevice = await db.device.findUnique({
    where: { id: target_device_id },
    include: { proxyConfig: true },
  });

  if (!sourceDevice || !targetDevice) {
    return NextResponse.json({ error: "Cihaz bulunamadı" }, { status: 404 });
  }

  if (action === "enable") {
    sendToAgentById(source_device_id, { cmd: "PROXY_START" });
    sendToAgentById(target_device_id, {
      cmd: "SET_PROXY",
      proxy_host: sourceDevice.localIp ?? "raspberrypi.local",
      proxy_port: sourceDevice.proxyPort ?? 1080,
      proxy_type: "socks5",
    });

    await db.proxyConfig.upsert({
      where: { deviceId: target_device_id },
      update: { enabled: true, proxyHost: sourceDevice.localIp, proxyPort: sourceDevice.proxyPort ?? 1080 },
      create: {
        deviceId: target_device_id,
        enabled: true,
        proxyHost: sourceDevice.localIp,
        proxyPort: sourceDevice.proxyPort ?? 1080,
      },
    });
  } else {
    sendToAgentById(target_device_id, { cmd: "CLEAR_PROXY" });
    await db.proxyConfig.updateMany({
      where: { deviceId: target_device_id },
      data: { enabled: false },
    });
  }

  return NextResponse.json({ ok: true });
}

import { NextRequest, NextResponse } from "next/server";
import { sendToAgentById } from "@/lib/websocket-server";
import { db } from "@/lib/db";

export async function POST(req: NextRequest) {
  const body = await req.json();
  const {
    local_device_id,
    remote_device_id,
    sync_source_path,
    sync_target_path,
    proxy_source_id,
  } = body as {
    local_device_id: string;
    remote_device_id: string;
    sync_source_path: string;
    sync_target_path: string;
    proxy_source_id?: string;
  };

  const remoteDevice = await db.device.findUnique({ where: { id: remote_device_id } });
  const localDevice = await db.device.findUnique({ where: { id: local_device_id } });

  if (!remoteDevice || !localDevice) {
    return NextResponse.json({ error: "Cihaz bulunamadı" }, { status: 404 });
  }

  const job = await db.syncJob.create({
    data: {
      sourceId: local_device_id,
      targetId: remote_device_id,
      sourcePath: sync_source_path,
      targetPath: sync_target_path,
      status: "starting",
    },
  });

  sendToAgentById(local_device_id, {
    cmd: "SYNC_INIT",
    job_id: job.id,
    source_path: sync_source_path,
    target_path: sync_target_path,
    peer_hostname: remoteDevice.hostname,
    peer_ip: remoteDevice.localIp,
  });

  if (proxy_source_id) {
    const proxySource = await db.device.findUnique({ where: { id: proxy_source_id } });
    if (proxySource) {
      sendToAgentById(proxy_source_id, { cmd: "PROXY_START" });
      sendToAgentById(local_device_id, {
        cmd: "SET_PROXY",
        proxy_host: proxySource.localIp ?? "raspberrypi.local",
        proxy_port: proxySource.proxyPort ?? 1080,
        proxy_type: "socks5",
      });
    }
  }

  sendToAgentById(remote_device_id, { cmd: "VSCODE_TUNNEL_START" });

  return NextResponse.json({ ok: true, sync_job_id: job.id });
}

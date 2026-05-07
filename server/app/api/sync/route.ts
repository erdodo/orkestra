import { NextRequest, NextResponse } from "next/server";
import { db } from "@/lib/db";
import { sendToAgentById } from "@/lib/websocket-server";

export async function GET() {
  const jobs = await db.syncJob.findMany({
    orderBy: { updatedAt: "desc" },
    include: { source: true, target: true },
  });
  return NextResponse.json(jobs);
}

export async function POST(req: NextRequest) {
  const body = await req.json();
  const { source_id, target_id, source_path, target_path } = body as {
    source_id: string;
    target_id: string;
    source_path: string;
    target_path: string;
  };

  if (!source_id || !target_id || !source_path || !target_path) {
    return NextResponse.json({ error: "Eksik parametreler" }, { status: 400 });
  }

  const job = await db.syncJob.create({
    data: { sourceId: source_id, targetId: target_id, sourcePath: source_path, targetPath: target_path, status: "starting" },
    include: { source: true, target: true },
  });

  const syncPayload = {
    cmd: "SYNC_INIT",
    job_id: job.id,
    source_path,
    target_path,
    peer_hostname: job.target.hostname,
    peer_ip: job.target.localIp,
  };

  sendToAgentById(source_id, syncPayload);
  sendToAgentById(target_id, {
    cmd: "SYNC_ACCEPT",
    job_id: job.id,
    source_path: target_path,
    target_path: source_path,
    peer_hostname: job.source.hostname,
    peer_ip: job.source.localIp,
  });

  return NextResponse.json(job, { status: 201 });
}

export async function DELETE(req: NextRequest) {
  const { job_id } = await req.json() as { job_id: string };
  const job = await db.syncJob.update({
    where: { id: job_id },
    data: { status: "stopped" },
    include: { source: true, target: true },
  });

  sendToAgentById(job.sourceId, { cmd: "SYNC_STOP", job_id });
  sendToAgentById(job.targetId, { cmd: "SYNC_STOP", job_id });

  return NextResponse.json({ ok: true });
}

import { NextResponse } from "next/server";
import { db } from "@/lib/db";

export async function GET() {
  const devices = await db.device.findMany({
    orderBy: { updatedAt: "desc" },
    include: { proxyConfig: true },
  });
  return NextResponse.json(devices);
}

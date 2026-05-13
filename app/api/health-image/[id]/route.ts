import { NextRequest, NextResponse } from "next/server"
import { DEFAULT_FARM_API_HOST } from "@/lib/api/default-api-hosts"

export const runtime = "nodejs"

function farmBaseUrl(): string {
  const raw = (process.env.FARM_API_URL || process.env.NEXT_PUBLIC_API_BASE_URL || DEFAULT_FARM_API_HOST)
    .trim()
    .replace(/\/+$/, "")
  if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
  if (raw.includes("localhost")) return `http://${raw}`
  return `https://${raw}`
}

/** Proxies GET /api/Health/{id}/attachment with Authorization so the browser can load images without putting tokens in the URL. */
export async function GET(request: NextRequest, context: { params: Promise<{ id: string }> }) {
  const { id: idParam } = await context.params
  const id = parseInt(idParam, 10)
  if (!Number.isFinite(id) || id <= 0) {
    return new NextResponse("Bad request", { status: 400 })
  }

  const userId = request.nextUrl.searchParams.get("userId")
  const farmId = request.nextUrl.searchParams.get("farmId")
  if (!userId?.trim() || !farmId?.trim()) {
    return new NextResponse("Bad request", { status: 400 })
  }

  const auth = request.headers.get("authorization")
  if (!auth?.toLowerCase().startsWith("bearer ")) {
    return new NextResponse("Unauthorized", { status: 401 })
  }

  const q = new URLSearchParams({
    userId: userId.trim(),
    farmId: farmId.trim(),
  })
  const upstream = `${farmBaseUrl()}/api/Health/${id}/attachment?${q.toString()}`

  const upstreamRes = await fetch(upstream, {
    method: "GET",
    headers: { Authorization: auth },
    cache: "no-store",
  })

  const buf = await upstreamRes.arrayBuffer()
  if (!upstreamRes.ok) {
    return new NextResponse(buf, { status: upstreamRes.status })
  }

  const contentType = upstreamRes.headers.get("content-type") || "application/octet-stream"
  return new NextResponse(buf, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "private, max-age=120",
    },
  })
}

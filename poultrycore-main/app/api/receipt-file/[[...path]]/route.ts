import { NextRequest, NextResponse } from "next/server"
import path from "path"
import { readFile } from "fs/promises"
import { getReceiptUploadsStorageDir } from "@/lib/server/receipt-uploads-dir"

export const runtime = "nodejs"

/**
 * Serves files from the receipt uploads directory only (path traversal safe).
 * URL path always uses `receipt-uploads/...` for compatibility with stored `/receipt-uploads/...` paths;
 * on disk, files live under `getReceiptUploadsStorageDir()` (see `RECEIPT_UPLOADS_ROOT`).
 */
export async function GET(
  _request: NextRequest,
  context: { params: Promise<{ path?: string[] }> }
) {
  const params = await context.params
  const segments = params.path
  if (!segments?.length) {
    return new NextResponse("Not found", { status: 404 })
  }
  if (segments[0] !== "receipt-uploads") {
    return new NextResponse("Not found", { status: 404 })
  }

  const allowedRoot = path.normalize(getReceiptUploadsStorageDir())
  const resolved = path.normalize(path.join(allowedRoot, ...segments.slice(1)))
  const rel = path.relative(allowedRoot, resolved)
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    return new NextResponse("Forbidden", { status: 403 })
  }

  const buf = await readFile(resolved).catch(() => null)
  if (!buf?.length) {
    return new NextResponse("Not found", { status: 404 })
  }

  const ext = path.extname(resolved).toLowerCase()
  const contentType =
    ext === ".png" ? "image/png" : ext === ".webp" ? "image/webp" : "image/jpeg"

  return new NextResponse(buf, {
    status: 200,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "private, max-age=300",
    },
  })
}

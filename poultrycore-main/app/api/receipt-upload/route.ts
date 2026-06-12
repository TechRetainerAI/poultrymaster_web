import { NextResponse } from "next/server"
import { mkdir, writeFile } from "fs/promises"
import path from "path"
import { randomUUID } from "crypto"
import { getReceiptUploadsStorageDir } from "@/lib/server/receipt-uploads-dir"

export const runtime = "nodejs"

const MAX_BYTES = 4 * 1024 * 1024
const ALLOWED_TYPES = new Set(["image/jpeg", "image/png", "image/webp"])

function safeFarmIdSegment(raw: unknown): string | null {
  if (typeof raw !== "string") return null
  const s = raw.trim()
  if (!s || s.length > 80) return null
  if (!/^[a-zA-Z0-9_-]+$/.test(s)) return null
  return s
}

/**
 * Saves receipt images under `{RECEIPT_UPLOADS_ROOT or public/receipt-uploads}/{farmId}/`.
 * For Cloud Run / multiple instances, set `RECEIPT_UPLOADS_ROOT` to a mounted volume path
 * so all instances read the same files; otherwise uploads are local disk only.
 */
export async function POST(request: Request) {
  const auth = request.headers.get("authorization")
  if (!auth?.toLowerCase().startsWith("bearer ")) {
    return NextResponse.json({ message: "Sign in required to upload receipts." }, { status: 401 })
  }

  let formData: FormData
  try {
    formData = await request.formData()
  } catch {
    return NextResponse.json({ message: "Invalid form data." }, { status: 400 })
  }

  const farmId = safeFarmIdSegment(formData.get("farmId"))
  if (!farmId) {
    return NextResponse.json({ message: "Invalid or missing farmId." }, { status: 400 })
  }

  const file = formData.get("file")
  if (!file || !(file instanceof Blob)) {
    return NextResponse.json({ message: "Missing file." }, { status: 400 })
  }

  if (file.size > MAX_BYTES) {
    return NextResponse.json({ message: "File too large (max 4 MB)." }, { status: 400 })
  }

  const mime = (file as File).type || "application/octet-stream"
  if (!ALLOWED_TYPES.has(mime)) {
    return NextResponse.json({ message: "Only JPEG, PNG, or WebP images are allowed." }, { status: 400 })
  }

  const ext = mime === "image/png" ? "png" : mime === "image/webp" ? "webp" : "jpg"
  const filename = `${randomUUID()}.${ext}`
  const dir = path.join(getReceiptUploadsStorageDir(), farmId)
  await mkdir(dir, { recursive: true })
  const buf = Buffer.from(await file.arrayBuffer())
  await writeFile(path.join(dir, filename), buf)

  const publicPath = `/receipt-uploads/${farmId}/${filename}`
  return NextResponse.json({ path: publicPath })
}

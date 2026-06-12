/** Embedded receipt path suffix on expense description (stored in DB description field). */
const RECEIPT_SUFFIX = /\s*::rcpt:(\/receipt-uploads\/[^\s]+)::\s*$/i

export function extractReceiptPathFromDescription(description: string | null | undefined): string | null {
  if (!description) return null
  const m = description.match(RECEIPT_SUFFIX)
  return m?.[1]?.trim() || null
}

/** User-facing description without the machine receipt suffix. */
export function stripReceiptSuffixFromDescription(description: string | null | undefined): string {
  if (!description) return ""
  return description.replace(RECEIPT_SUFFIX, "").trimEnd()
}

export function appendReceiptSuffix(description: string, publicPath: string): string {
  const base = stripReceiptSuffixFromDescription(description).trimEnd()
  const path = publicPath.trim()
  if (!path.startsWith("/")) {
    throw new Error("Receipt path must be absolute from site root")
  }
  return `${base}\n::rcpt:${path}::`
}

/** UUID image filename (receipt upload naming). */
const UUID_IMAGE_FILE =
  /^\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\.(png|jpe?g|webp)$/i

/** `/farmGuid/filename.ext` saved without the `receipt-uploads` segment (legacy / mistaken saves). */
const FARM_FOLDER_FILE =
  /^\/([0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})\/([^/\s]+)$/i

/**
 * Stored path is usually `/receipt-uploads/{farmId}/{file}` — use `/api/receipt-file/...` so files work
 * when they are not in the static export / CDN (and on Cloud Run disk).
 *
 * @param farmId When the stored path is only `/uuid.png` at site root, pass farmId so we can resolve
 *               to `/api/receipt-file/receipt-uploads/{farmId}/uuid.png`.
 */
export function toReceiptViewUrl(
  storedPath: string | null | undefined,
  farmId?: string | null
): string | null {
  if (!storedPath?.trim()) return null
  const raw = storedPath.trim()
  if (raw.startsWith("http://") || raw.startsWith("https://")) return raw
  const p = raw.startsWith("/") ? raw : `/${raw}`

  if (p.startsWith("/receipt-uploads/")) {
    const withoutLead = p.replace(/^\/+/, "")
    return `/api/receipt-file/${withoutLead}`
  }

  const farmSeg = farmId?.trim()
  if (farmSeg) {
    const um = p.match(UUID_IMAGE_FILE)
    if (um) {
      const ext = um[2].toLowerCase() === "jpeg" ? "jpg" : um[2].toLowerCase()
      return `/api/receipt-file/receipt-uploads/${farmSeg}/${um[1]}.${ext}`
    }
  }

  const ff = p.match(FARM_FOLDER_FILE)
  if (ff && !p.toLowerCase().startsWith("/receipt-uploads/")) {
    return `/api/receipt-file/receipt-uploads/${ff[1]}/${ff[2]}`
  }

  return p.startsWith("/") ? p : `/${p}`
}

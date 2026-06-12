import path from "path"

/**
 * Directory where receipt / medication images are stored (`{farmId}/{uuid}.ext`).
 * Set `RECEIPT_UPLOADS_ROOT` to an absolute path (e.g. a Cloud Run volume mount) so
 * uploads survive redeploys and are shared across instances.
 */
export function getReceiptUploadsStorageDir(): string {
  const raw = process.env.RECEIPT_UPLOADS_ROOT?.trim()
  if (raw) return path.resolve(raw)
  return path.join(process.cwd(), "public", "receipt-uploads")
}

/**
 * Turn a picked image File into a small `data:` URI suitable for storing inline.
 *
 * Menu item photos are stored in the row itself (`restaurantmenuitem.imageurl`,
 * a Postgres TEXT column), which means every `listMenuItems()` call reads them
 * back. A raw phone photo run through `FileReader.readAsDataURL` is several MB
 * of base64 -- fine for one item, ruinous for a POS screen listing a hundred.
 * So we re-encode to a thumbnail first.
 *
 * 512px on the long edge is generous: the menu list renders these at 56px and
 * the edit dialog at 64px, so this still looks sharp on a 2x display.
 */

/** Longest edge of the stored thumbnail, in pixels. */
const MAX_EDGE = 512
/** JPEG quality. 0.72 is the knee of the size/quality curve for food photos. */
const QUALITY = 0.72
/** Refuse absurd inputs before we try to decode them. */
const MAX_INPUT_BYTES = 15 * 1024 * 1024
/** Must stay under RestaurantImageLimits.DataUrl (400_000) on the API side. */
const MAX_OUTPUT_CHARS = 400_000

function readAsDataUrl(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => resolve(String(reader.result))
    reader.onerror = () => reject(new Error("That file could not be read."))
    reader.readAsDataURL(file)
  })
}

function decode(dataUrl: string): Promise<HTMLImageElement> {
  return new Promise((resolve, reject) => {
    const img = new Image()
    img.onload = () => resolve(img)
    img.onerror = () => reject(new Error("That file is not an image the browser can read."))
    img.src = dataUrl
  })
}

/**
 * @throws Error with a message safe to show the user in a toast.
 */
export async function fileToThumbnailDataUrl(
  file: File,
  { maxEdge = MAX_EDGE, quality = QUALITY }: { maxEdge?: number; quality?: number } = {}
): Promise<string> {
  if (!file.type.startsWith("image/")) {
    throw new Error("Pick an image file (JPG, PNG or WebP).")
  }
  if (file.size > MAX_INPUT_BYTES) {
    throw new Error("That image is over 15 MB. Pick a smaller one.")
  }

  const original = await readAsDataUrl(file)

  // SVG is vector and GIF may be animated; a canvas round-trip would rasterise or
  // freeze them. They're small enough to keep as-is.
  if (file.type === "image/svg+xml" || file.type === "image/gif") {
    if (original.length > MAX_OUTPUT_CHARS) {
      throw new Error("That image is too large to store. Use a JPG or PNG instead.")
    }
    return original
  }

  const img = await decode(original)
  const scale = Math.min(1, maxEdge / Math.max(img.width, img.height))
  const width = Math.max(1, Math.round(img.width * scale))
  const height = Math.max(1, Math.round(img.height * scale))

  const canvas = document.createElement("canvas")
  canvas.width = width
  canvas.height = height
  const ctx = canvas.getContext("2d")
  if (!ctx) return original // no canvas: fall back rather than lose the user's pick

  // JPEG has no alpha channel, so transparent pixels would otherwise composite
  // to black. Paint white underneath first.
  ctx.fillStyle = "#ffffff"
  ctx.fillRect(0, 0, width, height)
  ctx.drawImage(img, 0, 0, width, height)

  const thumbnail = canvas.toDataURL("image/jpeg", quality)

  // Re-encoding a tiny, already-optimised image can come out bigger. Keep whichever
  // is smaller, as long as it fits.
  const best = thumbnail.length <= original.length ? thumbnail : original
  if (best.length > MAX_OUTPUT_CHARS) {
    throw new Error("That image is too detailed to store. Try a smaller or simpler one.")
  }
  return best
}

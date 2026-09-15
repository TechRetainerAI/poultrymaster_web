/**
 * The URL a table's QR code encodes.
 *
 * Scanning must land the guest on the public ordering page with the token in
 * hand — `/restaurant-order-online` reads `?qr=` and resolves it server-side to
 * the restaurant and the table, so nothing about the guest's identity or which
 * table they are at is taken from anything they can edit.
 *
 * Why the origin is a stored setting rather than a compiled-in constant:
 * `NEXT_PUBLIC_*` values are inlined at Docker build time (cloudbuild.web.yaml),
 * so baking the public hostname in would mean rebuilding the image every time it
 * changes. It is also entirely normal for staff to be on a different hostname
 * from the one guests should use. `window.location.origin` is the sensible
 * default; `publicbaseurl` on the restaurant's online-ordering settings overrides
 * it when the two differ.
 */

export const QR_ORDER_PATH = "/restaurant-order-online"

/** Trailing slashes and stray whitespace are the usual paste damage. */
function normaliseBase(base: string): string {
  const trimmed = base.trim().replace(/\/+$/, "")
  if (!trimmed) return ""
  return /^https?:\/\//i.test(trimmed) ? trimmed : `https://${trimmed}`
}

/**
 * @param token   the `qrToken` from `restaurantqrcodes`, generated server-side
 * @param overrideBase  the farm's `publicBaseUrl` setting, when it has one
 * @returns an absolute URL, or "" during SSR when there is no origin to use
 */
export function buildQrOrderUrl(token: string, overrideBase?: string | null): string {
  const base = normaliseBase(overrideBase || "") ||
    (typeof window !== "undefined" ? window.location.origin : "")

  // No origin means we are rendering on the server. Returning "" lets the caller
  // hold off rather than print a QR code pointing at a relative path, which would
  // scan as garbage and be very hard to notice on a printed card.
  if (!base) return ""

  return `${base}${QR_ORDER_PATH}?qr=${encodeURIComponent(token)}`
}

/**
 * One place that turns a failed HTTP response into a sentence a person can read.
 *
 * There were six near-copies of this across lib/api, three of which did not
 * exist at all — poultry-inventory, poultry-distribution and
 * poultry-feed-production interpolated the response body straight into the
 * error message. Creating a poultry product with a name already in use put this
 * in a toast:
 *
 *   POST /Poultry/products failed (500): {"success":false,"errorType":
 *   "SqlException","sqlState":"23505","message":"duplicate key value violates
 *   unique constraint \"uq_poultryproducts_farm_name\"", ...}
 *
 * The rule that fixes it, and the one thing worth preserving if this is ever
 * rewritten: WHEN THE BODY IS JSON, NEVER RETURN THE BODY. Either a known field
 * holds a real message, or we say the request failed and leave the JSON to the
 * console. A raw payload in front of a farm manager is not an error message.
 */

/** Keys the backend actually uses, in the order we prefer them. */
const MESSAGE_KEYS = [
  "message", "Message",
  "detail", "Detail",
  "title", "Title",
  "error", "Error",
] as const

function fromErrorsBag(errors: unknown): string {
  if (!errors || typeof errors !== "object") return ""
  if (Array.isArray(errors)) return errors.map(String).join(", ")
  return Object.values(errors as Record<string, unknown>)
    .flat()
    .map(String)
    .filter(Boolean)
    .join(", ")
}

/**
 * The path out of a Response, for helpers that are handed the response rather
 * than the request. A Response knows its URL but not the verb it was fetched
 * with, so callers pass "" as the method and the generic message drops it.
 */
export function pathOf(res: Response): string {
  try {
    return new URL(res.url).pathname
  } catch {
    return res.url || ""
  }
}

export function explainHttpError(
  method: string,
  path: string,
  status: number,
  body: string,
): string {
  const where = [method, path].filter(Boolean).join(" ").trim()
  const generic = where ? `${where} failed (${status}).` : `Request failed (${status}).`
  const text = (body || "").trim()
  if (!text) return generic

  // An ASP.NET HTML error page is noise, never a message.
  if (text.startsWith("<")) return generic

  let parsed: any
  try {
    parsed = JSON.parse(text)
  } catch {
    // Genuinely plain text — that IS the message, just keep it to a sane length.
    return text.length > 400 ? `${text.slice(0, 400)}…` : text
  }

  if (parsed && typeof parsed === "object") {
    for (const key of MESSAGE_KEYS) {
      const v = parsed[key]
      if (typeof v === "string" && v.trim()) return v.trim()
    }

    const bag = fromErrorsBag(parsed.errors ?? parsed.Errors)
    if (bag) return bag

    // A duplicate that reached us without the backend's friendly wording —
    // an older API build, or a constraint it has no table mapping for.
    if (parsed.sqlState === "23505") return "That record already exists."
  }

  // Parsed as JSON but nothing usable in it. Say so plainly rather than
  // showing the payload.
  return generic
}

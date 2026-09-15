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

/**
 * The same job as explainHttpError, one step further along: what to PUT ON THE
 * PAGE when a read fails and there is nothing else to show.
 *
 * explainHttpError keeps a raw payload out of a toast, but it cannot help when
 * the backend hands us a technically accurate sentence that means nothing to
 * the reader -- "function sppoultrydeferredpurchase_summary(...) does not
 * exist" is the example that prompted this. That is a real answer to a
 * question a farm manager never asked.
 *
 * Returns a headline they can act on plus the hint of what to do. The caller
 * keeps the raw text and shows it demoted: whoever can fix this needs it, and
 * whoever cannot should not have to read it.
 *
 * @param subject what failed to load, lower case, e.g. "deferred inventory costs"
 */
export function explainLoadFailure(
  raw: string,
  subject = "this page",
): { headline: string; hint: string } {
  const t = (raw || "").toLowerCase()

  // 42883 is Postgres undefined_function: a migration this screen depends on
  // has not been applied. Nothing is wrong with the company's data, and saying
  // so is the difference between a shrug and a support call about lost records.
  if (t.includes("does not exist") || t.includes("undefined function") || t.includes("42883")) {
    return {
      headline: `${subject[0].toUpperCase()}${subject.slice(1)} aren't switched on yet.`,
      hint: "This company's database is missing an update this screen needs. Ask whoever looks after your system to apply it — nothing is wrong with your data.",
    }
  }
  if (t.includes("(401)") || t.includes("(403)") || t.includes("unauthor") || t.includes("forbid")) {
    return {
      headline: "You do not have permission to view this.",
      hint: "Ask an administrator to give you access for this company.",
    }
  }
  if (t.includes("failed to fetch") || t.includes("networkerror") || t.includes("timeout")) {
    return {
      headline: "Could not reach the server.",
      hint: "Check your connection and try again. Nothing has been changed.",
    }
  }
  return {
    headline: `Could not load ${subject}.`,
    hint: "Try again in a moment. If it keeps happening, pass the detail below to whoever looks after your system.",
  }
}

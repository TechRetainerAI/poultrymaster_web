/**
 * Fuzzy text matching for the header search.
 *
 * React-free and dependency-free so it can be unit tested on its own. The
 * scorer is deliberately simple and explainable -- a few tiers, best tier wins
 * -- rather than a weighted blend nobody can reason about when a result ranks
 * oddly:
 *
 *   100  exact            "sales"            -> Sales
 *    90  prefix           "sal"              -> Sales
 *    80  word prefixes    "cust bal"         -> Customer Balances
 *    70  substring        "flow"             -> Cash Flow
 *    65  acronym          "pl", "cf"         -> Profit & Loss, Cash Flow
 *    55  typo-tolerant    "expences", "suplier"
 *    <40 subsequence      "prdrec"           -> Production Records
 *
 * 0 means "does not match" and the caller drops the row.
 */

/** Lowercase, drop apostrophes ("doesn't" -> "doesnt"), `&` -> `and`, punctuation to spaces. */
export function normalize(s: string): string {
  return s
    .toLowerCase()
    .normalize("NFKD")
    .replace(/\p{M}/gu, "")            // accents, once NFKD has split them off
    .replace(/['\p{Pf}]/gu, "")        // apostrophes, straight and curly
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .trim()
}

export function tokenize(s: string): string[] {
  const n = normalize(s)
  return n ? n.split(" ") : []
}

/** Words that carry no meaning in a search and only dilute it. */
export const STOP_WORDS = new Set(["the", "a", "an", "of", "to", "for", "my", "and", "in", "on", "page", "show", "me"])

/**
 * Damerau-Levenshtein distance (adjacent transpositions count as one edit),
 * bailing out once it is clearly beyond `max`. Typing is where transpositions
 * come from ("slaes"), so they must cost one edit, not two.
 */
export function editDistance(a: string, b: string, max = 2): number {
  if (a === b) return 0
  if (Math.abs(a.length - b.length) > max) return max + 1
  const rows: number[][] = []
  for (let i = 0; i <= a.length; i++) {
    rows[i] = [i]
  }
  for (let j = 0; j <= b.length; j++) rows[0][j] = j
  for (let i = 1; i <= a.length; i++) {
    let rowMin = Infinity
    for (let j = 1; j <= b.length; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      let v = Math.min(rows[i - 1][j] + 1, rows[i][j - 1] + 1, rows[i - 1][j - 1] + cost)
      if (i > 1 && j > 1 && a[i - 1] === b[j - 2] && a[i - 2] === b[j - 1]) {
        v = Math.min(v, rows[i - 2][j - 2] + 1)
      }
      rows[i][j] = v
      if (v < rowMin) rowMin = v
    }
    if (rowMin > max) return max + 1
  }
  return rows[a.length][b.length]
}

/** How many typos a query word of this length is allowed. */
function typoBudget(len: number): number {
  if (len >= 8) return 2
  if (len >= 4) return 1
  return 0
}

/**
 * Does query word `q` loosely match text word `w`? A prefix counts (so "expen"
 * finds "expenses"), and so does a near-miss of either the whole word or the
 * same-length prefix of it (so "expences" and "suplier" still land).
 */
export function wordMatches(q: string, w: string): "prefix" | "typo" | null {
  if (w.startsWith(q)) return "prefix"
  const budget = typoBudget(q.length)
  if (budget === 0) return null
  if (editDistance(q, w, budget) <= budget) return "typo"
  // Compare against the word's prefix of the same length, one longer (a letter
  // dropped: "suplier") and one shorter (a letter doubled: "expennse").
  for (const len of [q.length, q.length + 1, q.length - 1]) {
    if (len > 0 && w.length > len && editDistance(q, w.slice(0, len), budget) <= budget) return "typo"
  }
  return null
}

/** Score a single query against a single piece of text. 0 = no match. */
export function scoreText(query: string, text: string): number {
  const q = normalize(query)
  const t = normalize(text)
  if (!q || !t) return 0
  if (q === t) return 100
  if (t.startsWith(q)) return 90

  const qWords = q.split(" ").filter((w) => !STOP_WORDS.has(w) || q.split(" ").length === 1)
  const tWords = t.split(" ")
  if (qWords.length === 0) return 0

  // Every query word starts some text word.
  if (qWords.every((qw) => tWords.some((tw) => tw.startsWith(qw)))) return 80
  if (t.includes(q)) return 70

  // Acronym: "pl" -> profit (and) loss. Stop words are skipped so "&" -> "and"
  // does not turn Profit & Loss into "pal".
  if (q.length >= 2 && !q.includes(" ")) {
    const initials = tWords.filter((w) => !STOP_WORDS.has(w)).map((w) => w[0]).join("")
    if (initials.startsWith(q)) return 65
  }

  // Typo tolerance, word by word. Every query word has to land somewhere.
  let typoHits = 0
  const allLand = qWords.every((qw) =>
    tWords.some((tw) => {
      const m = wordMatches(qw, tw)
      if (m === "typo") typoHits++
      return m !== null
    }),
  )
  if (allLand) return typoHits > 0 ? 55 : 80

  // Subsequence: the characters appear in order. Scored by how tightly they
  // pack -- "prdrec" in "production records" is a real hit, a query whose
  // letters are scattered across a long title is noise.
  const compactQ = q.replace(/ /g, "")
  if (compactQ.length >= 3) {
    let ti = 0
    let first = -1
    let last = -1
    for (const ch of compactQ) {
      const found = t.indexOf(ch, ti)
      if (found === -1) return 0
      if (first === -1) first = found
      last = found
      ti = found + 1
    }
    const span = last - first + 1
    const density = compactQ.length / span
    if (density < 0.35) return 0
    return Math.round(20 + density * 20)
  }

  return 0
}

/**
 * Best score across several fields, each with its own weight. A title hit
 * should beat a keyword hit of the same tier, and a keyword hit should beat a
 * hit on the group the row lives in.
 */
export function scoreFields(query: string, fields: { text: string; weight: number }[]): number {
  let best = 0
  for (const f of fields) {
    if (!f.text) continue
    const s = scoreText(query, f.text) * f.weight
    if (s > best) best = s
  }
  return best
}

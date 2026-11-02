/**
 * Searching the Help Center.
 *
 * Help questions are sentences ("why doesn't my cash match my profit"), not
 * page names, so this does not use the header search's all-words-must-match
 * scorer. It counts how many of the MEANINGFUL words land somewhere in an
 * entry -- the title counting most, then its keywords, then the body -- and
 * keeps an entry when at least half of them do. Typos are tolerated word by
 * word through the same matcher the header search uses.
 *
 * React-free so it can be tested on its own.
 */

import { normalize, scoreText, STOP_WORDS, tokenize, wordMatches } from "@/lib/search/fuzzy"
import type { HelpEntry } from "./help-types"

/** Words that make a question a question and say nothing about its subject. */
const QUESTION_WORDS = new Set([
  "how", "do", "does", "did", "i", "we", "can", "cant", "cannot", "what", "whats", "why", "where", "when",
  "which", "who", "is", "are", "was", "it", "its", "this", "that", "be", "should", "would", "will", "with",
  "doesnt", "dont", "isnt", "arent", "not", "no", "there", "get", "got", "use", "using", "help", "please",
  "you", "your", "our", "app", "system",
])

/** The words worth matching, in the order typed. */
export function meaningfulWords(query: string): string[] {
  const words = tokenize(query).filter((w) => !STOP_WORDS.has(w) && !QUESTION_WORDS.has(w))
  // A query made only of question words ("how do i") is still a query: fall
  // back to all of it rather than to nothing.
  return words.length ? words : tokenize(query)
}

interface Prepared {
  entry: HelpEntry
  title: string[]
  keywords: string[]
  body: string[]
}

function words(s: string): string[] {
  return normalize(s).split(" ").filter(Boolean)
}

export function prepareHelpIndex(entries: HelpEntry[]): Prepared[] {
  return entries.map((entry) => ({
    entry,
    title: words(entry.title),
    keywords: (entry.keywords ?? []).flatMap(words),
    body: words(`${entry.body} ${entry.category}`),
  }))
}

/** How well one query word lands in a list of words: 1 exact/prefix, 0.7 typo, 0 none. */
function land(q: string, ws: string[]): number {
  let best = 0
  for (const w of ws) {
    const m = wordMatches(q, w)
    if (m === "prefix") return 1
    if (m === "typo") best = 0.7
  }
  return best
}

export interface HelpHit {
  entry: HelpEntry
  score: number
  /** The query words that matched, for highlighting. */
  matched: string[]
}

export function searchHelp(query: string, index: Prepared[], limit = 30): HelpHit[] {
  const qs = meaningfulWords(query)
  if (qs.length === 0) return []
  const hits: HelpHit[] = []
  for (const p of index) {
    let total = 0
    let landed = 0
    const matched: string[] = []
    for (const q of qs) {
      // Title words are worth three, keywords two and a half, body one.
      const s = Math.max(land(q, p.title) * 3, land(q, p.keywords) * 2.5, land(q, p.body))
      if (s > 0) { landed++; matched.push(q) }
      total += s
    }
    if (landed === 0 || landed < Math.ceil(qs.length / 2)) continue
    // Normalised to 0-100, plus a bonus when the whole phrase reads like the title.
    const score = (total / (qs.length * 3)) * 100 + scoreText(query, p.entry.title) * 0.3
    hits.push({ entry: p.entry, score, matched })
  }
  return hits.sort((a, b) => b.score - a.score).slice(0, limit)
}

/**
 * Split `text` into plain and highlighted runs for the matched words. Matches
 * word STARTS only, so "sale" lights up "sales" but not "wholesale".
 */
export function highlightRuns(text: string, matched: string[]): { text: string; hit: boolean }[] {
  if (matched.length === 0) return [{ text, hit: false }]
  const escaped = matched
    .filter((m) => m.length >= 2)
    .map((m) => m.replace(/[.*+?^${}()|[\]\\]/g, "\\$&"))
  if (escaped.length === 0) return [{ text, hit: false }]
  const re = new RegExp(`\\b(${escaped.join("|")})[a-z]*`, "gi")
  const out: { text: string; hit: boolean }[] = []
  let last = 0
  for (const m of text.matchAll(re)) {
    const i = m.index ?? 0
    if (i > last) out.push({ text: text.slice(last, i), hit: false })
    out.push({ text: m[0], hit: true })
    last = i + m[0].length
  }
  if (last < text.length) out.push({ text: text.slice(last), hit: false })
  return out
}

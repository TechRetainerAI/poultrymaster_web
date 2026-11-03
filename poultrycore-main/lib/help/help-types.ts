/**
 * The shape of a Help Center entry. Kept apart from the content so the search
 * and its tests do not have to load every answer.
 */

export type HelpKind = "faq" | "fix" | "term"

export interface HelpLink {
  label: string
  href: string
}

export interface HelpEntry {
  /** Stable, URL-safe. Used as the #anchor, so do not rename once shipped. */
  id: string
  kind: HelpKind
  /** FAQ category, or the area a troubleshooting entry / term belongs to. */
  category: string
  /** The question, the symptom, or the term. */
  title: string
  /**
   * The answer. Paragraphs are separated by a blank line; a paragraph whose
   * lines start "1. ", "2. " renders as numbered steps, "- " as bullets.
   */
  body: string
  /** Words people use for this that are not in the title. */
  keywords?: string[]
  /**
   * Pages the answer is about. Shown as buttons, and only for pages the
   * user may open -- a link is never a way around a permission.
   */
  links?: HelpLink[]
}

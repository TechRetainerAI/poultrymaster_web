"use client"

/**
 * The user's Quick Links choice, held once for the whole app.
 *
 * Every nav surface renders the bar -- the desktop rail, the sidebar and the
 * mobile More sheet -- and all three are mounted at once on a desktop. A fetch
 * per surface would be three requests for one answer and three chances for
 * them to disagree mid-flight, so this store fetches once per company and they
 * all read it.
 *
 * NOT persisted. The farm-settings store persists because its answer is the
 * same for everyone in the company and stale currency text is harmless; this
 * one is per user per company and a stale copy would show someone else's bar
 * after a login on a shared machine. It is one small request on boot.
 *
 * `hrefs: null` means NEVER CUSTOMISED -- the nav shows its own defaults. `[]`
 * means the user cleared the bar. The two are not the same and nothing in here
 * may collapse them.
 */

import { useEffect } from "react"
import { create } from "zustand"
import {
  getUserQuickLinks, saveUserQuickLinks, resetUserQuickLinks,
} from "@/lib/api/quick-links"
import { getUserContext } from "@/lib/api/config"

interface QuickLinksState {
  /** The company this answer is for, so a company switch refetches. */
  farmId: string
  hrefs: string[] | null
  loading: boolean
  /** The last load failed. The nav falls back to defaults; the dialog says so. */
  error: string

  load: (force?: boolean) => Promise<void>
  save: (hrefs: string[]) => Promise<void>
  reset: () => Promise<void>
}

/**
 * The one in-flight load, shared.
 *
 * Three nav surfaces mount together on a desktop and each calls load() on
 * mount. Without this they race: three requests for one answer, and the last
 * one to land wins whether or not it was the last one sent.
 */
let inFlight: Promise<void> | null = null

export const useQuickLinksStore = create<QuickLinksState>()((set, get) => ({
  farmId: "",
  hrefs: null,
  loading: false,
  error: "",

  async load(force = false) {
    const { farmId, userId } = getUserContext()
    if (!farmId || !userId) return
    if (!force && get().farmId === farmId && !get().error) return
    if (inFlight) return inFlight

    set({ loading: true, error: "" })
    inFlight = (async () => {
      try {
        const res = await getUserQuickLinks()
        // customised, not hrefs.length: an empty bar the user chose is an answer.
        set({ farmId, hrefs: res?.customised ? res.hrefs : null })
      } catch (e: any) {
        // The nav must render either way. Defaults are the safe fallback, and
        // farmId is left alone so the next load retries rather than caching the
        // failure as an answer.
        set({ hrefs: null, error: e?.message || "Quick Links could not be loaded." })
      } finally {
        set({ loading: false })
        inFlight = null
      }
    })()
    return inFlight
  },

  async save(hrefs) {
    const res = await saveUserQuickLinks(hrefs)
    const { farmId } = getUserContext()
    // The SERVER's list, after 318 cleaned it -- not the one we sent.
    set({ farmId, hrefs: res.hrefs, error: "" })
  },

  async reset() {
    await resetUserQuickLinks()
    const { farmId } = getUserContext()
    set({ farmId, hrefs: null, error: "" })
  },
}))

/**
 * The bar this user wants, loading it once if it has not been loaded.
 *
 * Every nav surface calls this and passes the result into its config builder.
 * Returns null while loading and null when never customised -- both mean "show
 * the defaults", which is the right thing to render in either case and is why
 * they do not need telling apart here.
 */
export function useQuickLinkHrefs(): string[] | null {
  const hrefs = useQuickLinksStore((s) => s.hrefs)
  const load = useQuickLinksStore((s) => s.load)
  useEffect(() => { void load() }, [load])
  return hrefs
}

"use client"

import { useEffect } from "react"

/**
 * Lets a list page be filtered from the header search: picks up the
 * `globalSearchQuery` hand-off left when the search navigated here, and
 * follows the live `globalSearch` event while the user types on this page.
 *
 * The older poultry list pages do the same thing inline; new pages should use
 * this, and add their route to GLOBAL_SEARCH_FILTER_PAGES in
 * components/dashboard/global-search.tsx.
 */
export function useGlobalSearchPrefill(setSearch: (q: string) => void) {
  useEffect(() => {
    const handed = sessionStorage.getItem("globalSearchQuery")
    if (handed) {
      setSearch(handed)
      sessionStorage.removeItem("globalSearchQuery")
    }
    const onSearch = (e: Event) => setSearch((e as CustomEvent<{ query: string }>).detail?.query ?? "")
    window.addEventListener("globalSearch", onSearch)
    return () => window.removeEventListener("globalSearch", onSearch)
    // setSearch is a state setter: stable.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [])
}

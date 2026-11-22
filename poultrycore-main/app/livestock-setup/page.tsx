"use client"

// The old combined Farm setup page is now three pages: Company settings,
// Animals kept and Pens. This forwards old links and bookmarks.

import { useEffect } from "react"
import { useRouter } from "next/navigation"
import { Loading } from "@/components/livestock/livestock-page"

export default function LivestockSetupRedirect() {
  const router = useRouter()
  useEffect(() => {
    const tab = new URLSearchParams(window.location.search).get("tab")
    router.replace(tab === "pens" ? "/livestock-pens" : tab === "species" ? "/livestock-animals-kept" : "/livestock-company-settings")
  }, [router])
  return <Loading />
}

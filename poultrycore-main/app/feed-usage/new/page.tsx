"use client"

// Feed Usage (389) is recorded from a dialog on /feed-usage that draws feed
// from stock. This route stays for old links and bookmarks and opens it.

import { useEffect } from "react"
import { useRouter } from "next/navigation"

export default function NewFeedUsageRedirect() {
  const router = useRouter()
  useEffect(() => { router.replace("/feed-usage?record=1") }, [router])
  return null
}

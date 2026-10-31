"use client"

// The old feed usage edit page. Since 389 feed lives as feed lines on the
// flock's production record, so it is changed there (or the Feed Usage entry is
// reversed). Old links land on the feed log.

import { useEffect } from "react"
import { useRouter } from "next/navigation"

export default function FeedUsageDetailRedirect() {
  const router = useRouter()
  useEffect(() => { router.replace("/feed-usage") }, [router])
  return null
}

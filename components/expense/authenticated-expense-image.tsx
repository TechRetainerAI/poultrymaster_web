"use client"

import { useEffect, useState } from "react"
import { ImageIcon } from "lucide-react"
import { cn } from "@/lib/utils"

type AuthenticatedExpenseImageProps = {
  expenseId: number
  userId: string
  farmId: string
  alt?: string
  className?: string
  fallbackClassName?: string
}

export function AuthenticatedExpenseImage({
  expenseId,
  userId,
  farmId,
  alt = "",
  className,
  fallbackClassName,
}: AuthenticatedExpenseImageProps) {
  const [src, setSrc] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let cancelled = false
    let blobUrl: string | null = null

    const run = async () => {
      setFailed(false)
      setSrc(null)
      const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
      if (!token || !userId || !farmId) {
        setFailed(true)
        return
      }
      const q = new URLSearchParams({ userId, farmId })
      const url = `/api/expense-image/${expenseId}?${q}`
      try {
        const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
        if (!res.ok || cancelled) {
          if (!cancelled) setFailed(true)
          return
        }
        const blob = await res.blob()
        if (cancelled) return
        blobUrl = URL.createObjectURL(blob)
        setSrc(blobUrl)
      } catch {
        if (!cancelled) setFailed(true)
      }
    }

    void run()

    return () => {
      cancelled = true
      if (blobUrl) URL.revokeObjectURL(blobUrl)
    }
  }, [expenseId, userId, farmId])

  if (failed || !src) {
    return (
      <div
        className={cn(
          "flex items-center justify-center rounded-md border border-dashed border-slate-200 bg-slate-50",
          fallbackClassName ?? "h-10 w-10"
        )}
      >
        <ImageIcon className={cn("h-4 w-4 text-slate-400", failed && "text-amber-600/90")} aria-hidden />
      </div>
    )
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={alt} className={className} />
  )
}

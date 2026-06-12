"use client"

import { useEffect, useState } from "react"
import { ImageIcon } from "lucide-react"
import { cn } from "@/lib/utils"

type AuthenticatedHealthImageProps = {
  healthRecordId: number
  userId: string
  farmId: string
  alt?: string
  className?: string
  /** Shown while loading or on error */
  fallbackClassName?: string
  /**
   * If the DB attachment fetch fails (or list API omitted hasAttachmentImage), try this URL next
   * (e.g. legacy `/api/receipt-file/receipt-uploads/...` from notes). Avoids a broken `<img>` when
   * the file was never on disk but bytes exist in SQL.
   */
  legacyFallbackSrc?: string | null
}

/**
 * Loads GET /api/health-image/{id} with Bearer token (img src cannot), then displays a blob URL.
 */
export function AuthenticatedHealthImage({
  healthRecordId,
  userId,
  farmId,
  alt = "",
  className,
  fallbackClassName,
  legacyFallbackSrc,
}: AuthenticatedHealthImageProps) {
  const [src, setSrc] = useState<string | null>(null)
  const [legacySrc, setLegacySrc] = useState<string | null>(null)
  const [failed, setFailed] = useState(false)

  useEffect(() => {
    let cancelled = false
    let blobUrl: string | null = null

    const run = async () => {
      setFailed(false)
      setSrc(null)
      setLegacySrc(null)
      const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
      if (!token || !userId || !farmId) {
        if (legacyFallbackSrc?.trim()) {
          if (!cancelled) setLegacySrc(legacyFallbackSrc.trim())
          return
        }
        setFailed(true)
        return
      }
      const q = new URLSearchParams({ userId, farmId })
      const url = `/api/health-image/${healthRecordId}?${q}`
      try {
        const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } })
        const blob = res.ok ? await res.blob() : null
        if (cancelled) return
        if (res.ok && blob && blob.size > 0) {
          blobUrl = URL.createObjectURL(blob)
          setSrc(blobUrl)
          return
        }
        if (legacyFallbackSrc?.trim()) {
          setLegacySrc(legacyFallbackSrc.trim())
          return
        }
        setFailed(true)
      } catch {
        if (cancelled) return
        if (legacyFallbackSrc?.trim()) {
          setLegacySrc(legacyFallbackSrc.trim())
          return
        }
        setFailed(true)
      }
    }

    void run()

    return () => {
      cancelled = true
      if (blobUrl) URL.revokeObjectURL(blobUrl)
    }
  }, [healthRecordId, userId, farmId, legacyFallbackSrc])

  if (legacySrc && !src) {
    return (
      // eslint-disable-next-line @next/next/no-img-element
      <img
        src={legacySrc}
        alt={alt}
        className={className}
        onError={() => {
          setLegacySrc(null)
          setFailed(true)
        }}
      />
    )
  }

  if (failed || !src) {
    return (
      <div
        className={cn(
          "flex items-center justify-center rounded-md border border-dashed border-slate-600 bg-slate-800/50",
          fallbackClassName ?? "h-14 w-14"
        )}
      >
        <ImageIcon className={cn("text-slate-500", failed ? "text-amber-600/90" : "")} aria-hidden />
      </div>
    )
  }

  return (
    // eslint-disable-next-line @next/next/no-img-element
    <img src={src} alt={alt} className={className} />
  )
}

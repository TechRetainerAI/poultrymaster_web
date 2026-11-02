"use client"

import { useEffect, useRef } from "react"

/* eslint-disable @typescript-eslint/no-explicit-any */

/** The quality asked for once the video starts. */
const PREFERRED_QUALITY = "hd720"

let apiPromise: Promise<any> | null = null

/** Loads YouTube's IFrame Player API once per page and resolves with `YT`. */
function loadYouTubeApi(): Promise<any> {
  const w = window as any
  if (w.YT?.Player) return Promise.resolve(w.YT)
  if (!apiPromise) {
    apiPromise = new Promise((resolve, reject) => {
      const previous = w.onYouTubeIframeAPIReady
      w.onYouTubeIframeAPIReady = () => {
        previous?.()
        resolve(w.YT)
      }
      const script = document.createElement("script")
      script.src = "https://www.youtube.com/iframe_api"
      script.async = true
      script.onerror = () => {
        apiPromise = null
        reject(new Error("youtube-api-unavailable"))
      }
      document.head.appendChild(script)
    })
  }
  return apiPromise
}

/**
 * A YouTube player that asks for 720p as it starts. YouTube treats the ask as
 * a hint: it still drops lower on a slow connection, and a fresh upload has
 * only low qualities until YouTube finishes processing it.
 */
export function YouTubePlayer({ videoId, title, onEnded }: { videoId: string; title: string; onEnded?: () => void }) {
  const hostRef = useRef<HTMLDivElement>(null)
  // Kept in a ref so a new callback does not rebuild the player.
  const onEndedRef = useRef(onEnded)
  onEndedRef.current = onEnded

  useEffect(() => {
    let player: any = null
    let cancelled = false

    const askForHd = (p: any) => {
      try {
        p.setPlaybackQualityRange?.(PREFERRED_QUALITY, PREFERRED_QUALITY)
        p.setPlaybackQuality?.(PREFERRED_QUALITY)
      } catch {
        // The ask is best effort; the video plays either way.
      }
    }

    loadYouTubeApi()
      .then((YT) => {
        if (cancelled || !hostRef.current) return
        // The API replaces the element it is given, so it gets a child of
        // ours rather than the div React owns.
        const mount = document.createElement("div")
        hostRef.current.appendChild(mount)
        let askedWhilePlaying = false
        player = new YT.Player(mount, {
          host: "https://www.youtube-nocookie.com",
          videoId,
          width: "100%",
          height: "100%",
          playerVars: { autoplay: 1, rel: 0, playsinline: 1, vq: PREFERRED_QUALITY },
          events: {
            onReady: (e: any) => {
              e.target.getIframe()?.setAttribute("title", title)
              askForHd(e.target)
              e.target.playVideo()
            },
            onStateChange: (e: any) => {
              // Asked again once playback starts: YouTube settles the
              // quality then, and can override an earlier ask.
              if (e.data === YT.PlayerState.PLAYING && !askedWhilePlaying) {
                askedWhilePlaying = true
                askForHd(e.target)
              }
              if (e.data === YT.PlayerState.ENDED) onEndedRef.current?.()
            },
          },
        })
      })
      .catch(() => {
        // Script blocked or offline: fall back to a plain embed.
        if (cancelled || !hostRef.current) return
        const iframe = document.createElement("iframe")
        iframe.src = `https://www.youtube-nocookie.com/embed/${videoId}?autoplay=1&rel=0&vq=${PREFERRED_QUALITY}`
        iframe.title = title
        iframe.allow = "accelerometer; autoplay; clipboard-write; encrypted-media; gyroscope; picture-in-picture; web-share"
        iframe.allowFullscreen = true
        iframe.className = "w-full h-full"
        hostRef.current.appendChild(iframe)
      })

    return () => {
      cancelled = true
      try {
        player?.destroy()
      } catch {
        // Already gone with the page.
      }
      if (hostRef.current) hostRef.current.innerHTML = ""
    }
  }, [videoId, title])

  return <div ref={hostRef} className="w-full h-full [&>iframe]:w-full [&>iframe]:h-full" />
}

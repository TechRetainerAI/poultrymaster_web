import { NextResponse } from "next/server"
import { YOUTUBE_VIDEOS, channelIdFromPage, parseChannel, parseChannelFeed } from "@/lib/help/poultry-videos"

export const runtime = "nodejs"
// Run per request so the YOUTUBE_VIDEOS env var is read at runtime, not baked
// in at build; the fetches below still cache YouTube's answer.
export const dynamic = "force-dynamic"

/** How long a fetched feed is reused before YouTube is asked again. */
const REVALIDATE_SECONDS = 1800

/**
 * The playlist's (or channel's) latest videos for /poultry-videos. Public
 * content, so no auth: it only ever returns what anyone can see on YouTube.
 */
export async function GET() {
  const channel = parseChannel(process.env.YOUTUBE_VIDEOS || YOUTUBE_VIDEOS)
  if (!channel) return NextResponse.json({ error: "not-configured" }, { status: 404 })

  try {
    if ("playlist" in channel) {
      const res = await fetch(`https://www.youtube.com/feeds/videos.xml?playlist_id=${channel.playlist}`, {
        next: { revalidate: REVALIDATE_SECONDS },
      })
      if (!res.ok) return NextResponse.json({ error: "feed-unavailable" }, { status: 502 })
      const feed = {
        ...parseChannelFeed(await res.text()),
        playlistUrl: `https://www.youtube.com/playlist?list=${channel.playlist}`,
      }
      return NextResponse.json(feed, {
        headers: { "Cache-Control": `public, max-age=300, s-maxage=${REVALIDATE_SECONDS}` },
      })
    }

    let id = "id" in channel ? channel.id : null
    if (!id) {
      const page = await fetch(`https://www.youtube.com/${"handle" in channel ? channel.handle : ""}`, {
        headers: { "Accept-Language": "en", Cookie: "CONSENT=YES+1" },
        next: { revalidate: 86400 },
      })
      if (page.ok) id = channelIdFromPage(await page.text())
      if (!id) return NextResponse.json({ error: "channel-not-found" }, { status: 502 })
    }

    const res = await fetch(`https://www.youtube.com/feeds/videos.xml?channel_id=${id}`, {
      next: { revalidate: REVALIDATE_SECONDS },
    })
    if (!res.ok) return NextResponse.json({ error: "feed-unavailable" }, { status: 502 })

    return NextResponse.json(parseChannelFeed(await res.text()), {
      headers: { "Cache-Control": `public, max-age=300, s-maxage=${REVALIDATE_SECONDS}` },
    })
  } catch {
    return NextResponse.json({ error: "feed-unavailable" }, { status: 502 })
  }
}

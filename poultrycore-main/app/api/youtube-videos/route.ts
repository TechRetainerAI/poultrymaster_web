import { NextResponse } from "next/server"
import { YOUTUBE_VIDEOS, channelIdFromPage, parseChannel, parseChannelFeed } from "@/lib/help/poultry-videos"

export const runtime = "nodejs"
// Run per request so the YOUTUBE_VIDEOS env var is read at runtime, not baked
// in at build; the fetches below still cache YouTube's answer.
export const dynamic = "force-dynamic"

/** How long a fetched feed is reused before YouTube is asked again. */
const REVALIDATE_SECONDS = 300

/**
 * An empty, successful answer. No playlist set, a playlist that does not exist
 * yet, or YouTube being briefly unreachable are all just "no videos to show" --
 * never a fault. We answer 200 with an empty list so the page shows its calm
 * "No videos yet" state and the browser console stays clean (no 404 / 502).
 */
function emptyFeed() {
  return NextResponse.json(
    { channelTitle: "", channelUrl: "", videos: [] },
    { headers: { "Cache-Control": "public, max-age=60, s-maxage=60" } },
  )
}

/**
 * The playlist's (or channel's) latest videos for /poultry-videos. Public
 * content, so no auth: it only ever returns what anyone can see on YouTube.
 */
export async function GET() {
  const channel = parseChannel(process.env.YOUTUBE_VIDEOS || YOUTUBE_VIDEOS)
  if (!channel) return emptyFeed()

  try {
    if ("playlist" in channel) {
      const res = await fetch(`https://www.youtube.com/feeds/videos.xml?playlist_id=${channel.playlist}`, {
        next: { revalidate: REVALIDATE_SECONDS },
      })
      if (!res.ok) return emptyFeed()
      const feed = {
        ...parseChannelFeed(await res.text()),
        playlistUrl: `https://www.youtube.com/playlist?list=${channel.playlist}`,
      }
      return NextResponse.json(feed, {
        headers: { "Cache-Control": `public, max-age=60, s-maxage=${REVALIDATE_SECONDS}` },
      })
    }

    let id = "id" in channel ? channel.id : null
    if (!id) {
      const page = await fetch(`https://www.youtube.com/${"handle" in channel ? channel.handle : ""}`, {
        headers: { "Accept-Language": "en", Cookie: "CONSENT=YES+1" },
        next: { revalidate: 86400 },
      })
      if (page.ok) id = channelIdFromPage(await page.text())
      if (!id) return emptyFeed()
    }

    const res = await fetch(`https://www.youtube.com/feeds/videos.xml?channel_id=${id}`, {
      next: { revalidate: REVALIDATE_SECONDS },
    })
    if (!res.ok) return emptyFeed()

    return NextResponse.json(parseChannelFeed(await res.text()), {
      headers: { "Cache-Control": `public, max-age=60, s-maxage=${REVALIDATE_SECONDS}` },
    })
  } catch {
    return emptyFeed()
  }
}

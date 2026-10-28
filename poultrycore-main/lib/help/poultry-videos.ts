/**
 * The training videos on /poultry-videos (System > Videos) come straight from
 * our YouTube playlist's public feed, so a video added to the playlist shows
 * up on its own -- nothing to edit here. app/api/youtube-videos/route.ts
 * fetches the feed server-side (YouTube does not allow the browser to) and
 * caches it.
 *
 * YouTube's feed holds the 15 most recent videos only.
 */

/**
 * Where the videos come from: a playlist (its link or PL... id) or a channel
 * (youtube.com/@handle, youtube.com/channel/UC..., the @handle or the UC...
 * id). The YOUTUBE_VIDEOS env var overrides it.
 */
export const YOUTUBE_VIDEOS = "https://www.youtube.com/playlist?list=PLYzAmLbvpCls"

export interface ChannelVideo {
  id: string
  title: string
  description: string
  /** ISO date the video went up. */
  published: string
}

export interface ChannelFeed {
  channelTitle: string
  channelUrl: string
  /** Set when the videos come from a playlist. */
  playlistUrl?: string
  videos: ChannelVideo[]
}

const CHANNEL_ID = /^UC[A-Za-z0-9_-]{22}$/
const PLAYLIST_ID = /^(PL|OL|UU|FL)[A-Za-z0-9_-]{10,}$/

/**
 * What YOUTUBE_VIDEOS names: a playlist, a channel id, a handle to look up, or
 * nothing usable.
 */
export function parseChannel(input: string): { playlist: string } | { id: string } | { handle: string } | null {
  const s = input.trim()
  if (!s) return null
  if (PLAYLIST_ID.test(s)) return { playlist: s }
  if (CHANNEL_ID.test(s)) return { id: s }
  if (/^@[\w.-]+$/.test(s)) return { handle: s }
  let u: URL
  try {
    u = new URL(s.includes("://") ? s : `https://${s}`)
  } catch {
    return null
  }
  if (u.hostname.replace(/^(www|m)\./, "") !== "youtube.com") return null
  const list = u.searchParams.get("list")
  if (list && PLAYLIST_ID.test(list)) return { playlist: list }
  const [, first, second] = u.pathname.split("/")
  if (first === "channel" && second && CHANNEL_ID.test(second)) return { id: second }
  if (first?.startsWith("@") && first.length > 1) return { handle: decodeURIComponent(first) }
  return null
}

/** The channel id in a channel page's HTML, or null. */
export function channelIdFromPage(html: string): string | null {
  const m =
    html.match(/<link rel="canonical" href="https:\/\/www\.youtube\.com\/channel\/(UC[A-Za-z0-9_-]{22})"/) ??
    html.match(/"externalId":"(UC[A-Za-z0-9_-]{22})"/) ??
    html.match(/"channelId":"(UC[A-Za-z0-9_-]{22})"/)
  return m ? m[1] : null
}

function decode(s: string): string {
  return s
    .replace(/<!\[CDATA\[([\s\S]*?)\]\]>/g, "$1")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, '"')
    .replace(/&#39;|&apos;/g, "'")
    .replace(/&#(\d+);/g, (_, n) => String.fromCodePoint(Number(n)))
    .replace(/&#x([0-9a-f]+);/gi, (_, n) => String.fromCodePoint(parseInt(n, 16)))
    .replace(/&amp;/g, "&")
    .trim()
}

function tag(xml: string, name: string): string {
  const m = xml.match(new RegExp(`<${name}(?:\\s[^>]*)?>([\\s\\S]*?)</${name}>`))
  return m ? decode(m[1]) : ""
}

/** The videos in a channel's Atom feed (youtube.com/feeds/videos.xml), newest first. */
export function parseChannelFeed(xml: string): ChannelFeed {
  const [head] = xml.split("<entry>")
  const author = tag(head, "author")
  const videos = (xml.match(/<entry>[\s\S]*?<\/entry>/g) ?? [])
    .map((entry) => ({
      id: tag(entry, "yt:videoId"),
      title: tag(entry, "title"),
      description: tag(entry, "media:description"),
      published: tag(entry, "published"),
    }))
    .filter((v) => /^[A-Za-z0-9_-]{11}$/.test(v.id))
    .sort((a, b) => b.published.localeCompare(a.published))
  return {
    channelTitle: tag(author, "name") || tag(head, "title"),
    channelUrl: tag(author, "uri"),
    videos,
  }
}

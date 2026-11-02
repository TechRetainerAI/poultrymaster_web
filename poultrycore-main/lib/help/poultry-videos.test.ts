import { describe, expect, it } from "vitest"
import { channelIdFromPage, parseChannel, parseChannelFeed } from "./poultry-videos"

const UC = "UCabcdefghijklmnopqrstuv"

describe("parseChannel", () => {
  it.each([
    [UC, { id: UC }],
    [`https://www.youtube.com/channel/${UC}`, { id: UC }],
    [`youtube.com/channel/${UC}/videos`, { id: UC }],
    ["@PoultryMaster", { handle: "@PoultryMaster" }],
    ["https://www.youtube.com/@PoultryMaster", { handle: "@PoultryMaster" }],
    ["https://m.youtube.com/@PoultryMaster/videos?view=0", { handle: "@PoultryMaster" }],
    ["https://www.youtube.com/playlist?list=PLYzAmLbvpCls", { playlist: "PLYzAmLbvpCls" }],
    ["https://www.youtube.com/watch?v=dQw4w9WgXcQ&list=PLYzAmLbvpCls", { playlist: "PLYzAmLbvpCls" }],
    ["PLYzAmLbvpCls", { playlist: "PLYzAmLbvpCls" }],
  ])("reads %s", (input, want) => {
    expect(parseChannel(input)).toEqual(want)
  })

  it.each(["", "   ", "not a channel", "https://www.youtube.com/watch?v=dQw4w9WgXcQ", "https://example.com/@x", "UCtooShort"])(
    "rejects %s",
    (input) => {
      expect(parseChannel(input)).toBeNull()
    },
  )
})

describe("channelIdFromPage", () => {
  it("reads the canonical link", () => {
    expect(channelIdFromPage(`<link rel="canonical" href="https://www.youtube.com/channel/${UC}">`)).toBe(UC)
  })
  it("falls back to the page data", () => {
    expect(channelIdFromPage(`{"externalId":"${UC}"}`)).toBe(UC)
  })
  it("returns null when there is none", () => {
    expect(channelIdFromPage("<html></html>")).toBeNull()
  })
})

const FEED = `<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns:yt="http://www.youtube.com/xml/schemas/2015" xmlns:media="http://search.yahoo.com/mrss/" xmlns="http://www.w3.org/2005/Atom">
 <link rel="self" href="http://www.youtube.com/feeds/videos.xml?channel_id=${UC}"/>
 <yt:channelId>${UC}</yt:channelId>
 <title>Poultry Master</title>
 <author>
  <name>Poultry Master</name>
  <uri>https://www.youtube.com/channel/${UC}</uri>
 </author>
 <entry>
  <id>yt:video:aaaaaaaaaaa</id>
  <yt:videoId>aaaaaaaaaaa</yt:videoId>
  <title>Older: Feed &amp; Water</title>
  <published>2026-09-01T10:00:00+00:00</published>
  <media:group>
   <media:title>Older: Feed &amp; Water</media:title>
   <media:description>Line one
Line two &quot;quoted&quot;</media:description>
   <media:community>
    <media:starRating count="12" average="5.00" min="1" max="5"/>
    <media:statistics views="1234"/>
   </media:community>
  </media:group>
 </entry>
 <entry>
  <id>yt:video:bbbbbbbbbbb</id>
  <yt:videoId>bbbbbbbbbbb</yt:videoId>
  <title>Newer: Egg sorting</title>
  <published>2026-10-01T10:00:00+00:00</published>
  <media:group><media:description></media:description></media:group>
 </entry>
</feed>`

describe("parseChannelFeed", () => {
  const feed = parseChannelFeed(FEED)

  it("reads the channel", () => {
    expect(feed.channelTitle).toBe("Poultry Master")
    expect(feed.channelUrl).toBe(`https://www.youtube.com/channel/${UC}`)
  })

  it("lists the videos newest first, with entities decoded", () => {
    expect(feed.videos).toEqual([
      { id: "bbbbbbbbbbb", title: "Newer: Egg sorting", description: "", published: "2026-10-01T10:00:00+00:00" },
      { id: "aaaaaaaaaaa", title: "Older: Feed & Water", description: 'Line one\nLine two "quoted"', published: "2026-09-01T10:00:00+00:00", views: 1234 },
    ])
  })

  it("survives an empty or broken feed", () => {
    expect(parseChannelFeed("").videos).toEqual([])
    expect(parseChannelFeed("<html>error</html>").videos).toEqual([])
  })
})

#!/usr/bin/env node
/**
 * Captures the annotated Help Center screenshots.
 *
 *   HELP_SHOTS_USER=demo HELP_SHOTS_PASS=... npm run screenshots
 *   npm run screenshots -- --only=record-sale,add-expense
 *
 * Env:
 *   HELP_SHOTS_URL      app to photograph (default http://localhost:3000)
 *   HELP_SHOTS_USER     login of a DEMO account -- one poultry company, fake data
 *   HELP_SHOTS_PASS
 *   HELP_SHOTS_COMPANY  required company name; the run refuses any other, so
 *                       a real farm's customers never end up in a help picture
 *
 * READ-ONLY BY CONSTRUCTION: every non-GET request to /api/proxy except the
 * login and the company switch (both only issue tokens) is aborted, so a click
 * that lands on Save cannot write data.
 *
 * Writes public/help/<entry>-<n>.jpg and merges lib/help/help-shots.json.
 * An entry whose shots fail keeps its previous pictures.
 */

import { chromium } from "playwright"
import { mkdir, readdir, readFile, rm, writeFile } from "node:fs/promises"
import os from "node:os"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { SHOTS } from "./shots.mjs"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..", "..")
const OUT_DIR = path.join(ROOT, "public", "help")
const MANIFEST = path.join(ROOT, "lib", "help", "help-shots.json")

const BASE = (process.env.HELP_SHOTS_URL || "http://localhost:3000").replace(/\/$/, "")
const USER = process.env.HELP_SHOTS_USER
const PASS = process.env.HELP_SHOTS_PASS
const COMPANY = process.env.HELP_SHOTS_COMPANY
const VIEWPORT = { width: 1366, height: 820 }
const onlyArg = process.argv.find((a) => a.startsWith("--only="))
const ONLY = onlyArg ? new Set(onlyArg.slice(7).split(",").map((s) => s.trim()).filter(Boolean)) : null

if (!USER || !PASS || !COMPANY) {
  console.error("Set HELP_SHOTS_USER, HELP_SHOTS_PASS and HELP_SHOTS_COMPANY (a demo account and its demo company).")
  process.exit(2)
}

const escape = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")

/** A target spec -> a Playwright locator for the first VISIBLE match. */
function locate(page, t) {
  let loc
  // within: "dialog" looks only inside the open dialog.
  const root = t.within === "dialog" ? page.getByRole("dialog").locator("visible=true").last() : page
  // Anchored, so "Add Flock" does not also match "Add Flock Batch".
  if (t.button) loc = root.getByRole("button", { name: new RegExp(`^\\s*${escape(t.button)}\\s*$`, "i") })
  else if (t.tab) loc = root.getByRole("tab", { name: new RegExp(`^\\s*${escape(t.tab)}\\s*$`, "i") })
  else if (t.text) loc = root.getByText(t.text, { exact: !!t.exact })
  else if (t.label) loc = root.getByLabel(t.label)
  else if (t.css) loc = root.locator(t.css)
  else if (t.placeholder) loc = root.getByPlaceholder(t.placeholder)
  else throw new Error(`Unknown target ${JSON.stringify(t)}`)
  loc = loc.locator("visible=true")
  return t.nth != null ? loc.nth(t.nth) : loc.first()
}

const describe = (t) => JSON.stringify(t)

/**
 * { card: "Total Sales" }: the box of the card, panel or section holding that
 * exact text -- the nearest ancestor drawn with a border or a shadow -- so a
 * picture can point at a whole summary card instead of only its label.
 */
async function cardBox(page, label) {
  return page.evaluate((label) => {
    const want = label.trim().toLowerCase()
    const own = (el) => [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join("").trim().toLowerCase()
    const shown = [...document.querySelectorAll("body *")].filter((el) => el.getClientRects().length > 0 && !el.closest("nav, aside"))
    // Exact text first; "Total Purchase Price" also finds "Total Purchase Price (GH₵)".
    let hits = shown.filter((el) => own(el) === want)
    if (!hits.length) hits = shown.filter((el) => own(el).startsWith(want))
    const vw = window.innerWidth, vh = window.innerHeight
    let best = null
    for (const el of hits) {
      for (let p = el; p && p !== document.body; p = p.parentElement) {
        const cs = getComputedStyle(p)
        const r = p.getBoundingClientRect()
        const drawn = parseFloat(cs.borderTopWidth) > 0 || parseFloat(cs.borderLeftWidth) > 0 || cs.boxShadow !== "none"
        if (drawn && r.width > 60 && r.height > 28) {
          // The same words can sit in a small badge and in a big panel:
          // point at the biggest, but never at a whole-page wrapper.
          if (r.width * r.height < vw * vh * 0.5 && (!best || r.width * r.height > best.r.width * best.r.height)) best = { p, r }
          break
        }
      }
    }
    if (!best) return null
    best.p.scrollIntoView({ block: "nearest" })
    const b = best.p.getBoundingClientRect()
    return { x: b.x, y: b.y, width: b.width, height: b.height }
  }, label)
}

/**
 * Example values for a form, so the picture shows a filled-in form, not an
 * empty one. Typing never reaches the server (the save is blocked anyway).
 *   fill: [{ ...target, value }]          type into a box
 *   pick: [{ ...target, option | nth }]   open a dropdown and choose
 * A value that cannot be entered is only a warning: the picture still works.
 */
async function enterValues(page, s, where) {
  for (const f of s.fill ?? []) {
    try {
      const box = locate(page, f)
      await box.fill(String(f.value), { timeout: 8_000 })
    } catch (e) {
      console.warn(`  ! ${where}: could not type into ${describe(f)}`)
    }
  }
  for (const p of s.pick ?? []) {
    try {
      const trigger = locate(page, p)
      await trigger.waitFor({ state: "visible", timeout: 8_000 })
      if ((await trigger.evaluate((el) => el.tagName)) === "SELECT") {
        await trigger.selectOption(p.option != null ? { label: p.option } : { index: (p.nth ?? 0) + 1 })
      } else {
        await trigger.click()
        const options = page.getByRole("option").locator("visible=true")
        await options.first().waitFor({ state: "visible", timeout: 8_000 })
        const choice = p.option != null ? options.filter({ hasText: new RegExp(`^\\s*${escape(p.option)}\\b`, "i") }).first() : options.nth(p.nth ?? 0)
        await choice.click({ timeout: 8_000 })
      }
      await settle(page)
    } catch (e) {
      console.warn(`  ! ${where}: could not choose in ${describe(p)}`)
      await page.keyboard.press("Escape").catch(() => {})
    }
  }
  if (s.fill?.length) await page.waitForTimeout(400)
}

/** Hide things that should never be in a help picture. */
const CLEAN_CSS = `
  nextjs-portal, [data-nextjs-toast], [data-nextjs-dev-tools-button], #__next-build-watcher { display: none !important; }
  [data-sonner-toaster] { display: none !important; }
  *, *::before, *::after { animation-duration: 0s !important; transition-duration: 0s !important; caret-color: transparent !important; }
`

async function settle(page) {
  await page.waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => {})
  // After an in-app (client-side) navigation the load state is already
  // "idle" before the new page has even asked for its data -- give it a beat
  // to start, then wait for that traffic to finish too.
  await page.waitForTimeout(1_000)
  await page.waitForLoadState("networkidle", { timeout: 20_000 }).catch(() => {})
  // Skeletons / spinners from React Query.
  await page.waitForFunction(() => !document.querySelector('[class*="animate-spin"], [class*="animate-pulse"]'), null, { timeout: 15_000 }).catch(() => {})
  // Selects that show "Loading…" until their options arrive.
  // Judged on an element's OWN text, so "Loading customers…" beside a spinner
  // icon counts too.
  await page.waitForFunction(() => ![...document.querySelectorAll("body *")].some((el) => {
    const own = [...el.childNodes].filter((n) => n.nodeType === 3).map((n) => n.textContent).join("").trim()
    return /^loading/i.test(own) && el.getClientRects().length > 0
  }), null, { timeout: 20_000 }).catch(() => {})
  await page.waitForTimeout(400)
}

/**
 * Orange box(es) around what to click. One box dims the rest of the page; with
 * several, each carries its number so "1 then 2" reads off the picture.
 */
async function drawBoxes(page, boxes) {
  await page.evaluate((boxes) => {
    const pad = 6
    boxes.forEach(({ x, y, width, height }, i) => {
      const el = document.createElement("div")
      el.className = "__help_shot_box"
      Object.assign(el.style, {
        position: "fixed", left: `${x - pad}px`, top: `${y - pad}px`,
        width: `${width + pad * 2}px`, height: `${height + pad * 2}px`,
        border: "3px solid #f97316", borderRadius: "10px",
        boxShadow: boxes.length === 1
          ? "0 0 0 4px rgba(249,115,22,0.25), 0 0 0 9999px rgba(15,23,42,0.18)"
          : "0 0 0 4px rgba(249,115,22,0.25)",
        zIndex: "2147483647", pointerEvents: "none",
      })
      if (boxes.length > 1) {
        const n = document.createElement("div")
        n.textContent = String(i + 1)
        Object.assign(n.style, {
          position: "absolute", top: "-14px", left: "-14px", width: "26px", height: "26px",
          borderRadius: "9999px", background: "#f97316", color: "#fff", border: "2px solid #fff",
          font: "700 14px/22px system-ui, sans-serif", textAlign: "center",
        })
        el.appendChild(n)
      }
      document.body.appendChild(el)
    })
  }, boxes)
}

/** A top-nav trigger, not the sidebar's same-named group: the one furthest right. */
async function navTrigger(page, label) {
  const all = await page.getByRole("button", { name: new RegExp(`^\\s*${escape(label)}\\s*$`, "i") }).locator("visible=true").all()
  let best = null, bestX = -1
  for (const l of all) {
    const b = await l.boundingBox()
    if (b && b.y < 140 && b.x > bestX) { best = l; bestX = b.x }
  }
  if (!best) throw new Error(`no "${label}" in the top menu bar`)
  return best
}

/** Close anything a page pops up on arrival (announcements, prompts). */
async function dismissPopups(page) {
  for (let i = 0; i < 3; i++) {
    const d = page.locator('[role="alertdialog"], [role="dialog"]').locator("visible=true").first()
    if (!(await d.isVisible().catch(() => false))) return
    console.log(`    (closing a popup: ${((await d.innerText().catch(() => "")) || "").split("\n")[0].slice(0, 60)})`)
    await page.keyboard.press("Escape")
    await page.waitForTimeout(400)
  }
}

/**
 * Mark every email address and phone number on screen -- in text or in an
 * input -- so the screenshot paints over it. Help pictures ship to every
 * customer; contact details of whoever is in the demo company must not.
 */
async function markSensitive(page) {
  await page.evaluate(() => {
    const email = /[^\s@]+@[^\s@]+\.[^\s@]+/
    const phone = (s) => /^(\+\d{6,15}|0\d{8,10})$/.test(s.replace(/[\s()-]/g, ""))
    const hit = (s) => !!s && (email.test(s) || phone(s.trim()))
    for (const el of document.querySelectorAll("input, textarea")) {
      // An empty phone/email box (a new form) has nothing to hide.
      if (hit(el.value) || ((el.type === "email" || el.type === "tel") && el.value.trim())) el.setAttribute("data-help-mask", "")
    }
    for (const el of document.querySelectorAll("body *")) {
      if (el.childElementCount === 0 && hit((el.textContent || "").trim())) el.setAttribute("data-help-mask", "")
    }
  })
}

const clearBox = (page) => page.evaluate(() => document.querySelectorAll(".__help_shot_box").forEach((e) => e.remove()))

async function login(page) {
  await page.goto(`${BASE}/login`)
  await page.locator("#username").fill(USER)
  await page.locator("#password").fill(PASS)
  await page.locator("#password").press("Enter")
  // The "Login Successful!" card waits for a click.
  const go = page.getByRole("button", { name: /go to dashboard/i })
  await go.waitFor({ state: "visible", timeout: 30_000 }).then(() => go.click(), () => {})
  await page.waitForURL((u) => !/\/login/.test(u.pathname), { timeout: 60_000 })
  if (/login-2fa/.test(page.url())) throw new Error("The demo account has two-factor authentication on; use one without it.")
  await settle(page)

  // Not on the demo company yet: pick it in the header switcher.
  const activeName = () => page.evaluate(() => localStorage.getItem("farmName") || "")
  if ((await activeName()).trim().toLowerCase() !== COMPANY.trim().toLowerCase()) {
    // Owners land on the Business Office, which lists companies in its
    // sidebar; elsewhere the header has a "Switch company" menu.
    const exact = new RegExp(`^\\s*${escape(COMPANY)}\\s*$`, "i")
    let option = page.getByText(exact).locator("visible=true").first()
    if (!(await option.isVisible().catch(() => false))) {
      await page.getByRole("button", { name: /switch company/i }).first().click({ timeout: 15_000 })
      option = page.getByText(exact).locator("visible=true").first()
    }
    await option.click({ timeout: 15_000 }).catch(() => { throw new Error(`"${COMPANY}" is not in this account's company list.`) })
    await page.waitForFunction((want) => (localStorage.getItem("farmName") || "").trim().toLowerCase() === want, COMPANY.trim().toLowerCase(), { timeout: 30_000 })
    await settle(page)
  }

  const auth = await page.evaluate(() => {
    let state = {}
    try { state = JSON.parse(localStorage.getItem("auth-storage") || "{}").state ?? {} } catch {}
    return {
      activeFarmName: state.activeFarmName ?? localStorage.getItem("farmName"),
      activeFarmType: state.activeFarmType ?? localStorage.getItem("farmType"),
    }
  })
  const name = auth.activeFarmName
  if (!name || name.trim().toLowerCase() !== COMPANY.trim().toLowerCase()) {
    throw new Error(`Active company is "${name ?? "(none)"}", not "${COMPANY}". Refusing to photograph it. Log in as the demo account, or switch it to the demo company first.`)
  }
  if (auth.activeFarmType && auth.activeFarmType !== "Poultry") {
    throw new Error(`Active company type is ${auth.activeFarmType}; the help pictures are for Poultry.`)
  }
}

async function captureEntry(context, id, shots) {
  const page = await context.newPage()
  const results = []
  try {
    for (let i = 0; i < shots.length; i++) {
      const s = shots[i]
      const where = `${id} #${i + 1}`
      if (s.path) {
        await page.goto(`${BASE}${s.path}`)
        await settle(page)
        if (/\/login/.test(new URL(page.url()).pathname)) throw new Error(`${where}: sent back to login`)
        if (new URL(page.url()).pathname !== new URL(`${BASE}${s.path}`).pathname) {
          throw new Error(`${where}: ${s.path} redirected to ${new URL(page.url()).pathname} (no access for the demo user?)`)
        }
      }
      // A menu step: open the top-bar menu, box the trigger (1) and the row
      // (2), take the picture, then click through to the page.
      let menuBoxes = []
      let menuRow = null
      if (s.menu) {
        await dismissPopups(page)
        const trigger = await navTrigger(page, s.menu.bar)
        // The menus open on hover, and a click toggles -- so a click (which
        // hovers first) opens then shuts them. Hover, and click only if that
        // did not open it.
        menuRow = page.locator(`div[class*="z-[9999]"] a[href="${s.menu.href}"]`).locator("visible=true").first()
        await trigger.hover()
        const opened = await menuRow.waitFor({ state: "visible", timeout: 2_000 }).then(() => true, () => false)
        if (!opened) {
          await trigger.click()
          await menuRow.waitFor({ state: "visible", timeout: 8_000 }).catch(() => {
            throw new Error(`${where}: "${s.menu.bar}" menu has no row for ${s.menu.href}`)
          })
        }
        await page.waitForTimeout(300)
        menuBoxes = [await trigger.boundingBox(), await menuRow.boundingBox()]
      }

      // A step the user takes before this picture (a tab, a radio): click it
      // and wait for what it opens.
      if (s.click) {
        await dismissPopups(page) // a dialog left open by the previous picture
        await locate(page, s.click).click({ timeout: 10_000 }).catch(() => { throw new Error(`${where}: could not click ${describe(s.click)}`) })
        await settle(page)
        await dismissPopups(page)
      }
      if (s.focus) { await locate(page, s.focus).click({ timeout: 10_000 }); await page.waitForTimeout(300) }
      if (s.press) { await page.keyboard.press(s.press); await page.waitForTimeout(300) }
      if (s.type) { await page.keyboard.type(s.type, { delay: 40 }); await page.waitForTimeout(500) }

      await enterValues(page, s, where)
      // scrollTo: bring a later part of a long form (or page) into view.
      if (s.scrollTo) {
        // To the TOP of the view, not merely "in view": a heading already
        // peeking in at the bottom would otherwise not move at all.
        await locate(page, s.scrollTo).evaluate((el) => el.scrollIntoView({ block: "start" }), null, { timeout: 8_000 })
          .catch(() => console.warn(`  ! ${where}: could not scroll to ${describe(s.scrollTo)}`))
        await page.waitForTimeout(300)
      }

      // One target, or a list: several get numbered boxes (1, 2, ...).
      if (s.highlight) {
        const boxes = []
        for (const h of [].concat(s.highlight)) {
          if (h.card) {
            const box = await cardBox(page, h.card)
            if (box) boxes.push(box)
            else if (!s.optional) throw new Error(`${where}: no card with the text "${h.card}" on ${new URL(page.url()).pathname}`)
            else console.warn(`  ! ${where}: no card "${h.card}"; picture taken without that box`)
            continue
          }
          const target = locate(page, h)
          const found = await target.waitFor({ state: "visible", timeout: 10_000 }).then(() => true, () => false)
          if (found) {
            await target.scrollIntoViewIfNeeded()
            const box = await target.boundingBox()
            if (box) boxes.push(box)
          } else if (!s.optional) {
            throw new Error(`${where}: could not find ${describe(h)} on ${new URL(page.url()).pathname}`)
          } else {
            console.warn(`  ! ${where}: ${describe(h)} not shown; picture taken without that box`)
          }
        }
        if (boxes.length) await drawBoxes(page, boxes)
      }

      if (menuBoxes.length) await drawBoxes(page, menuBoxes)

      const file = `${id}-${i + 1}.jpg`
      const out = path.join(OUT_DIR, file)
      await markSensitive(page)
      const mask = [page.locator("[data-help-mask]"), ...(s.mask ?? []).map((t) => (t.css ? page.locator(t.css) : locate(page, t)))]
      const shotOpts = { path: out, type: "jpeg", quality: 82, mask, maskColor: "#cbd5e1" }
      let size
      if (s.area === "dialog") {
        const dialog = page.getByRole("dialog").locator("visible=true").last()
        await dialog.waitFor({ state: "visible", timeout: 10_000 }).catch(() => {
          throw new Error(`${where}: expected a dialog, none is open`)
        })
        await settle(page)
        await markSensitive(page)
        // Only what is inside the dialog: masks are painted on top, so a
        // masked phone number in the list behind it would show through.
        await dialog.screenshot({ ...shotOpts, mask: [dialog.locator("[data-help-mask]"), ...mask.slice(1)] })
        const b = await dialog.boundingBox()
        size = { width: Math.round(b.width), height: Math.round(b.height) }
      } else {
        await page.screenshot(shotOpts)
        size = { ...VIEWPORT }
      }
      await clearBox(page)
      results.push({ src: `/help/${file}`, caption: s.caption, ...size })
      console.log(`  ✓ ${where}`)

      if (menuRow) {
        await menuRow.click()
        const want = s.menu.href.split("?")[0]
        await page.waitForURL((u) => u.pathname === want, { timeout: 30_000 }).catch(() => {
          throw new Error(`${where}: the "${s.menu.bar}" menu row did not open ${want}`)
        })
        await settle(page)
        await dismissPopups(page)
      }

      if (s.then) {
        const next = locate(page, s.then)
        await next.click({ timeout: 10_000 }).catch(() => { throw new Error(`${where}: could not click ${describe(s.then)}`) })
        await settle(page)
      }
    }
    return results
  } finally {
    await page.close()
  }
}

async function main() {
  await mkdir(OUT_DIR, { recursive: true })
  let manifest = {}
  try { manifest = JSON.parse(await readFile(MANIFEST, "utf8")) } catch {}

  // Playwright's own Chromium if installed, otherwise the machine's Chrome.
  const browser = await chromium.launch().catch(() => chromium.launch({ channel: "chrome" }))
  const context = await browser.newContext({ viewport: VIEWPORT, deviceScaleFactor: 1, locale: "en-GB" })
  await context.addInitScript((css) => {
    const add = () => { const s = document.createElement("style"); s.textContent = css; document.head.appendChild(s) }
    if (document.head) add(); else document.addEventListener("DOMContentLoaded", add)
  }, CLEAN_CSS)

  // The guard: nothing but reads (and the login) reach the backend.
  const blocked = []
  await context.route("**/api/proxy/**", (route) => {
    const req = route.request()
    // Login, token refresh and company switch only issue tokens.
    if (req.method() === "GET" || /\/(Authentication\/|Companies\/switch$)/i.test(new URL(req.url()).pathname)) return route.continue()
    blocked.push(`${req.method()} ${new URL(req.url()).pathname}`)
    return route.abort("blockedbyclient")
  })

  const failures = []
  try {
    const page = await context.newPage()
    try {
      await login(page)
    } catch (e) {
      const shot = path.join(os.tmpdir(), "help-shots-login-failure.png")
      await page.screenshot({ path: shot }).catch(() => {})
      throw new Error(`${e.message}\n(Login screen at failure: ${shot}, URL ${page.url()})`)
    }
    await page.close()

    for (const [id, shots] of Object.entries(SHOTS)) {
      if (ONLY && !ONLY.has(id)) continue
      console.log(id)
      try {
        manifest[id] = await captureEntry(context, id, shots)
        // Pictures from a longer, older version of this walkthrough.
        for (const f of await readdir(OUT_DIR)) {
          const m = f.match(new RegExp(`^${escape(id)}-(\\d+)\\.jpg$`))
          if (m && Number(m[1]) > shots.length) await rm(path.join(OUT_DIR, f))
        }
      } catch (e) {
        failures.push(`${id}: ${e.message}`)
        console.error(`  ✗ ${e.message}`)
      }
    }
  } finally {
    await browser.close()
  }

  const sorted = Object.fromEntries(Object.entries(manifest).sort(([a], [b]) => a.localeCompare(b)))
  await writeFile(MANIFEST, JSON.stringify(sorted, null, 2) + "\n")

  if (blocked.length) console.log(`\nBlocked ${blocked.length} write request(s) (expected for read-model POSTs):\n  ${[...new Set(blocked)].join("\n  ")}`)
  if (failures.length) {
    console.error(`\n${failures.length} entr${failures.length === 1 ? "y" : "ies"} failed (kept their previous pictures):\n  ${failures.join("\n  ")}`)
    process.exit(1)
  }
  console.log("\nAll help screenshots captured.")
}

main().catch((e) => { console.error(e); process.exit(1) })

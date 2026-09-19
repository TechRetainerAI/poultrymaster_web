#!/usr/bin/env node
/**
 * dev-reset — recover from a damaged Turbopack dev route table.
 *
 * THE FAILURE THIS FIXES
 * Every `/api/proxy/*` call 404s with Next's HTML error page while ordinary
 * pages still load fine, so logging in dies with:
 *
 *   [Login diagnostic] Non-JSON response, HTTP 404
 *
 * The cause is `.next/dev/types/routes.d.ts` being written over itself without
 * being truncated first. It ends up holding two generations interleaved — you
 * can see two `export type { AppRoutes ... }` footers — and the surviving
 * `AppRoutes` line carries only page routes, with **no** `/api/*` route
 * handlers. `app/api/proxy/[...path]/route.ts` is therefore not in the route
 * table at all, so Next routes those requests into the page tree and answers
 * `/_not-found`. Nothing is wrong with the backend, the ports or the env, which
 * is exactly why it wastes so much time.
 *
 * Seen 2026-09-15 and again 2026-09-16, both times right after a large change.
 *
 * WHY A SCRIPT AND NOT JUST `rm -rf .next`
 *  - It only removes `.next/dev`, not the whole of `.next`. On Windows the full
 *    directory is ~11k files and slow to delete, and the production build output
 *    in `.next/` is untouched (`server.js` pins `distDir: '.next'`, and the
 *    Dockerfile copies `.next/standalone`, so blowing it away costs a rebuild).
 *  - It kills stray `next dev` processes FIRST. Two things go wrong otherwise:
 *    Windows file locks make the delete silently incomplete, and — observed on
 *    2026-09-16 — Ctrl+C can leave an orphaned `next-server` still holding port
 *    3000, so the replacement dev server quietly starts on 3001 while the
 *    browser keeps talking to the orphan and its broken cache.
 *
 * Usage:
 *   npm run dev:reset        stop strays, clear .next/dev, start `next dev`
 *   npm run dev:reset -- --check    report only, change nothing
 *   npm run dev:reset -- --no-start clean up but do not start the dev server
 */

import { execSync, spawn } from "node:child_process"
import { existsSync, readFileSync, rmSync, writeFileSync } from "node:fs"
import { tmpdir } from "node:os"
import { dirname, join } from "node:path"
import { fileURLToPath } from "node:url"

const root = dirname(dirname(fileURLToPath(import.meta.url)))
const devDir = join(root, ".next", "dev")
const routesFile = join(devDir, "types", "routes.d.ts")

const args = process.argv.slice(2)
const checkOnly = args.includes("--check")
const noStart = args.includes("--no-start")
const isWindows = process.platform === "win32"

const log = (...m) => console.log(...m)

/** Healthy: one footer, and at least one `"/api/` entry. */
function inspectRouteTable() {
  if (!existsSync(routesFile)) return { state: "absent" }
  const text = readFileSync(routesFile, "utf8")
  const apiRefs = (text.match(/"\/api\//g) || []).length
  const footers = (text.match(/export type \{ AppRoutes/g) || []).length
  const lines = text.split("\n").length
  return {
    state: apiRefs > 0 && footers === 1 ? "healthy" : "damaged",
    apiRefs,
    footers,
    lines,
  }
}

function report(label, info) {
  if (info.state === "absent") {
    log(`${label}: routes.d.ts absent (dev server has not generated it yet)`)
    return
  }
  const verdict =
    info.state === "healthy"
      ? "healthy"
      : `DAMAGED (${info.apiRefs === 0 ? "no /api/* handlers" : `${info.apiRefs} /api refs`}, ${info.footers} footers)`
  log(`${label}: ${info.lines} lines, ${info.apiRefs} /api refs, ${info.footers} footers -> ${verdict}`)
}

/** Stray `next dev` processes for THIS project only — never anyone else's. */
function killStrayDevServers() {
  const marker = "poultrycore-main"
  try {
    if (isWindows) {
      // Written to a temp .ps1 and run with -File rather than passed inline to
      // -Command. The inline form needs the double quotes inside the CIM filter
      // escaped through both cmd and PowerShell, which silently failed and left
      // the stray processes alive while still reporting a delete.
      const ps = `
$ErrorActionPreference = 'SilentlyContinue'
$marker = '${marker}'
$t = Get-CimInstance Win32_Process -Filter "Name='node.exe' OR Name='cmd.exe'" |
  Where-Object {
    $_.CommandLine -and $_.CommandLine -like "*$marker*" -and
    ($_.CommandLine -like '*next*dev*' -or $_.CommandLine -like '*run dev*')
  }
if ($t) {
  foreach ($x in $t) {
    Write-Output ('killed pid ' + $x.ProcessId)
    Stop-Process -Id $x.ProcessId -Force
  }
} else {
  Write-Output 'no stray dev servers'
}
# An orphan can outlive its parents and keep port 3000, which makes the next
# dev server quietly bind 3001 while the browser keeps hitting the orphan.
Start-Sleep -Milliseconds 800
$held = (Get-NetTCPConnection -LocalPort 3000 -State Listen).OwningProcess
# NOT $pid — that is a read-only automatic variable in PowerShell and assigning
# to it aborts the script.
foreach ($procId in $held) {
  $c = (Get-CimInstance Win32_Process -Filter ('ProcessId=' + $procId)).CommandLine
  if ($c -and $c -like "*$marker*") {
    Write-Output ('freed port 3000 from orphan pid ' + $procId)
    Stop-Process -Id $procId -Force
  }
}
`
      const tmp = join(tmpdir(), `dev-reset-${process.pid}.ps1`)
      writeFileSync(tmp, ps, "utf8")
      try {
        const out = execSync(
          `powershell -NoProfile -NonInteractive -ExecutionPolicy Bypass -File "${tmp}"`,
          { encoding: "utf8", stdio: ["ignore", "pipe", "pipe"] },
        )
        out.split("\n").map(l => l.trim()).filter(Boolean).forEach(l => log(`  ${l}`))
      } finally {
        rmSync(tmp, { force: true })
      }
    } else {
      execSync(`pkill -f "${marker}.*next.*dev" || true`, { stdio: "ignore" })
      log("  sent pkill for stray dev servers")
    }
  } catch (e) {
    log(`  (could not enumerate processes: ${e.message.split("\n")[0]})`)
    log("  if the delete below fails, stop the dev server by hand and re-run")
  }
}

log("")
log("dev-reset — Turbopack dev route table")
log("".padEnd(52, "-"))
report("before", inspectRouteTable())

if (checkOnly) {
  log("")
  log("--check: nothing was changed.")
  process.exit(inspectRouteTable().state === "damaged" ? 1 : 0)
}

log("")
log("stopping stray dev servers for this project...")
killStrayDevServers()

log("")
if (existsSync(devDir)) {
  // Must happen AFTER the kill: a live dev server holds locks under .next/dev
  // and the removal silently leaves files behind.
  rmSync(devDir, { recursive: true, force: true, maxRetries: 5, retryDelay: 300 })
  log(existsSync(devDir) ? "WARNING: .next/dev not fully removed — is a dev server still running?" : "deleted .next/dev")
} else {
  log(".next/dev already absent")
}
log("(left .next/ alone — the production build output and Docker's standalone dir live there)")

if (noStart) {
  log("")
  log("--no-start: run `npm run dev` when you are ready.")
  process.exit(0)
}

log("")
log("starting `next dev`...")
log("")
const child = spawn(isWindows ? "npm.cmd" : "npm", ["run", "dev"], {
  cwd: root,
  stdio: "inherit",
  shell: isWindows,
})
child.on("exit", code => process.exit(code ?? 0))

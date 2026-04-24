/**
 * Runs before `next build` (npm prebuild). Writes public/deploy-stamp.txt so you can
 * verify Cloud Run is serving the image you just built (open /deploy-stamp.txt or see Support page).
 */
import { mkdirSync, writeFileSync } from "fs"
import { dirname, join } from "path"
import { fileURLToPath } from "url"

const root = join(dirname(fileURLToPath(import.meta.url)), "..")
const dir = join(root, "public")
mkdirSync(dir, { recursive: true })
const stamp = new Date().toISOString()
writeFileSync(join(dir, "deploy-stamp.txt"), `${stamp}\n`, "utf8")
console.log("[stamp-deploy]", stamp)

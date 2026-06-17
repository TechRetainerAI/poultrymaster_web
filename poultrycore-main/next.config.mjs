import { fileURLToPath } from 'node:url'
import { dirname } from 'node:path'

/** @type {import('next').NextConfig} */
// Vercel runs its own output pipeline; standalone is for Docker (Render, etc.).
const isVercel = Boolean(process.env.VERCEL)

// Pin the workspace root to THIS folder. Next infers the root by walking up for
// a lockfile; a stray lockfile in a parent dir (e.g. an empty package-lock.json
// one level up in poultrymaster_web/) makes it pick the parent, where there's no
// node_modules — which breaks module resolution ("Can't resolve 'tailwindcss'")
// and can spiral into an OOM during file tracing. Pinning prevents that.
// See DEV_SETUP_AND_KNOWN_ISSUES.md (Issue 1).
const projectRoot = dirname(fileURLToPath(import.meta.url))

const nextConfig = {
  ...(!isVercel ? { output: 'standalone' } : {}),
  outputFileTracingRoot: projectRoot,
  turbopack: {
    root: projectRoot,
  },
  typescript: {
    ignoreBuildErrors: true,
  },
  images: {
    unoptimized: true,
  },
  // Note: The ngrok cross-origin warning is harmless and can be ignored.
  // CORS is properly handled by the backend API configuration.
  // If you want to suppress the warning for a specific ngrok URL, uncomment and add it:
  // allowedDevOrigins: ['https://your-ngrok-url.ngrok-free.dev'],
}

export default nextConfig

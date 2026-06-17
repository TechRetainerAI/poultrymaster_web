/** @type {import('next').NextConfig} */
// Vercel runs its own output pipeline; standalone is for Docker (Render, etc.).
const isVercel = Boolean(process.env.VERCEL)

const nextConfig = {
  ...(!isVercel ? { output: 'standalone' } : {}),
  // Pin the workspace root so Next doesn't infer it from the parent dir's
  // package-lock.json (there are multiple lockfiles in the tree).
  turbopack: {
    root: import.meta.dirname,
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

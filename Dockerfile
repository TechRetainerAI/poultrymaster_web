# Dockerfile for Next.js Frontend Application
# Multi-stage build for optimized production image

# Stage 1: Dependencies
FROM node:20-alpine AS deps
RUN apk add --no-cache libc6-compat
WORKDIR /app

# Copy package files
COPY package.json package-lock.json* ./
RUN npm ci

# Stage 2: Builder
FROM node:20-alpine AS builder
WORKDIR /app

# Copy dependencies from deps stage
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Set build-time environment variables (optional, can be overridden)
ENV NEXT_TELEMETRY_DISABLED=1
ENV NODE_ENV=production

# Next.js inlines NEXT_PUBLIC_* into the client bundle at build time.
# The two supported ways to supply them are:
#   1. A .env.production file in the build context (preferred for Cloud Run
#      `--source .` deploys — `gcloud builds submit` does NOT translate
#      `--build-env-vars-file` to docker `--build-arg`, so ARG-based wiring
#      below silently bakes empty strings if you only set runtime env vars).
#   2. docker build --build-arg NEXT_PUBLIC_*=... (for manual builds).
# Without either, the client bundle falls back to DEFAULT_LOGIN_API_HOST /
# DEFAULT_FARM_API_HOST (the PRODUCTION hosts) — dangerous for dev/staging.
ARG NEXT_PUBLIC_API_BASE_URL
ARG NEXT_PUBLIC_ADMIN_API_URL
ARG NEXT_PUBLIC_LOGIN_API_URL
# Only export ARG values as ENV when they are non-empty, otherwise an empty
# ENV would clobber whatever .env.production provides.
RUN if [ -n "$NEXT_PUBLIC_API_BASE_URL"   ]; then printf 'NEXT_PUBLIC_API_BASE_URL=%s\n'   "$NEXT_PUBLIC_API_BASE_URL"   >> .env.production; fi && \
    if [ -n "$NEXT_PUBLIC_ADMIN_API_URL"  ]; then printf 'NEXT_PUBLIC_ADMIN_API_URL=%s\n'  "$NEXT_PUBLIC_ADMIN_API_URL"  >> .env.production; fi && \
    if [ -n "$NEXT_PUBLIC_LOGIN_API_URL"  ]; then printf 'NEXT_PUBLIC_LOGIN_API_URL=%s\n'  "$NEXT_PUBLIC_LOGIN_API_URL"  >> .env.production; fi && \
    echo "--- .env.production used for this build ---" && \
    cat .env.production 2>/dev/null || echo "(none — using DEFAULT_*_HOST fallbacks; OK only for production)"

# Build the application
RUN npm run build

# Stage 3: Runner
FROM node:20-alpine AS runner
WORKDIR /app

ENV NODE_ENV=production
ENV NEXT_TELEMETRY_DISABLED=1

# Create a non-root user
RUN addgroup --system --gid 1001 nodejs
RUN adduser --system --uid 1001 nextjs

# Copy necessary files from builder
COPY --from=builder /app/public ./public
COPY --from=builder /app/.next/standalone ./
COPY --from=builder /app/.next/static ./.next/static

# Set correct permissions
RUN chown -R nextjs:nodejs /app

USER nextjs

# Listen on process.env.PORT (Cloud Run, Render, etc. inject this). Next standalone defaults to 3000 if PORT is unset.
# Cloud Run: use container port 8080 (gcloud default) — not 300 (typo). Example:
#   gcloud run deploy poultrymaster-web --source . --region europe-west1 --port 8080 --allow-unauthenticated
EXPOSE 8080

ENV HOSTNAME="0.0.0.0"

# Use the standalone server from Next.js
CMD ["node", "server.js"]


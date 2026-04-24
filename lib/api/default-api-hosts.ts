/**
 * Defaults when env vars are unset (local dev without .env.local).
 * Override with NEXT_PUBLIC_ADMIN_API_URL, ADMIN_API_URL, NEXT_PUBLIC_API_BASE_URL, FARM_API_URL.
 * Custom domains (e.g. usermanagementapi.techretainer.com) take precedence only when set in env.
 */
export const DEFAULT_LOGIN_API_HOST =
  "poultrymaster-api-git-1024831506678.europe-west1.run.app"
export const DEFAULT_FARM_API_HOST =
  "poultrymaster-farm-api-git-1024831506678.europe-west1.run.app"

export const DEFAULT_LOGIN_API_ORIGIN = `https://${DEFAULT_LOGIN_API_HOST}`
export const DEFAULT_FARM_API_ORIGIN = `https://${DEFAULT_FARM_API_HOST}`

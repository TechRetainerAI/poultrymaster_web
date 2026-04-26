/** Roles allowed to use the developer registry site (platform — not farm staff). */
export const PLATFORM_DIRECTORY_ROLES = ["SystemAdmin", "PlatformOwner"] as const

export function hasPlatformDirectoryAccess(roles: string[]): boolean {
  const set = new Set(roles.map((r) => r.trim()))
  return PLATFORM_DIRECTORY_ROLES.some((r) => set.has(r))
}

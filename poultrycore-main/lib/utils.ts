import { clsx, type ClassValue } from 'clsx'
import { twMerge } from 'tailwind-merge'

export function cn(...inputs: ClassValue[]) {
  return twMerge(clsx(inputs))
}

/** Mobile-friendly short date format */
export function formatDateShort(d: string | Date): string {
  const dt = typeof d === 'string' ? new Date(d) : d
  return dt.toLocaleDateString('en-US', { month: 'short', day: 'numeric', year: '2-digit' })
}

/** Shared main content class for mobile layout (bottom nav clearance) */
export const mainMobileClass = 'flex-1 overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0'

"use client"

import Link from "next/link"
import { Lock } from "lucide-react"
import { Button } from "@/components/ui/button"

/**
 * Shown instead of a page the person may not open. Rendered BEFORE the page
 * mounts, so none of its data is ever requested or displayed.
 */
export function AccessRestricted({ homeHref = "/dashboard" }: { homeHref?: string }) {
  return (
    <div className="flex min-h-[60vh] items-center justify-center p-6">
      <div className="max-w-md rounded-xl border bg-card p-8 text-center shadow-sm">
        <div className="mx-auto mb-4 flex h-12 w-12 items-center justify-center rounded-full bg-muted">
          <Lock className="h-6 w-6 text-muted-foreground" aria-hidden />
        </div>
        <h1 className="text-lg font-semibold">Access Restricted</h1>
        <p className="mt-2 text-sm text-muted-foreground">
          You don&apos;t have permission to access this page. Please contact your company administrator if you need access.
        </p>
        <Button asChild className="mt-6">
          <Link href={homeHref}>Back to dashboard</Link>
        </Button>
      </div>
    </div>
  )
}

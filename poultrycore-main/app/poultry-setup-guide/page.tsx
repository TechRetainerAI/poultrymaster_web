"use client"

import { SupportPageShell } from "@/components/support/support-page-shell"
import { SetupGuideView } from "@/components/support/setup-guide-view"

// Poultry-only through the "/poultry-" prefix in CompanyTypeGuard.
export default function SetupGuidePage() {
  return <SupportPageShell><SetupGuideView /></SupportPageShell>
}

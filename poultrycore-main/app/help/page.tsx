"use client"

import { SupportPageShell } from "@/components/support/support-page-shell"
import { HelpCenterView } from "@/components/support/help-center-view"
import { usePoultryHelpRedirect } from "@/components/support/use-poultry-help-redirect"

export default function HelpPage() {
  usePoultryHelpRedirect()
  return <SupportPageShell><HelpCenterView /></SupportPageShell>
}

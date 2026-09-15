"use client"

// Loads the active farm's egg-pick settings (six times + the enable switches
// for the 4th, 5th and 6th) for the production entry forms. Falls back to
// defaults while loading / on error.
import { useEffect, useState } from "react"
import {
  DEFAULT_PICK_SETTINGS,
  getFarmProductionSettings,
  pickLabels,
  type FarmProductionSettings,
} from "@/lib/api/farm-production-settings"

export function usePickSettings() {
  const [settings, setSettings] = useState<FarmProductionSettings>(DEFAULT_PICK_SETTINGS)

  useEffect(() => {
    let cancelled = false
    getFarmProductionSettings()
      .then((s) => { if (!cancelled) setSettings(s) })
      .catch(() => { /* keep defaults */ })
    return () => { cancelled = true }
  }, [])

  return {
    settings,
    labels: pickLabels(settings),
    enableFourthPick: settings.enableFourthPick,
    enableFifthPick: settings.enableFifthPick,
    enableSixthPick: settings.enableSixthPick,
  }
}

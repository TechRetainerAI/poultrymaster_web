import { create } from 'zustand'

export type AlertItem = { id: string; title: string; description?: string; time?: string }

type AlertsState = {
  isOpen: boolean
  alerts: AlertItem[]
  open: () => void
  close: () => void
  setAlerts: (items: AlertItem[]) => void
}

export const useAlertsStore = create<AlertsState>((set) => ({
  isOpen: false,
  alerts: [], // No hardcoded alerts - only real alerts from the system
  open: () => set({ isOpen: true }),
  close: () => set({ isOpen: false }),
  setAlerts: (items) => set({ alerts: items }),
}))



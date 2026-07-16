import { buildApiUrl, getAuthHeaders, getUserContext } from './config'

// Per-farm egg-pick configuration (migration 153). Times are 24h "HH:mm" strings.
export interface FarmProductionSettings {
  farmId: string
  firstPickTime: string
  secondPickTime: string
  thirdPickTime: string
  fourthPickTime: string
  enableFourthPick: boolean
}

export const DEFAULT_PICK_SETTINGS: FarmProductionSettings = {
  farmId: '',
  firstPickTime: '09:00',
  secondPickTime: '12:00',
  thirdPickTime: '16:00',
  fourthPickTime: '18:00',
  enableFourthPick: false,
}

function mapSettings(raw: any, farmId: string): FarmProductionSettings {
  if (!raw) return { ...DEFAULT_PICK_SETTINGS, farmId }
  return {
    farmId: raw.farmId ?? raw.FarmId ?? farmId,
    firstPickTime: raw.firstPickTime ?? raw.FirstPickTime ?? DEFAULT_PICK_SETTINGS.firstPickTime,
    secondPickTime: raw.secondPickTime ?? raw.SecondPickTime ?? DEFAULT_PICK_SETTINGS.secondPickTime,
    thirdPickTime: raw.thirdPickTime ?? raw.ThirdPickTime ?? DEFAULT_PICK_SETTINGS.thirdPickTime,
    fourthPickTime: raw.fourthPickTime ?? raw.FourthPickTime ?? DEFAULT_PICK_SETTINGS.fourthPickTime,
    enableFourthPick: Boolean(raw.enableFourthPick ?? raw.EnableFourthPick ?? false),
  }
}

export async function getFarmProductionSettings(farmId?: string): Promise<FarmProductionSettings> {
  const ctx = getUserContext()
  const fid = farmId || ctx.farmId || ''
  if (!fid) return { ...DEFAULT_PICK_SETTINGS }
  try {
    const url = `${buildApiUrl('/FarmProductionSettings')}?farmId=${encodeURIComponent(fid)}`
    const res = await fetch(url, { headers: getAuthHeaders() })
    if (!res.ok) return { ...DEFAULT_PICK_SETTINGS, farmId: fid }
    const data = await res.json()
    return mapSettings(data, fid)
  } catch {
    return { ...DEFAULT_PICK_SETTINGS, farmId: fid }
  }
}

export async function saveFarmProductionSettings(
  input: FarmProductionSettings,
): Promise<{ success: boolean; message?: string; data?: FarmProductionSettings }> {
  const ctx = getUserContext()
  const farmId = input.farmId || ctx.farmId || ''
  if (!farmId) return { success: false, message: 'No active farm. Please sign in again.' }
  try {
    const payload = {
      FarmId: farmId,
      FirstPickTime: input.firstPickTime || null,
      SecondPickTime: input.secondPickTime || null,
      ThirdPickTime: input.thirdPickTime || null,
      FourthPickTime: input.fourthPickTime || null,
      EnableFourthPick: input.enableFourthPick,
      UpdatedBy: ctx.userId || null,
    }
    const res = await fetch(buildApiUrl('/FarmProductionSettings'), {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify(payload),
    })
    if (!res.ok) {
      const t = await res.text().catch(() => '')
      return { success: false, message: t || `Save failed (${res.status})` }
    }
    const data = await res.json().catch(() => null)
    return { success: true, data: data ? mapSettings(data, farmId) : undefined }
  } catch (e: any) {
    return { success: false, message: e?.message || 'Network error' }
  }
}

/** "09:00" -> "9:00 AM"; blank/invalid -> "". */
export function formatPickTime(hhmm?: string | null): string {
  if (!hhmm) return ''
  const m = /^(\d{1,2}):(\d{2})/.exec(hhmm.trim())
  if (!m) return hhmm
  let h = parseInt(m[1], 10)
  const min = m[2]
  const ampm = h >= 12 ? 'PM' : 'AM'
  h = h % 12
  if (h === 0) h = 12
  return `${h}:${min} ${ampm}`
}

/** Pick labels with the configured time in parentheses, e.g. "1st Pick (9:00 AM)". */
export function pickLabels(s: FarmProductionSettings) {
  const suffix = (v?: string | null) => {
    const f = formatPickTime(v)
    return f ? ` (${f})` : ''
  }
  return {
    first: `1st Pick${suffix(s.firstPickTime)}`,
    second: `2nd Pick${suffix(s.secondPickTime)}`,
    third: `3rd Pick${suffix(s.thirdPickTime)}`,
    fourth: `4th Pick${suffix(s.fourthPickTime)}`,
  }
}

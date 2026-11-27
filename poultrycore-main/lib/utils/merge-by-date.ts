// 508: slot display-only rows (a reversed batch's flocks or expense lines) into
// a list that is already newest-first, by date -- the list's own order is kept.

export function mergeNewestFirst<T, R>(rows: T[], extra: R[], dateOf: (x: T | R) => string | null | undefined): (T | R)[] {
  if (extra.length === 0) return rows
  const t = (x: T | R) => {
    const v = dateOf(x)
    const n = v ? new Date(v).getTime() : NaN
    return Number.isFinite(n) ? n : -Infinity
  }
  const out: (T | R)[] = [...rows]
  for (const e of [...extra].sort((a, b) => t(b) - t(a))) {
    const at = out.findIndex((x) => t(x) < t(e))
    if (at === -1) out.push(e)
    else out.splice(at, 0, e)
  }
  return out
}

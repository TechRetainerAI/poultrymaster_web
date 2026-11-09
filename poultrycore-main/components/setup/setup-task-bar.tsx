"use client"

// The Farm Setup task bar: one row of buttons that changes with the open tab.
//
// A view describes its buttons as data (SetupTask[]) instead of laying them
// out itself, so every tab's buttons look and behave the same:
//   * the primary task is filled, the rest are outlined;
//   * tasks with a different `group` get a divider between them;
//   * whatever does not fit the width moves into a "More" menu (and comes
//     back when there is room), so the bar never wraps or overflows;
//   * `more: true` tasks always live in the menu.

import { Fragment, useLayoutEffect, useRef, useState, type ComponentType } from "react"
import Link from "next/link"
import { MoreHorizontal } from "lucide-react"
import { Button } from "@/components/ui/button"
import {
  DropdownMenu, DropdownMenuContent, DropdownMenuItem, DropdownMenuSeparator, DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu"
import { cn } from "@/lib/utils"

export type SetupTask = {
  /** Stable within the view. */
  id: string
  label: string
  icon?: ComponentType<{ className?: string }>
  onClick?: () => void
  /** A link instead of a click handler. */
  href?: string
  /** The tab's main task: filled button, kept on the bar longest. */
  primary?: boolean
  disabled?: boolean
  /** Left out entirely (e.g. no permission). */
  hidden?: boolean
  /** Tooltip, e.g. why it is disabled. */
  title?: string
  /** Always in the More menu. */
  more?: boolean
  /** A divider separates tasks of different groups. */
  group?: string
}

const GAP = 8

/** light: on a white page (standalone). dark: on Farm Setup's coloured dock. */
export type TaskBarTone = "light" | "dark"

const SECONDARY: Record<TaskBarTone, string> = {
  light: "bg-white",
  dark: "border-white/20 bg-white/10 text-white hover:bg-white/20 hover:text-white disabled:text-white/50",
}
const PRIMARY: Record<TaskBarTone, string> = {
  light: "bg-blue-600 text-white hover:bg-blue-700",
  dark: "bg-orange-500 text-white shadow-sm hover:bg-orange-600",
}

function TaskButton({ task, tabIndex, tone = "light" }: { task: SetupTask; tabIndex?: number; tone?: TaskBarTone }) {
  const Icon = task.icon
  const inner = <>{Icon && <Icon className="h-4 w-4" />}{task.label}</>
  const cls = cn("h-9 shrink-0 gap-1.5 whitespace-nowrap px-3",
    task.primary ? PRIMARY[tone] : SECONDARY[tone])
  const variant = task.primary ? "default" : "outline"
  if (task.href && !task.disabled) {
    return (
      <Button asChild variant={variant} className={cls} title={task.title} tabIndex={tabIndex}>
        <Link href={task.href}>{inner}</Link>
      </Button>
    )
  }
  return (
    <Button type="button" variant={variant} className={cls} onClick={task.onClick}
      disabled={task.disabled} title={task.title} tabIndex={tabIndex}>
      {inner}
    </Button>
  )
}

function Divider({ tone = "light" }: { tone?: TaskBarTone }) {
  return <span aria-hidden className={cn("h-6 w-px shrink-0", tone === "dark" ? "bg-white/20" : "bg-slate-200")} />
}

/** The buttons of one task bar, folding into "More" when the row is too narrow. */
export function TaskBarRow({ tasks, className, align = "start", tone = "light" }: {
  tasks: SetupTask[]; className?: string; align?: "start" | "end"; tone?: TaskBarTone
}) {
  const live = tasks.filter((t) => !t.hidden)
  const inline = live.filter((t) => !t.more)
  const pinnedMore = live.filter((t) => t.more)

  const wrapRef = useRef<HTMLDivElement>(null)
  const measureRef = useRef<HTMLDivElement>(null)
  const [fit, setFit] = useState(inline.length)

  // Re-measure when the set of buttons changes (label, count, divider).
  const shape = inline.map((t) => `${t.id}:${t.label}:${t.group ?? ""}:${t.primary ? 1 : 0}`).join("|") + `#${pinnedMore.length}`

  useLayoutEffect(() => {
    const wrap = wrapRef.current
    const meas = measureRef.current
    if (!wrap || !meas) return
    const measure = () => {
      const kids = Array.from(meas.children) as HTMLElement[]
      const moreW = kids[kids.length - 1]?.offsetWidth ?? 36
      const widths = kids.slice(0, -1).map((k) => k.offsetWidth)
      const avail = wrap.clientWidth
      const all = widths.reduce((a, w) => a + w, 0) + GAP * Math.max(0, widths.length - 1)
      const needMenu = pinnedMore.length > 0
      if (all + (needMenu ? GAP + moreW : 0) <= avail) { setFit(widths.length); return }
      // Primary first: it is the last to leave the bar.
      let used = moreW, n = 0
      for (const w of widths) {
        if (used + GAP + w > avail) break
        used += GAP + w; n++
      }
      setFit(Math.max(1, n))
    }
    measure()
    const ro = new ResizeObserver(measure)
    ro.observe(wrap)
    return () => ro.disconnect()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shape])

  // Primary tasks go first, so a narrow bar keeps the main button.
  const ordered = [...inline.filter((t) => t.primary), ...inline.filter((t) => !t.primary)]
  const shown = ordered.slice(0, fit)
  const folded = [...ordered.slice(fit), ...pinnedMore]
  const withDivider = (list: SetupTask[], i: number) => i > 0 && (list[i].group ?? "") !== (list[i - 1].group ?? "")

  return (
    <div ref={wrapRef} className={cn("relative min-w-0", className)}>
      {/* Off-screen copy used only to measure each button's width. */}
      <div ref={measureRef} aria-hidden className="pointer-events-none invisible absolute left-0 top-0 flex w-max gap-2">
        {ordered.map((t, i) => (
          <span key={t.id} className="flex items-center gap-2">
            {withDivider(ordered, i) && <Divider tone={tone} />}
            <TaskButton task={t} tabIndex={-1} tone={tone} />
          </span>
        ))}
        <span><Button variant="outline" size="icon" className="h-9 w-9" tabIndex={-1}><MoreHorizontal /></Button></span>
      </div>

      <div className={cn("flex items-center gap-2", align === "end" && "justify-end")}>
        {shown.map((t, i) => (
          <Fragment key={t.id}>
            {withDivider(shown, i) && <Divider tone={tone} />}
            <TaskButton task={t} tone={tone} />
          </Fragment>
        ))}
        {folded.length > 0 && (
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button variant="outline" size="icon" className={cn("h-9 w-9 shrink-0", SECONDARY[tone])} aria-label="More tasks" title="More tasks">
                <MoreHorizontal className="h-4 w-4" />
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align={align} className="min-w-52">
              {folded.map((t, i) => {
                const Icon = t.icon
                const body = <>{Icon && <Icon className="mr-2 h-4 w-4" />}{t.label}</>
                return (
                  <Fragment key={t.id}>
                    {withDivider(folded, i) && <DropdownMenuSeparator />}
                    {t.href && !t.disabled ? (
                      <DropdownMenuItem asChild><Link href={t.href}>{body}</Link></DropdownMenuItem>
                    ) : (
                      <DropdownMenuItem disabled={t.disabled} onSelect={() => t.onClick?.()} title={t.title}>{body}</DropdownMenuItem>
                    )}
                  </Fragment>
                )
              })}
            </DropdownMenuContent>
          </DropdownMenu>
        )}
      </div>
    </div>
  )
}

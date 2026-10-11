// Page-level tab bar, as on Raw Materials & Supplies: a white bar, a solid blue
// active tab and a count pill that inverts on the active tab.
//   <TabsList className={tabListCls}>
//     <TabsTrigger className={tabTriggerCls}><Icon className="h-4 w-4" /> Name <span className={tabCountCls}>3</span></TabsTrigger>

export const tabListCls =
  "h-auto w-full max-w-full justify-start gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm sm:w-fit"

export const tabTriggerCls =
  "group h-auto flex-none shrink-0 gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 sm:px-4 " +
  "transition-all hover:bg-slate-100 hover:text-slate-900 " +
  "data-[state=active]:bg-blue-600 data-[state=active]:text-white data-[state=active]:shadow-md " +
  "data-[state=active]:shadow-blue-600/25 data-[state=active]:hover:bg-blue-600 data-[state=active]:hover:text-white"

export const tabCountCls =
  "ml-0.5 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold tabular-nums text-slate-600 " +
  "group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white"

// Filter that sits on the tab row, right-aligned: a smaller pill group so all
// options are visible at once (lighter than the tabs, so the two don't compete).
//   <div className={filterGroupCls}><span className={filterLabelCls}>Show</span>
//     <button className={filterPillCls(active)}>…</button></div>
export const filterGroupCls =
  "flex max-w-full items-center gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm"
export const filterLabelCls = "shrink-0 pl-2 pr-1 text-xs font-semibold uppercase tracking-wide text-slate-500"
export const filterPillCls = (active: boolean) =>
  "shrink-0 rounded-lg px-3 py-1.5 text-sm font-medium transition-colors " +
  (active ? "bg-blue-50 text-blue-700 ring-1 ring-inset ring-blue-300" : "text-slate-600 hover:bg-slate-100 hover:text-slate-900")

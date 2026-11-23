'use client'

import * as React from 'react'
import * as TabsPrimitive from '@radix-ui/react-tabs'

import { cn } from '@/lib/utils'

function Tabs({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Root>) {
  return (
    <TabsPrimitive.Root
      data-slot="tabs"
      className={cn('flex flex-col gap-2', className)}
      {...props}
    />
  )
}

function TabsList({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.List>) {
  return (
    <TabsPrimitive.List
      data-slot="tabs-list"
      className={cn(
        'bg-muted text-muted-foreground inline-flex h-9 w-fit items-center justify-center rounded-lg p-[3px]',
        className,
      )}
      {...props}
    />
  )
}

function TabsTrigger({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Trigger>) {
  return (
    <TabsPrimitive.Trigger
      data-slot="tabs-trigger"
      className={cn(
        "data-[state=active]:bg-background dark:data-[state=active]:text-foreground focus-visible:border-ring focus-visible:ring-ring/50 focus-visible:outline-ring dark:data-[state=active]:border-input dark:data-[state=active]:bg-input/30 text-foreground dark:text-muted-foreground inline-flex h-[calc(100%-1px)] flex-1 items-center justify-center gap-1.5 rounded-md border border-transparent px-2 py-1 text-sm font-medium whitespace-nowrap transition-[color,box-shadow] focus-visible:ring-[3px] focus-visible:outline-1 disabled:pointer-events-none disabled:opacity-50 data-[state=active]:shadow-sm [&_svg]:pointer-events-none [&_svg]:shrink-0 [&_svg:not([class*='size-'])]:size-4",
        className,
      )}
      {...props}
    />
  )
}

// A tab strip people can actually see: white bar with a border, solid blue
// active tab, count pills. Started on Poultry Supply Purchases; shared by the
// inventory pages so they all look the same. Opt in per page -- the default
// grey strip above stays the default everywhere else.
//   <TabsList className={PROMINENT_TABS_LIST}>
//     <TabsTrigger className={PROMINENT_TABS_TRIGGER}>Items <span className={PROMINENT_TABS_COUNT}>3</span></TabsTrigger>
export const PROMINENT_TABS_LIST =
  'h-auto w-full max-w-full justify-start gap-1 overflow-x-auto rounded-xl border border-slate-200 bg-white p-1 shadow-sm sm:w-fit'
export const PROMINENT_TABS_TRIGGER =
  'group h-auto flex-none shrink-0 gap-1.5 rounded-lg px-3 py-2 text-sm font-semibold text-slate-600 sm:px-4 ' +
  'transition-all hover:bg-slate-100 hover:text-slate-900 ' +
  'data-[state=active]:bg-blue-600 data-[state=active]:text-white data-[state=active]:shadow-md ' +
  'data-[state=active]:shadow-blue-600/25 data-[state=active]:hover:bg-blue-600 data-[state=active]:hover:text-white'
// Count pill inside a trigger -- inverted on the active (blue) tab.
export const PROMINENT_TABS_COUNT =
  'ml-0.5 rounded-full bg-slate-100 px-1.5 py-0.5 text-[11px] font-bold tabular-nums text-slate-600 ' +
  'group-data-[state=active]:bg-white/20 group-data-[state=active]:text-white'

function TabsContent({
  className,
  ...props
}: React.ComponentProps<typeof TabsPrimitive.Content>) {
  return (
    <TabsPrimitive.Content
      data-slot="tabs-content"
      className={cn('flex-1 outline-none', className)}
      {...props}
    />
  )
}

export { Tabs, TabsList, TabsTrigger, TabsContent }

"use client"

import { ChevronRight } from "lucide-react"
import { cn } from "@/lib/utils"

interface InfoRowProps {
  label: string
  value: string | React.ReactNode
  icon?: React.ReactNode
}

export function InfoRow({ label, value, icon }: InfoRowProps) {
  return (
    <div className="flex items-center justify-between py-3 border-b border-slate-100 last:border-0">
      <div className="flex items-center gap-3 text-slate-600 text-sm">
        {icon && <span className="text-slate-400">{icon}</span>}
        {label}
      </div>
      <div className="text-slate-900 font-medium text-sm text-right">
        {value || <span className="text-slate-400">Not set</span>}
      </div>
    </div>
  )
}

interface InfoSectionProps {
  title: string
  children: React.ReactNode
  onClick?: () => void
  className?: string
  collapsible?: boolean
}

export function InfoSection({ title, children, onClick, className, collapsible = true }: InfoSectionProps) {
  return (
    <div 
      className={cn(
        "bg-white rounded-lg border border-slate-200",
        onClick && "cursor-pointer hover:bg-slate-50 transition-colors",
        className
      )}
      onClick={onClick}
    >
      <div className="flex items-center justify-between px-6 py-4 border-b border-slate-100">
        <h3 className="text-base font-semibold text-slate-900">{title}</h3>
        {collapsible && (
          <ChevronRight className="w-5 h-5 text-slate-400" />
        )}
      </div>
      <div className="px-6 py-2">
        {children}
      </div>
    </div>
  )
}

interface PageHeaderProps {
  title: string
  subtitle: string
  icon?: React.ReactNode
  action?: React.ReactNode
}

export function PageHeader({ title, subtitle, icon, action }: PageHeaderProps) {
  return (
    <div className="mb-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-semibold text-slate-900 tracking-tight">{title}</h1>
          <p className="text-sm text-slate-500 mt-1">{subtitle}</p>
        </div>
        {action && <div>{action}</div>}
      </div>
    </div>
  )
}

interface StatusBadgeProps {
  status: "active" | "pending" | "inactive" | "verified" | "unverified"
  label?: string
}

export function StatusBadge({ status, label }: StatusBadgeProps) {
  const styles = {
    active: "bg-emerald-50 text-emerald-700 border-emerald-200",
    verified: "bg-emerald-50 text-emerald-700 border-emerald-200",
    pending: "bg-amber-50 text-amber-700 border-amber-200",
    inactive: "bg-slate-50 text-slate-600 border-slate-200",
    unverified: "bg-slate-50 text-slate-600 border-slate-200",
  }

  const defaultLabels = {
    active: "Active",
    verified: "Verified",
    pending: "Pending",
    inactive: "Inactive",
    unverified: "Not Verified",
  }

  return (
    <span className={cn(
      "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium border",
      styles[status]
    )}>
      <span className={cn(
        "w-1.5 h-1.5 rounded-full mr-1.5",
        status === "active" || status === "verified" ? "bg-emerald-500" :
        status === "pending" ? "bg-amber-500" : "bg-slate-400"
      )} />
      {label || defaultLabels[status]}
    </span>
  )
}


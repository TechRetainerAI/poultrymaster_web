import { type LucideIcon } from "lucide-react"
import { type ReactNode } from "react"

interface PageHeaderProps {
  icon: LucideIcon
  title: string
  subtitle?: string
  children?: ReactNode
}

export function PageHeader({ icon: Icon, title, subtitle, children }: PageHeaderProps) {
  return (
    <div className="flex items-center justify-between flex-wrap gap-3">
      <div className="flex items-center gap-3">
        <div className="bg-rose-100 text-rose-600 rounded-lg p-2">
          <Icon className="h-6 w-6" />
        </div>
        <div>
          <h1 className="text-2xl font-bold">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
        </div>
      </div>
      {children && <div className="flex items-center gap-2">{children}</div>}
    </div>
  )
}

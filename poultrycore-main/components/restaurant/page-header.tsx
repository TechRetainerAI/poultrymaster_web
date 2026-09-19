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
    <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
      <div className="flex items-center gap-3 min-w-0">
        <div className="bg-rose-100 text-rose-600 rounded-lg p-2 flex-shrink-0">
          <Icon className="h-5 w-5 sm:h-6 sm:w-6" />
        </div>
        <div className="min-w-0">
          <h1 className="text-xl sm:text-2xl font-bold leading-tight">{title}</h1>
          {subtitle && <p className="text-sm text-muted-foreground">{subtitle}</p>}
        </div>
      </div>
      {/* Actions go full width on a phone rather than wrapping to an odd
          intrinsic width under the title. [&>*]:flex-1 makes a pair of
          buttons share the row instead of one stretching alone. */}
      {children && (
        <div className="flex items-center gap-2 w-full sm:w-auto flex-shrink-0 [&>*]:flex-1 sm:[&>*]:flex-none">
          {children}
        </div>
      )}
    </div>
  )
}

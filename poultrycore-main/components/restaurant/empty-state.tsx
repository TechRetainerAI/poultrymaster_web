import { Button } from "@/components/ui/button"
import { type LucideIcon } from "lucide-react"

interface EmptyStateProps {
  icon: LucideIcon
  title: string
  description?: string
  actionLabel?: string
  onAction?: () => void
}

export function EmptyState({ icon: Icon, title, description, actionLabel, onAction }: EmptyStateProps) {
  return (
    <div className="text-center py-16 border-2 border-dashed rounded-xl">
      <Icon className="h-12 w-12 mx-auto text-gray-300 mb-3" />
      <h3 className="text-lg font-semibold text-gray-500">{title}</h3>
      {description && <p className="text-sm text-gray-400 mt-1">{description}</p>}
      {actionLabel && onAction && (
        <Button onClick={onAction} className="mt-4 bg-rose-600 hover:bg-rose-700">
          {actionLabel}
        </Button>
      )}
    </div>
  )
}

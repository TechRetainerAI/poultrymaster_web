import { toast } from "@/hooks/use-toast"

/**
 * A save / approve / reverse the API refused for lack of permission
 * (IamEnforcementFilter answers 403 with code "forbidden"). Pages each word
 * their own failures ("Could not save") and many hide the reason, so the
 * refusal is announced once, in plain words, by the two places every request
 * passes: the fetch watcher in PageAccessGuard and the axios client. A 403 from
 * a business rule has no code "forbidden" and keeps the page's own message.
 */
const ACTION_WORDS: Record<string, string> = {
  create: "add records",
  edit: "change records",
  delete: "delete records",
  approve: "approve",
  reverse: "reverse records",
  export: "export",
}

let lastAt = 0

export function announceRefusal(body: unknown) {
  const b = body as { code?: unknown; message?: unknown; requiredPermission?: unknown } | null
  if (!b || b.code !== "forbidden") return
  const now = Date.now()
  if (now - lastAt < 1500) return // one toast for a burst of refused calls
  lastAt = now
  const action = typeof b.requiredPermission === "string" ? b.requiredPermission.split(".").pop() : undefined
  toast({
    variant: "destructive",
    title: "Not allowed",
    description: action && ACTION_WORDS[action]
      ? `You do not have permission to ${ACTION_WORDS[action]} on this page. Ask your company administrator if you need it.`
      : typeof b.message === "string" && b.message ? b.message : "You do not have permission to do this.",
  })
}

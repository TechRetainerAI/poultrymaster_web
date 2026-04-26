import { farmApiUrl, getAuthHeaders } from "./config"

export type ChatThread = {
  threadId: string
  farmId: string
  createdBy: string
  createdAt: string
  otherUserId?: string
  otherUserName?: string
  otherUserFirstName?: string
  otherUserLastName?: string
  lastMessagePreview?: string
  lastMessageAt?: string
  unreadCount?: number
}

export type ChatMessage = {
  messageId: string
  threadId: string
  userId: string
  content: string
  createdAt: string
  isRead: boolean
}

async function json<T>(res: Response): Promise<T> {
  if (!res.ok) {
    // Handle 401 gracefully - return empty array for lists
    if (res.status === 401) {
      console.warn("[Chat API] Unauthorized (401) - returning empty data")
      return [] as unknown as T
    }
    const text = await res.text()
    throw new Error(`API error: ${res.status} ${res.statusText}${text ? ` - ${text}` : ""}`)
  }
  const text = await res.text()
  if (!text || text.trim() === "") {
    // Return empty array for list endpoints, or null for single object
    return [] as unknown as T
  }
  try {
    return JSON.parse(text) as T
  } catch (e) {
    console.error("[Chat API] Failed to parse JSON:", text)
    throw new Error(`Invalid JSON response: ${e instanceof Error ? e.message : "Unknown error"}`)
  }
}

export async function createOrGetThread(farmId: string, userId: string, otherUserId: string): Promise<ChatThread> {
  const r = await fetch(farmApiUrl("Chat/threads"), {
    method: "POST",
    headers: { ...getAuthHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ farmId, userId, otherUserId })
  })
  return json<ChatThread>(r)
}

export async function getThreads(userId: string, farmId: string): Promise<ChatThread[]> {
  try {
    const r = await fetch(
      farmApiUrl(
        `Chat/threads?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
      ),
      {
        headers: getAuthHeaders(),
      }
    )
    return json<ChatThread[]>(r)
  } catch (err) {
    console.error("[Chat API] Error getting threads:", err)
    return [] // Return empty array on error
  }
}

export async function getMessages(threadId: string, take = 50, before?: string): Promise<ChatMessage[]> {
  try {
    const qs = new URLSearchParams({ take: String(take) })
    if (before) qs.set("before", before)
    const r = await fetch(farmApiUrl(`Chat/threads/${threadId}/messages?${qs.toString()}`), {
      headers: getAuthHeaders()
    })
    return json<ChatMessage[]>(r)
  } catch (err) {
    console.error("[Chat API] Error getting messages:", err)
    return [] // Return empty array on error
  }
}

export async function sendMessage(threadId: string, userId: string, content: string): Promise<ChatMessage> {
  const r = await fetch(farmApiUrl(`Chat/threads/${threadId}/messages`), {
    method: "POST",
    headers: { ...getAuthHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ userId, content })
  })
  
  if (!r.ok) {
    // Handle specific error cases
    if (r.status === 403) {
      const text = await r.text().catch(() => "")
      throw new Error(`Permission denied: You are not a participant in this thread. ${text}`)
    }
    if (r.status === 401) {
      throw new Error("Unauthorized: Please log in again.")
    }
    if (r.status === 400) {
      const text = await r.text().catch(() => "")
      throw new Error(`Invalid request: ${text || "Please check your message content."}`)
    }
  }
  
  return json<ChatMessage>(r)
}

export async function markRead(threadId: string, userId: string): Promise<void> {
  const r = await fetch(farmApiUrl(`Chat/threads/${threadId}/read`), {
    method: "POST",
    headers: { ...getAuthHeaders(), "Content-Type": "application/json" },
    body: JSON.stringify({ userId })
  })
  if (!r.ok && r.status !== 204) {
    const text = await r.text()
    throw new Error(`Mark read failed: ${r.status} ${text}`)
  }
}



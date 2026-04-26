"use client"

import { useEffect, useRef, useState } from "react"
import { HubConnectionBuilder, LogLevel } from "@microsoft/signalr"
import { createOrGetThread, getMessages, getThreads, sendMessage, markRead, type ChatThread, type ChatMessage } from "@/lib/api/chat"
import { getEmployees, type Employee } from "@/lib/api/admin"
import { getUserContext } from "@/lib/utils/user-context"
import { usePermissions } from "@/hooks/use-permissions"
import { Button } from "@/components/ui/button"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { ScrollArea } from "@/components/ui/scroll-area"
import { Avatar, AvatarFallback } from "@/components/ui/avatar"
import { Badge } from "@/components/ui/badge"
import { MessageCircle, X, Send, Users } from "lucide-react"
import { API_BASE_URL } from "@/lib/api/config"
import { useChatStore } from "@/lib/store/chat-store"
import { toast } from "sonner"

export function FloatingChatWidget() {
  const [mounted, setMounted] = useState(false)
  const { userId, farmId } = getUserContext()
  const { isStaff } = usePermissions()
  const setUnread = useChatStore((s) => s.setUnread)
  const incUnread = useChatStore((s) => s.incUnread)
  const [isOpen, setIsOpen] = useState(false)
  const isGlobalOpen = useChatStore((s) => s.isOpen)
  const openThreadId = useChatStore((s) => s.openThreadId)
  const closeGlobal = useChatStore((s) => s.closeChat)
  const [showUserList, setShowUserList] = useState(true)
  const [chatableUsers, setChatableUsers] = useState<Employee[]>([])
  const [threads, setThreads] = useState<ChatThread[]>([])
  const [activeThread, setActiveThread] = useState<ChatThread | null>(null)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [messageText, setMessageText] = useState("")
  const [isTyping, setIsTyping] = useState(false)
  const [loading, setLoading] = useState(false)
  const connRef = useRef<any>(null)
  const messagesEndRef = useRef<HTMLDivElement>(null)
  const openThreadRef = useRef<((thread: ChatThread) => Promise<void>) | undefined>(undefined)

  // Only render on client to prevent hydration errors
  useEffect(() => {
    setMounted(true)
  }, [])

  // Load chatable users (staff see admins, admins see staff)
  useEffect(() => {
    if (!isOpen || !farmId) return
    // Wait for threads to load first, then load chatable users
    if (threads.length > 0 || !isStaff) {
      loadChatableUsers()
    }
  }, [isOpen, farmId, isStaff, threads])

  // Load threads
  useEffect(() => {
    if (!isOpen || !userId || !farmId) return
    loadThreads()
  }, [isOpen, userId, farmId])

  // React to global open from header bell
  useEffect(() => {
    if (isGlobalOpen && !isOpen) {
      setIsOpen(true)
      // if a specific thread was requested, try to open it after threads load
      setTimeout(async () => {
        await loadThreads()
        if (openThreadId) {
          const t = (Array.isArray(threads) ? threads : []).find(x => x.threadId === openThreadId)
          if (t) {
            await openThread(t)
          }
        } else {
          // Auto-open most recent unread if any
          const unread = [...threads].filter(t => (t.unreadCount || 0) > 0)
          if (unread.length > 0) {
            const newest = unread.sort((a, b) =>
              new Date(b.lastMessageAt || 0).getTime() - new Date(a.lastMessageAt || 0).getTime()
            )[0]
            if (newest) await openThread(newest)
          }
        }
      }, 0)
    }
  }, [isGlobalOpen])

  // Setup SignalR connection
  useEffect(() => {
    if (!isOpen || !userId || !farmId) return

    const conn = new HubConnectionBuilder()
      .withUrl(`${API_BASE_URL}/hubs/chat`)
      .withAutomaticReconnect()
      .configureLogging(LogLevel.Information)
      .build()

    conn.on("message", (msg: any) => {
      const chatMsg = msg as ChatMessage
      const isActiveThread = chatMsg.threadId === activeThread?.threadId
      const isFromOther = chatMsg.userId !== userId
      
      if (isActiveThread) {
        // Add message to active chat, but check for duplicates
        setMessages((prev) => {
          // Remove any temp messages with same content from current user
          const noTemps = prev.filter(m => !m.messageId.startsWith("temp-"))
          // Check if message already exists
          const exists = noTemps.some(m => m.messageId === chatMsg.messageId)
          if (!exists) {
            return [...noTemps, chatMsg]
          }
          return noTemps
        })
        scrollToBottom()
      } else if (isFromOther) {
        // Show toast notification for messages in other threads
        // Use current threads state via function that will be called after loadThreads
        loadThreads().then(() => {
          // After threads are refreshed, find the thread and show toast
          setTimeout(() => {
            setThreads((currentThreads) => {
              const thread = currentThreads.find(t => t.threadId === chatMsg.threadId)
              const senderName = thread?.otherUserFirstName && thread?.otherUserLastName
                ? `${thread.otherUserFirstName} ${thread.otherUserLastName}`
                : thread?.otherUserName || thread?.otherUserId || "Someone"
              toast.info("New message", {
                description: `${senderName}: ${chatMsg.content.substring(0, 50)}${chatMsg.content.length > 50 ? '...' : ''}`,
                duration: 5000,
                action: {
                  label: "Open",
                  onClick: async () => {
                    setIsOpen(true)
                    setShowUserList(false)
                    // Find and open the thread
                    const foundThread = currentThreads.find(t => t.threadId === chatMsg.threadId)
                    if (foundThread && openThreadRef.current) {
                      await openThreadRef.current(foundThread)
                    }
                  }
                }
              })
              // increment global unread badge
              try { incUnread(1) } catch {}
              return currentThreads
            })
          }, 100)
        })
      } else {
        // Just refresh threads for unread counts
        loadThreads()
      }
    })

    conn.on("typing", (data: { threadId: string; userId: string }) => {
      if (data.threadId === activeThread?.threadId && data.userId !== userId) {
        setIsTyping(true)
        setTimeout(() => setIsTyping(false), 3000)
      }
    })

    conn.on("read", (data: { threadId: string; userId: string }) => {
      if (data.threadId === activeThread?.threadId) {
        setMessages((prev) =>
          prev.map((m) => ({ ...m, isRead: true }))
        )
      }
      loadThreads()
    })

    conn.start().catch((err: unknown) => {
      console.error("[Chat] SignalR connection error:", err)
    })

    connRef.current = conn

    return () => {
      conn.stop().catch(() => {})
    }
  }, [isOpen, activeThread?.threadId, userId, farmId])

  const loadChatableUsers = async () => {
    if (!farmId) return
    try {
      setLoading(true)
      
      if (isStaff) {
        // Staff: Extract admin/owner from existing threads OR allow creating thread with known admin
        // For new chats, staff can manually enter admin ID or we show existing thread participants
        // Convert existing thread participants to chatable users format
        const adminUsers: Employee[] = []
        const uniqueAdminIds = new Set<string>()
        
        threads.forEach(t => {
          if (t.otherUserId && !uniqueAdminIds.has(t.otherUserId)) {
            uniqueAdminIds.add(t.otherUserId)
            // Create a user object from thread data
            adminUsers.push({
              id: t.otherUserId,
              email: "", // Will be empty, could fetch from profile if needed
              firstName: "", // Will be empty
              lastName: "", // Will be empty  
              phoneNumber: "",
              userName: t.otherUserId,
              farmId: farmId,
              farmName: "",
              isStaff: false, // Admin/owner
              emailConfirmed: false,
              createdDate: t.createdAt || new Date().toISOString()
            })
          }
        })
        
        // If no existing threads, show a placeholder so they know they can start chatting
        // In the future, we can add an API endpoint to fetch farm admins
        setChatableUsers(adminUsers)
      } else {
        // Admins: Show all staff members (requires Admin API auth token)
        const token = typeof window !== "undefined" ? localStorage.getItem("auth_token") : null
        if (!token) {
          setChatableUsers([])
          return
        }
        try {
          const res = await getEmployees()
          if (res.success && res.data) {
            const filtered = res.data.filter((emp) => 
              emp.isStaff && emp.id !== userId
            )
            setChatableUsers(filtered)
          } else {
            // Graceful fallback on 401/failed Admin API
            console.log("[Chat] Admin API unavailable, using existing threads only")
            setChatableUsers([])
          }
        } catch (err) {
          // Silently handle Admin API errors - chat still works with existing threads
          console.log("[Chat] Could not load staff list from Admin API, using existing threads")
          setChatableUsers([])
        }
      }
    } catch (err) {
      console.error("[Chat] Error loading users:", err)
    } finally {
      setLoading(false)
    }
  }

  const loadThreads = async (): Promise<void> => {
    if (!userId || !farmId) return Promise.resolve()
    try {
      const ts = await getThreads(userId, farmId)
      setThreads(Array.isArray(ts) ? ts : [])
      const totalUnread = (Array.isArray(ts) ? ts : []).reduce((sum, t) => sum + (t.unreadCount || 0), 0)
      setUnread(totalUnread)
    } catch (err: any) {
      // Handle 401 gracefully - user may not be authenticated for chat API yet
      if (err?.message?.includes('401') || err?.status === 401) {
        console.log("[Chat] Not authenticated for chat API, chat unavailable")
        setThreads([])
        setUnread(0)
      } else {
        console.error("[Chat] Error loading threads:", err)
        setThreads([]) // Set empty array on error
      }
    }
  }

  const startChatWithUser = async (otherUserId: string, userName: string) => {
    if (!userId || !farmId) return
    try {
      setLoading(true)
      const thread = await createOrGetThread(farmId, userId, otherUserId)
      setActiveThread({ ...thread, otherUserId: userName })
      setShowUserList(false)

      // Load messages
      const msgs = await getMessages(thread.threadId)
      setMessages(msgs)

      // Join SignalR thread
      await connRef.current?.invoke("JoinThread", thread.threadId)

      // Mark as read
      await markRead(thread.threadId, userId)
      await loadThreads()
    } catch (err) {
      console.error("[Chat] Error starting chat:", err)
    } finally {
      setLoading(false)
    }
  }

  const openThread = async (thread: ChatThread) => {
    setActiveThread(thread)
    setShowUserList(false)
    try {
      const msgs = await getMessages(thread.threadId)
      setMessages(Array.isArray(msgs) ? msgs : [])
      await connRef.current?.invoke("JoinThread", thread.threadId)
      await markRead(thread.threadId, userId!)
      await loadThreads() // Update unread counts
      scrollToBottom()
    } catch (err) {
      console.error("[Chat] Error opening thread:", err)
    }
  }
  
  // Store openThread in ref for use in SignalR handler
  useEffect(() => {
    openThreadRef.current = openThread
  }, [userId])

  const handleSend = async () => {
    if (!activeThread || !messageText.trim() || !userId) return

    const content = messageText.trim()
    setMessageText("")

    try {
      // Optimistic update with temp ID
      const tempId = `temp-${Date.now()}`
      const tempMsg: ChatMessage = {
        messageId: tempId,
        threadId: activeThread.threadId,
        userId: userId,
        content,
        createdAt: new Date().toISOString(),
        isRead: false,
      }
      setMessages((prev) => [...prev, tempMsg])
      scrollToBottom()

      // Send via API (this will return the real message)
      const realMsg = await sendMessage(activeThread.threadId, userId, content)

      // Replace temp message with real one
      setMessages((prev) => {
        // Remove temp message and add real one
        const filtered = prev.filter(m => m.messageId !== tempId)
        // Check if real message already exists (from SignalR)
        const exists = filtered.some(m => m.messageId === realMsg.messageId)
        if (!exists) {
          return [...filtered, realMsg]
        }
        return filtered
      })

      // SignalR will also broadcast, but we handle duplicates there too
      await connRef.current?.invoke("SendMessage", activeThread.threadId, userId, content)

      await loadThreads()
    } catch (err: any) {
      console.error("[Chat] Error sending message:", err)
      // Remove temp message on error
      setMessages((prev) => prev.filter(m => !m.messageId.startsWith("temp-")))
      
      // Show user-friendly error message
      const errorMessage = err?.message || "Failed to send message"
      if (errorMessage.includes("403") || errorMessage.includes("Forbid")) {
        toast.error("Permission Denied", {
          description: "You don't have permission to send messages in this thread. Please contact support if this persists.",
        })
      } else if (errorMessage.includes("401") || errorMessage.includes("Unauthorized")) {
        toast.error("Authentication Required", {
          description: "Please log in again to send messages.",
        })
      } else {
        toast.error("Failed to Send", {
          description: errorMessage,
        })
      }
    }
  }

  const scrollToBottom = () => {
    setTimeout(() => {
      messagesEndRef.current?.scrollIntoView({ behavior: "smooth" })
    }, 100)
  }

  useEffect(() => {
    if (activeThread && messages.length > 0) {
      scrollToBottom()
    }
  }, [messages, activeThread])

  // Don't render on server to prevent hydration errors
  if (!mounted || !userId || !farmId) return null

  return (
    <>
      {/* Floating Chat Button */}
      <Button
        onClick={() => setIsOpen(true)}
        className="fixed bottom-20 right-6 lg:bottom-6 h-14 w-14 rounded-full shadow-lg z-50 bg-blue-600 hover:bg-blue-700"
        size="icon"
      >
        <MessageCircle className="h-6 w-6" />
      </Button>

      {/* Chat Dialog */}
      <Dialog open={isOpen} onOpenChange={(open) => {
        setIsOpen(open)
        if (!open) {
          try { closeGlobal() } catch {}
          setShowUserList(true)
          setActiveThread(null)
          setMessages([])
        }
      }}>
        <DialogContent className="w-[95vw] max-w-4xl h-[85vh] max-h-[800px] flex flex-col p-0">
          <DialogHeader className="px-6 py-4 border-b">
            <div className="flex items-center justify-between">
              <div>
                <DialogTitle className="flex items-center gap-2">
                  <MessageCircle className="h-5 w-5" />
                  Chat
                </DialogTitle>
                <DialogDescription className="sr-only">
                  Chat with team members and administrators
                </DialogDescription>
              </div>
              <Button
                variant="ghost"
                size="icon"
                onClick={() => {
                  setIsOpen(false)
                  try { closeGlobal() } catch {}
                  setShowUserList(true)
                  setActiveThread(null)
                  setMessages([])
                }}
              >
                <X className="h-4 w-4" />
              </Button>
            </div>
          </DialogHeader>

          <div className="flex-1 flex overflow-hidden">
            {/* Thread List Sidebar */}
            <div className="w-1/4 min-w-[200px] border-r flex flex-col">
              <div className="p-3 border-b">
              <Button
                variant="outline"
                size="sm"
                className="w-full justify-start"
                onClick={async () => {
                  setShowUserList(true)
                  setActiveThread(null)
                  // Reload chatable users when clicking "New Chat"
                  if (farmId) {
                    await loadChatableUsers()
                  }
                }}
              >
                <Users className="h-4 w-4 mr-2" />
                {showUserList ? "New Chat" : "Start New Chat"}
              </Button>
              </div>
              <ScrollArea className="flex-1">
                <div className="p-2 space-y-1">
                  {threads.map((thread) => (
                    <Button
                      key={thread.threadId}
                      variant={activeThread?.threadId === thread.threadId ? "secondary" : "ghost"}
                      className="w-full justify-between"
                      onClick={() => openThread(thread)}
                    >
                      <span className="truncate text-sm">
                        {thread.otherUserFirstName && thread.otherUserLastName
                          ? `${thread.otherUserFirstName} ${thread.otherUserLastName}`
                          : thread.otherUserName || thread.otherUserId || `Thread ${thread.threadId.slice(0, 8)}`}
                      </span>
                      {thread.unreadCount && thread.unreadCount > 0 && (
                        <Badge variant="destructive" className="ml-2">
                          {thread.unreadCount}
                        </Badge>
                      )}
                    </Button>
                  ))}
                </div>
              </ScrollArea>
            </div>

            {/* Main Chat Area */}
            <div className="flex-1 flex flex-col">
              {showUserList ? (
                /* User Selection */
                <div className="flex-1 overflow-auto p-3">
                  <h3 className="text-sm font-semibold mb-3">
                    {isStaff ? "Chat with Farm Owner/Admin" : "Select Staff Member to Chat"}
                  </h3>
                  {loading ? (
                    <div className="text-center text-muted-foreground py-8">Loading users...</div>
                  ) : chatableUsers.length === 0 ? (
                    <div className="text-center text-muted-foreground py-8 space-y-2">
                      {isStaff ? (
                        <>
                          {threads.length === 0 ? (
                            <>
                              <p>No conversations yet. Start by messaging your farm owner/admin.</p>
                              <p className="text-xs">If you have a thread in the left sidebar, use that to continue chatting.</p>
                            </>
                          ) : (
                            <>
                              <p>Select an existing conversation from the left sidebar to continue chatting.</p>
                              <p className="text-xs">All your conversations appear in the left sidebar.</p>
                            </>
                          )}
                        </>
                      ) : (
                        <p>No staff members available to chat</p>
                      )}
                    </div>
                  ) : (
                    <div className="space-y-2">
                      {chatableUsers.map((user) => (
                        <Button
                          key={user.id}
                          variant="outline"
                          className="w-full justify-start h-auto p-3"
                          onClick={() => startChatWithUser(user.id, user.firstName && user.lastName ? `${user.firstName} ${user.lastName}` : user.userName || user.id)}
                        >
                          <Avatar className="h-10 w-10 mr-3">
                            <AvatarFallback>
                              {(user.firstName?.[0] || user.userName?.[0] || user.id[0]).toUpperCase()}
                              {(user.lastName?.[0] || user.userName?.[1] || user.id[1]).toUpperCase()}
                            </AvatarFallback>
                          </Avatar>
                          <div className="flex-1 text-left">
                            <div className="font-medium">
                              {user.firstName && user.lastName 
                                ? `${user.firstName} ${user.lastName}` 
                                : user.userName || `Admin (${user.id.slice(0, 8)})`}
                            </div>
                            {user.email && (
                              <div className="text-xs text-muted-foreground">{user.email}</div>
                            )}
                          </div>
                        </Button>
                      ))}
                    </div>
                  )}
                </div>
              ) : activeThread ? (
                /* Active Chat */
                <>
                  <div className="p-3 border-b">
                    <div className="font-medium">
                      {activeThread.otherUserFirstName && activeThread.otherUserLastName
                        ? `${activeThread.otherUserFirstName} ${activeThread.otherUserLastName}`
                        : activeThread.otherUserName || activeThread.otherUserId || `Thread ${activeThread.threadId.slice(0, 8)}`}
                    </div>
                  </div>
                  <ScrollArea className="flex-1 p-4 min-h-0">
                    <div className="space-y-3 pr-4">
                      {messages.map((msg) => {
                        const isMe = msg.userId === userId
                        const senderName = isMe 
                          ? (typeof window !== "undefined" ? localStorage.getItem("username") || "You" : "You")
                          : (activeThread?.otherUserFirstName && activeThread?.otherUserLastName
                              ? `${activeThread.otherUserFirstName} ${activeThread.otherUserLastName}`
                              : activeThread?.otherUserName || activeThread?.otherUserId || `User ${msg.userId.slice(0, 8)}`)
                        
                        return (
                          <div
                            key={msg.messageId}
                            className={`flex flex-col ${isMe ? "items-end" : "items-start"}`}
                          >
                            {!isMe && (
                              <span className="text-xs text-muted-foreground mb-1 px-1">
                                {senderName}
                              </span>
                            )}
                            <div
                              className={`max-w-[70%] px-4 py-2 rounded-lg text-sm ${
                                isMe
                                  ? "bg-blue-600 text-white"
                                  : "bg-slate-100 text-slate-900"
                              }`}
                            >
                              {msg.content}
                            </div>
                          </div>
                        )
                      })}
                      {isTyping && (
                        <div className="flex justify-start">
                          <div className="bg-slate-100 px-4 py-2 rounded-lg">
                            <span className="text-xs text-muted-foreground">Typing...</span>
                          </div>
                        </div>
                      )}
                      <div ref={messagesEndRef} />
                    </div>
                  </ScrollArea>
                  <div className="p-3 border-t flex gap-2">
                    <Input
                      value={messageText}
                      onChange={(e) => setMessageText(e.target.value)}
                      placeholder="Type a message..."
                      onKeyDown={(e) => {
                        if (e.key === "Enter" && !e.shiftKey) {
                          e.preventDefault()
                          handleSend()
                        }
                      }}
                    />
                    <Button onClick={handleSend} disabled={!messageText.trim()}>
                      <Send className="h-4 w-4" />
                    </Button>
                  </div>
                </>
              ) : (
                <div className="flex-1 flex items-center justify-center text-muted-foreground">
                  Select a conversation or start a new chat
                </div>
              )}
            </div>
          </div>
        </DialogContent>
      </Dialog>
    </>
  )
}


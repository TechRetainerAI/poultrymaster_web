"use client"

import { useEffect, useMemo, useRef, useState } from "react"
import { HubConnectionBuilder, LogLevel } from "@microsoft/signalr"
import { getThreads, getMessages, sendMessage, type ChatThread, type ChatMessage, createOrGetThread, markRead } from "@/lib/api/chat"
import { getUserContext } from "@/lib/utils/user-context"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"

export default function ChatPage() {
  const { userId, farmId } = getUserContext()
  const [threads, setThreads] = useState<ChatThread[]>([])
  const [active, setActive] = useState<ChatThread | null>(null)
  const [messages, setMessages] = useState<ChatMessage[]>([])
  const [text, setText] = useState("")
  const connRef = useRef<any>()

  useEffect(() => {
    if (!userId || !farmId) return
    loadThreads()
    const conn = new HubConnectionBuilder()
      .withUrl("/hubs/chat")
      .withAutomaticReconnect()
      .configureLogging(LogLevel.Information)
      .build()
    conn.on("message", (m) => {
      if (m.threadId === active?.threadId) {
        setMessages((prev) => [...prev, m])
      }
      loadThreads()
    })
    conn.on("typing", () => {})
    conn.start().catch(() => {})
    connRef.current = conn
    return () => { conn.stop().catch(() => {}) }
  }, [])

  const loadThreads = async () => {
    const th = await getThreads(userId!, farmId!)
    setThreads(th)
  }

  const openThread = async (t: ChatThread) => {
    setActive(t)
    const ms = await getMessages(t.threadId)
    setMessages(ms)
    await connRef.current?.invoke("JoinThread", t.threadId)
    await markRead(t.threadId, userId!)
    await loadThreads()
  }

  const onSend = async () => {
    if (!active || !text.trim()) return
    setText("")
    await sendMessage(active.threadId, userId!, text.trim())
  }

  return (
    <div className="p-6 grid grid-cols-1 md:grid-cols-3 gap-4">
      <Card className="md:col-span-1">
        <CardHeader><CardTitle>Conversations</CardTitle></CardHeader>
        <CardContent className="space-y-2">
          {threads.map(t => (
            <Button key={t.threadId} variant={active?.threadId===t.threadId?"default":"outline"} className="w-full justify-between" onClick={()=>openThread(t)}>
              <span>{t.otherUserId || t.threadId.slice(0,8)}</span>
              {t.unreadCount ? <span className="text-xs bg-red-600 text-white px-2 rounded-full">{t.unreadCount}</span> : null}
            </Button>
          ))}
        </CardContent>
      </Card>
      <Card className="md:col-span-2">
        <CardHeader><CardTitle>{active ? (active.otherUserId || active.threadId) : "Select a conversation"}</CardTitle></CardHeader>
        <CardContent>
          <div className="h-80 overflow-auto border rounded p-3 space-y-2">
            {messages.map(m => (
              <div key={m.messageId} className={`flex ${m.userId===userId?"justify-end":"justify-start"}`}>
                <div className={`px-3 py-2 rounded-lg ${m.userId===userId?"bg-blue-600 text-white":"bg-slate-50"}`}>
                  {m.content}
                </div>
              </div>
            ))}
          </div>
          {active && (
            <div className="mt-3 flex gap-2">
              <Input value={text} onChange={(e)=>setText(e.target.value)} placeholder="Type a message" />
              <Button onClick={onSend}>Send</Button>
            </div>
          )}
        </CardContent>
      </Card>
    </div>
  )
}



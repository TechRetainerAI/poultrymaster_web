import { create } from 'zustand'

interface ChatState {
  unreadCount: number
  isOpen: boolean
  openThreadId?: string
  setUnread: (count: number) => void
  incUnread: (by?: number) => void
  clearUnread: () => void
  openChat: (threadId?: string) => void
  closeChat: () => void
}

export const useChatStore = create<ChatState>((set) => ({
  unreadCount: 0,
  isOpen: false,
  setUnread: (count: number) => set({ unreadCount: Math.max(0, count) }),
  incUnread: (by = 1) => set((s) => ({ unreadCount: Math.max(0, s.unreadCount + by) })),
  clearUnread: () => set({ unreadCount: 0 }),
  openChat: (threadId) => set({ isOpen: true, openThreadId: threadId }),
  closeChat: () => set({ isOpen: false, openThreadId: undefined }),
}))



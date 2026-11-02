"use client"

import { forwardRef, useImperativeHandle, useRef, useState } from "react"
import { Mail, MessageCircle, Phone } from "lucide-react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Textarea } from "@/components/ui/textarea"
import { mailtoLink, SUPPORT_EMAIL, SUPPORT_PHONES, whatsappLink } from "@/lib/help/support"

export interface ContactSupportHandle {
  /** Put a question in the message box and bring the card into view. */
  ask: (message: string) => void
}

/**
 * Write the problem once, send it by WhatsApp or email. Only the user's own
 * message is sent -- nothing about the company, page, user or browser.
 */
export const ContactSupport = forwardRef<ContactSupportHandle>(function ContactSupport(_, ref) {
  const [message, setMessage] = useState("")
  const cardRef = useRef<HTMLDivElement>(null)
  const boxRef = useRef<HTMLTextAreaElement>(null)

  useImperativeHandle(ref, () => ({
    ask: (q: string) => {
      setMessage(q)
      cardRef.current?.scrollIntoView({ behavior: "smooth", block: "center" })
      setTimeout(() => boxRef.current?.focus(), 300)
    },
  }))

  return (
    <Card ref={cardRef} id="contact" className="scroll-mt-24 border-indigo-200 bg-indigo-50/50">
      <CardHeader>
        <CardTitle className="flex items-center gap-2 text-indigo-900">
          <MessageCircle className="h-5 w-5" />
          Contact support
        </CardTitle>
        <CardDescription className="text-indigo-700">
          Describe what you were doing and what went wrong. Only your message is sent.
        </CardDescription>
      </CardHeader>
      <CardContent className="space-y-3">
        <Textarea
          ref={boxRef}
          value={message}
          onChange={(e) => setMessage(e.target.value)}
          placeholder="e.g. I recorded a sale this morning but it isn't showing on Daily Closing."
          rows={3}
          className="bg-white"
        />
        <div className="flex flex-wrap gap-2">
          <Button asChild className="bg-emerald-600 hover:bg-emerald-700">
            <a href={whatsappLink(message)} target="_blank" rel="noopener noreferrer">
              <MessageCircle className="mr-1.5 h-4 w-4" /> Send on WhatsApp
            </a>
          </Button>
          <Button asChild variant="outline" className="bg-white">
            <a href={mailtoLink(message)}>
              <Mail className="mr-1.5 h-4 w-4" /> Send by email
            </a>
          </Button>
        </div>

        <div className="flex flex-wrap gap-x-6 gap-y-2 border-t border-indigo-100 pt-3 text-sm text-slate-600">
          <a href={`mailto:${SUPPORT_EMAIL}`} className="flex items-center gap-2 hover:text-indigo-700">
            <Mail className="h-4 w-4 text-indigo-500" /> {SUPPORT_EMAIL}
          </a>
          {SUPPORT_PHONES.map((p) => (
            <a key={p} href={`tel:${p.replace(/[^\d+]/g, "")}`} className="flex items-center gap-2 hover:text-indigo-700">
              <Phone className="h-4 w-4 text-indigo-500" /> {p}
            </a>
          ))}
        </div>
      </CardContent>
    </Card>
  )
})

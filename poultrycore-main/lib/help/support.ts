/**
 * Contacting support from the Help Center.
 *
 * Nothing here talks to a server: the message is handed to the user's own
 * email app or WhatsApp, so they see and send it themselves.
 */

export const SUPPORT_EMAIL = "techretainer@gmail.com"
/** Display form, as on the old page. */
export const SUPPORT_PHONES = ["+1 (917) 420-2946", "053 343 1086"]
/** International form of the US line, for wa.me (digits only, no +). */
export const SUPPORT_WHATSAPP = "19174202946"

/**
 * WhatsApp and email carry the user's own words and nothing else -- no
 * company, page or browser details, and no subject line.
 */
export function mailtoLink(message: string): string {
  const body = message.trim()
  return body ? `mailto:${SUPPORT_EMAIL}?body=${encodeURIComponent(body)}` : `mailto:${SUPPORT_EMAIL}`
}

export function whatsappLink(message: string): string {
  const text = message.trim()
  return text ? `https://wa.me/${SUPPORT_WHATSAPP}?text=${encodeURIComponent(text)}` : `https://wa.me/${SUPPORT_WHATSAPP}`
}

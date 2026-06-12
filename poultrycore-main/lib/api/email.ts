import { buildApiUrl, getAuthHeaders } from "./config"

export interface SendReportEmailInput {
  blob: Blob
  filename: string
  to: string
  subject?: string
  body?: string
  farmName?: string
  reportTitle?: string
}

export interface ApiResponse<T = unknown> {
  success: boolean
  data?: T
  message?: string
}

// POST /api/Email/Report — multipart upload of a PDF blob plus delivery params.
// Auth headers come from getAuthHeaders() but the Content-Type is intentionally
// omitted so the browser sets a multipart boundary.
export async function sendReportEmail(input: SendReportEmailInput): Promise<ApiResponse<{ message?: string }>> {
  try {
    const form = new FormData()
    form.append("file", input.blob, input.filename || "report.pdf")
    form.append("to", input.to)
    if (input.subject) form.append("subject", input.subject)
    if (input.body) form.append("body", input.body)
    if (input.farmName) form.append("farmName", input.farmName)
    if (input.reportTitle) form.append("reportTitle", input.reportTitle)

    // Strip Content-Type if getAuthHeaders includes it — let fetch set it.
    const headers = { ...getAuthHeaders() } as Record<string, string>
    delete headers["Content-Type"]
    delete headers["content-type"]

    const url = buildApiUrl("/Email/Report")
    const response = await fetch(url, {
      method: "POST",
      headers,
      body: form,
    })

    if (!response.ok) {
      let message = `Failed to send email (status ${response.status})`
      try {
        const data = await response.json()
        message = data?.message || message
      } catch {
        const text = await response.text()
        if (text) message = text
      }
      return { success: false, message }
    }

    const data = await response.json().catch(() => ({}))
    return { success: true, data, message: (data as any)?.message }
  } catch (e) {
    return { success: false, message: (e as Error)?.message || "Network error sending email" }
  }
}

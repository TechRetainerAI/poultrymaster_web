/** Upload a receipt image to the Next.js app (same origin). Requires Bearer auth. */
export async function uploadExpenseReceipt(
  file: File,
  farmId: string
): Promise<{ success: boolean; path?: string; message?: string }> {
  const formData = new FormData()
  formData.append("file", file)
  formData.append("farmId", farmId)

  const headers: Record<string, string> = { Accept: "application/json" }
  if (typeof window !== "undefined") {
    const token = localStorage.getItem("auth_token")
    if (token) headers.Authorization = `Bearer ${token}`
  }

  try {
    const res = await fetch("/api/receipt-upload", { method: "POST", headers, body: formData })
    const data = (await res.json().catch(() => ({}))) as { path?: string; message?: string }
    if (!res.ok) {
      return { success: false, message: data.message || `Upload failed (${res.status})` }
    }
    if (!data.path) return { success: false, message: "Upload response missing path" }
    return { success: true, path: data.path }
  } catch (e) {
    return { success: false, message: e instanceof Error ? e.message : "Upload failed" }
  }
}

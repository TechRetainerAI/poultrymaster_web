/** Base64 payload only (no `data:image/...;base64,` prefix) for JSON APIs. */
export function fileToBase64DataOnly(file: File): Promise<string> {
  return new Promise((resolve, reject) => {
    const reader = new FileReader()
    reader.onload = () => {
      const s = reader.result as string
      const i = s.indexOf(",")
      resolve(i >= 0 ? s.slice(i + 1) : s)
    }
    reader.onerror = () => reject(new Error("Could not read file"))
    reader.readAsDataURL(file)
  })
}

"use client"

// Users & Permissions now reuses the full /employees page rendered inside the
// Business Office shell (?bo=1) — same data, same features. Redirect any old
// links here to that page.
import { useEffect } from "react"
import { useRouter } from "next/navigation"

export default function BusinessOfficeUsersRedirect() {
  const router = useRouter()
  useEffect(() => { router.replace("/employees?bo=1") }, [router])
  return <div className="min-h-screen bg-slate-50" />
}

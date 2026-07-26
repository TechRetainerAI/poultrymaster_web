"use client"

import type React from "react"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Eye, EyeOff, ChevronLeft, Check, Loader2, X } from "lucide-react"
import { register, checkOrgCodeAvailable } from "@/lib/api/auth"
import Link from "next/link"

// Derive a friendly org code from a name (letters/numbers only, max 20).
function suggestOrgCode(name: string): string {
  return (name || "").toUpperCase().replace(/[^A-Z0-9]/g, "").slice(0, 20)
}

// Identity-style errors come back as a string[] OR an object map ({ field: [msgs] }).
function flattenErrors(errors: unknown): string[] {
  if (!errors) return []
  if (Array.isArray(errors)) return errors.map((e) => String(e))
  if (typeof errors === "object") {
    return Object.values(errors as Record<string, unknown>).flat().map((e) => String(e))
  }
  return [String(errors)]
}

const USERNAME_RE = /^[A-Za-z0-9._-]{3,30}$/
const PHONE_RE = /^(\+?\d{7,15}|0\d{6,14})$/
type CType = "" | "Poultry" | "Water" | "Generic"

const inputCls = "h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"

export default function RegisterPage() {
  const router = useRouter()
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [errorList, setErrorList] = useState<string[]>([])
  const [success, setSuccess] = useState(false)

  const [f, setF] = useState({
    businessName: "",
    firstName: "", lastName: "", username: "", email: "", phoneNumber: "",
    password: "", confirmPassword: "",
    organizationCode: "", companyType: "" as CType, companyName: "",
  })
  const set = (k: keyof typeof f, v: string) => setF((p) => ({ ...p, [k]: v }))
  // First company is opt-in: the icons + company form stay hidden until ticked.
  const [createCompany, setCreateCompany] = useState(false)
  const toggleCreateCompany = () =>
    setCreateCompany((prev) => {
      const next = !prev
      if (!next) setF((p) => ({ ...p, companyType: "", companyName: "" }))
      return next
    })
  const [codeTouched, setCodeTouched] = useState(false)
  const [codeCheck, setCodeCheck] = useState<{ status: "idle" | "checking" | "ok" | "bad"; reason?: string; suggestions?: string[] }>({ status: "idle" })

  // The Business Office (headquarters) is named after the business the owner
  // enters at the top; the owner may then opt in to create a first company.
  const ownerName = [f.firstName.trim(), f.lastName.trim()].filter(Boolean).join(" ")
  const businessOfficeName = f.businessName.trim() || ownerName || f.username.trim() || "My Business Office"
  const derivedCompanyName = createCompany
    ? (f.companyName.trim() || (f.companyType ? `${f.firstName.trim() || businessOfficeName}'s ${f.companyType} Company`.trim() : ""))
    : ""

  // Auto-suggest the organization code from the business name (or owner name)
  // until the owner edits it themselves.
  useEffect(() => {
    if (!codeTouched) setF((p) => ({ ...p, organizationCode: suggestOrgCode(p.businessName.trim() || ownerName) }))
  }, [f.businessName, ownerName, codeTouched])

  // Debounced availability check.
  useEffect(() => {
    const code = f.organizationCode.trim()
    if (code.length < 4) { setCodeCheck({ status: code.length === 0 ? "idle" : "bad", reason: code.length === 0 ? undefined : "At least 4 characters." }); return }
    setCodeCheck({ status: "checking" })
    const t = setTimeout(async () => {
      const r = await checkOrgCodeAvailable(code)
      setCodeCheck(r.available ? { status: "ok" } : { status: "bad", reason: r.reason, suggestions: r.suggestions })
    }, 450)
    return () => clearTimeout(t)
  }, [f.organizationCode])

  function validate(): string | null {
    if (!f.businessName.trim()) return "Please enter your business / organization name."
    if (!f.firstName.trim() || !f.lastName.trim()) return "Please enter your first and last name."
    if (!USERNAME_RE.test(f.username.trim())) return "Username must be 3–30 characters: letters, numbers, dot, underscore, or hyphen (no spaces)."
    if (!f.email.trim()) return "Please enter your email address."
    if (!PHONE_RE.test(f.phoneNumber.replace(/[\s()-]/g, ""))) return "Enter a valid phone number including the country code (e.g. +233XXXXXXXXX)."
    if (f.password.length < 6) return "Password must be at least 6 characters."
    if (f.password !== f.confirmPassword) return "Passwords do not match."
    if (f.organizationCode.trim().length < 4) return "Please choose an Organization Code (at least 4 characters)."
    if (codeCheck.status === "bad") return codeCheck.reason || "That Organization Code can't be used. Please pick another."
    if (codeCheck.status === "checking") return "Please wait — still checking the Organization Code."
    // Company is optional — an owner can create it later in the Business Office.
    return null
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(""); setErrorList([])
    const v = validate()
    if (v) { setError(v); return }

    setIsLoading(true)
    // Auto-create the Business Office (name, currency, country) and the first
    // company — the owner only supplied their details, the Business Code, and
    // the company type.
    const result = await register({
      farmName: derivedCompanyName || undefined,  // first company (optional — omit to register with none)
      username: f.username.trim(),
      email: f.email.trim(),
      password: f.password,
      firstName: f.firstName.trim(),
      lastName: f.lastName.trim(),
      phoneNumber: f.phoneNumber.replace(/[\s()-]/g, ""),
      companyType: createCompany ? (f.companyType || undefined) : undefined,
      roles: ["Admin"], // the registrant is the Business Office owner/admin
      businessOfficeName,
      businessOfficeCurrency: "GHS",
      businessOfficeCountry: "Ghana",
      organizationCode: f.organizationCode.trim(),
    })

    if (result.success) {
      try { localStorage.setItem("businessOfficeName", businessOfficeName) } catch {}
      setSuccess(true)
      setTimeout(() => router.push("/login"), 1800)
    } else {
      setError(result.message || "Registration failed. Please try again.")
      setErrorList(flattenErrors(result.errors))
    }
    setIsLoading(false)
  }

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 p-4">
        <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md w-full text-center">
          <div className="mb-6 flex justify-center"><div className="text-6xl">🎉</div></div>
          <h2 className="text-2xl font-bold text-slate-900 mb-3">Business Office created!</h2>
          <p className="text-slate-500 mb-2">Your account, <span className="font-medium">{businessOfficeName}</span>, and your first company are ready.</p>
          <p className="text-slate-500">Taking you to sign in…</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex">
      {/* Left Panel */}
      <div className="hidden lg:flex lg:w-1/2 bg-white items-center justify-center p-12">
        <div className="max-w-md text-center">
          <div className="mb-8">
            <h1 className="text-4xl font-bold text-slate-900 mb-2">VisibilityCore</h1>
            <p className="text-slate-600">Run all your businesses from one place.</p>
          </div>
          <div className="relative">
            <img src="/farmer-illustration.png" alt="VisibilityCore" className="w-full h-96 object-contain" />
          </div>
        </div>
      </div>

      {/* Right Panel */}
      <div className="w-full lg:w-1/2 bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center p-8">
        <div className="w-full max-w-md">
          <Link href="/login" className="inline-flex items-center gap-2 text-orange-400 hover:text-orange-300 mb-6 transition-colors">
            <ChevronLeft className="w-5 h-5" /><span className="font-medium">Back to login</span>
          </Link>

          {(error || errorList.length > 0) && (
            <div className="mb-5 p-4 bg-red-900/20 border border-red-500/30 rounded-lg">
              {error && <p className="text-sm text-red-300">{error}</p>}
              {errorList.length > 0 && (
                <ul className="mt-2 text-sm text-red-300 list-disc list-inside space-y-1">
                  {errorList.map((m, i) => <li key={i}>{m}</li>)}
                </ul>
              )}
            </div>
          )}

          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="text-center mb-2">
              <h2 className="text-xl font-bold text-white">Create your account</h2>
              <p className="text-sm text-slate-300">Name your organization to get started — you can add companies now or later.</p>
            </div>

            {/* Business / Organization name — the headline field. Names the
                Business Office and seeds the Organization Code below. */}
            <div>
              <Input placeholder="Business / organization name" value={f.businessName} onChange={(e) => set("businessName", e.target.value)} className={`${inputCls} text-base font-medium`} disabled={isLoading} autoFocus />
              <p className="mt-1 text-[11px] text-slate-400">This names your Business Office — the home for all your companies.</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Input placeholder="Owner first name" value={f.firstName} onChange={(e) => set("firstName", e.target.value)} className={inputCls} disabled={isLoading} />
              <Input placeholder="Owner last name" value={f.lastName} onChange={(e) => set("lastName", e.target.value)} className={inputCls} disabled={isLoading} />
            </div>
            <Input placeholder="Username" value={f.username} onChange={(e) => set("username", e.target.value)} className={inputCls} disabled={isLoading} />
            <Input type="email" placeholder="Email address" value={f.email} onChange={(e) => set("email", e.target.value)} className={inputCls} disabled={isLoading} />
            <Input type="tel" placeholder="Phone number (e.g. +233...)" value={f.phoneNumber} onChange={(e) => set("phoneNumber", e.target.value)} className={inputCls} disabled={isLoading} />
            <div className="relative">
              <Input type={showPassword ? "text" : "password"} placeholder="Password" value={f.password} onChange={(e) => set("password", e.target.value)} className={`${inputCls} pr-12`} disabled={isLoading} />
              <button type="button" onClick={() => setShowPassword(!showPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-300" aria-label="Toggle password">
                {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
              </button>
            </div>
            <div className="relative">
              <Input type={showConfirmPassword ? "text" : "password"} placeholder="Confirm password" value={f.confirmPassword} onChange={(e) => set("confirmPassword", e.target.value)} className={`${inputCls} pr-12`} disabled={isLoading} />
              <button type="button" onClick={() => setShowConfirmPassword(!showConfirmPassword)} className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-300" aria-label="Toggle confirm password">
                {showConfirmPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
              </button>
            </div>

            {/* Organization Code — auto-suggested from the business name, editable. */}
            <div>
              <div className="relative">
                <Input
                  placeholder="Organization Code (e.g. EVANSBIZ)"
                  value={f.organizationCode}
                  onChange={(e) => { setCodeTouched(true); set("organizationCode", e.target.value.toUpperCase().replace(/[^A-Z0-9_-]/g, "")) }}
                  className={`${inputCls} pr-10 tracking-wide`}
                  maxLength={30}
                  disabled={isLoading}
                />
                <span className="absolute right-3 top-1/2 -translate-y-1/2">
                  {codeCheck.status === "checking" && <Loader2 className="w-4 h-4 animate-spin text-slate-400" />}
                  {codeCheck.status === "ok" && <Check className="w-4 h-4 text-emerald-400" />}
                  {codeCheck.status === "bad" && <X className="w-4 h-4 text-red-400" />}
                </span>
              </div>
              {codeCheck.status === "ok" && <p className="mt-1 text-xs text-emerald-300">✓ {f.organizationCode} is available.</p>}
              {codeCheck.status === "bad" && <p className="mt-1 text-xs text-red-300">{codeCheck.reason}</p>}
              {codeCheck.status === "bad" && codeCheck.suggestions && codeCheck.suggestions.length > 0 && (
                <div className="mt-1 flex flex-wrap gap-1">
                  {codeCheck.suggestions.map((s) => (
                    <button key={s} type="button" onClick={() => { setCodeTouched(true); set("organizationCode", s) }} className="text-xs rounded bg-slate-700 text-slate-200 px-2 py-0.5 hover:bg-slate-600">{s}</button>
                  ))}
                </div>
              )}
              <p className="mt-1 text-[11px] text-slate-400">You and your staff type this code when signing in. Short and memorable is best.</p>
            </div>

            {/* First company — fully optional and opt-in. The type icons + the
                company-name form stay hidden until the owner ticks the box. */}
            <div className="pt-1">
              <label className="flex items-start gap-2 cursor-pointer select-none">
                <input type="checkbox" checked={createCompany} onChange={toggleCreateCompany} disabled={isLoading}
                  className="mt-0.5 h-4 w-4 accent-orange-500 disabled:opacity-50" />
                <span>
                  <span className="block text-sm font-medium text-slate-200">Create my first company now <span className="text-slate-400 font-normal">(optional)</span></span>
                  <span className="block text-[11px] text-slate-400">Leave unchecked to add companies later from your Business Office.</span>
                </span>
              </label>

              {createCompany && (
                <div className="mt-3">
                  <p className="text-[11px] text-slate-400 mb-2">Pick a company type to set it up right away.</p>
                  <div className="grid grid-cols-3 gap-2">
                    {([
                      { value: "Poultry", emoji: "🐔", title: "Poultry" },
                      { value: "Water", emoji: "💧", title: "Water" },
                      { value: "Generic", emoji: "🏪", title: "Generic" },
                    ] as const).map((opt) => {
                      const selected = f.companyType === opt.value
                      // Clicking a selected type again clears it (type stays optional).
                      return (
                        <button key={opt.value} type="button" onClick={() => set("companyType", selected ? "" : opt.value)} disabled={isLoading} aria-pressed={selected}
                          className={`p-3 rounded-lg border-2 text-center transition-all ${selected ? "border-orange-500 bg-orange-500/10 ring-2 ring-orange-500/40" : "border-slate-600 bg-slate-700/30 hover:border-slate-500"} disabled:opacity-50`}>
                          <div className="text-2xl mb-1">{opt.emoji}</div>
                          <div className="text-xs font-semibold text-white">{opt.title}</div>
                        </button>
                      )
                    })}
                  </div>
                  {f.companyType && (
                    <Input placeholder="Company name" value={f.companyName} onChange={(e) => set("companyName", e.target.value)} className={`${inputCls} mt-3`} disabled={isLoading} />
                  )}
                </div>
              )}
            </div>

            <Button type="submit" disabled={isLoading} className="h-12 w-full bg-orange-500 hover:bg-orange-600 text-white font-medium">
              {isLoading ? "Creating…" : "Create account"}
            </Button>

            <div className="text-center">
              <p className="text-sm text-slate-300">Already have an account?{" "}
                <Link href="/login" className="font-medium text-orange-400 hover:text-orange-300">Login</Link>
              </p>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}

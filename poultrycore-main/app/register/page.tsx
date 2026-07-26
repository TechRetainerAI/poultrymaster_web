"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Eye, EyeOff, ChevronLeft } from "lucide-react"
import { register, checkOrgCodeAvailable } from "@/lib/api/auth"
import Link from "next/link"

// Build the organization-code seed: first 3 letters of the owner's first name +
// first 3 of the last name (letters/numbers only, uppercased). E.g. Kwame Owusu → KWAOWU.
function orgCodeSeed(first: string, last: string): string {
  const clean = (s: string) => (s || "").toUpperCase().replace(/[^A-Z0-9]/g, "")
  return clean(first).slice(0, 3) + clean(last).slice(0, 3)
}

// Turn the seed into a code that is unique in the database. Try the seed, then
// seed2, seed3, … until availability check passes. Owner can change it later in
// the Business Office. Codes are padded to the 4-char minimum.
async function generateUniqueOrgCode(seed: string): Promise<string> {
  const base = seed || "ORG"
  for (let i = 0; i < 25; i++) {
    let code = i === 0 ? base : `${base}${i + 1}`
    while (code.length < 4) code += "X"
    try {
      const r = await checkOrgCodeAvailable(code)
      if (r.available) return code
      // The endpoint reports its own failures as { available:false, reason:"Check
      // failed…" }. Don't hammer it 25× — take this candidate and let the server
      // reject on the (unique-constrained) register call if it's genuinely taken.
      if (r.reason && /check failed|could not check/i.test(r.reason)) return code
    } catch {
      return code
    }
  }
  return `${base}${Date.now() % 100000}`
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
    firstName: "", lastName: "", username: "", email: "", phoneNumber: "",
    password: "", confirmPassword: "",
    companyType: "" as CType, companyName: "",
  })
  const set = (k: keyof typeof f, v: string) => setF((p) => ({ ...p, [k]: v }))
  // First company is opt-in: the type icons + company name field stay hidden
  // until the owner ticks the box.
  const [createCompany, setCreateCompany] = useState(false)
  const toggleCreateCompany = () =>
    setCreateCompany((prev) => {
      const next = !prev
      if (!next) setF((p) => ({ ...p, companyType: "", companyName: "" }))
      return next
    })

  // The Business Office (headquarters) name is generated automatically from the
  // owner's last name — "Owusu" → "Owusu Companies". The Organization Code is
  // generated at submit (see generateUniqueOrgCode). Both are editable later in
  // the Business Office.
  const ownerName = [f.firstName.trim(), f.lastName.trim()].filter(Boolean).join(" ")
  const businessOfficeName = f.lastName.trim()
    ? `${f.lastName.trim()} Companies`
    : (ownerName || f.username.trim() || "My Business Office")

  function validate(): string | null {
    if (!f.firstName.trim() || !f.lastName.trim()) return "Please enter the owner's first and last name."
    if (!USERNAME_RE.test(f.username.trim())) return "Username must be 3–30 characters: letters, numbers, dot, underscore, or hyphen (no spaces)."
    if (!f.email.trim()) return "Please enter your email address."
    if (!PHONE_RE.test(f.phoneNumber.replace(/[\s()-]/g, ""))) return "Please enter a valid phone number."
    if (f.password.length < 6) return "Password must be at least 6 characters."
    if (f.password !== f.confirmPassword) return "Passwords do not match."
    if (createCompany) {
      if (!f.companyType) return "Please choose a company type, or uncheck \"Create my first company now\"."
      if (!f.companyName.trim()) return "Please enter the company name."
    }
    return null
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(""); setErrorList([])
    const v = validate()
    if (v) { setError(v); return }

    setIsLoading(true)
    // Auto-generate the Business Office name (from last name) and a unique
    // Organization Code (from the owner's initials) — the owner supplied only
    // their details and, optionally, a first company.
    const organizationCode = await generateUniqueOrgCode(orgCodeSeed(f.firstName, f.lastName))
    const result = await register({
      farmName: createCompany ? (f.companyName.trim() || undefined) : undefined,  // first company (optional)
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
      organizationCode,
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
          <p className="text-slate-500 mb-2">Your Business Office, <span className="font-medium">{businessOfficeName}</span>, is ready.</p>
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
              <p className="text-sm text-slate-300">Just your details — your Business Office is set up automatically.</p>
            </div>

            <div className="grid grid-cols-2 gap-3">
              <Input placeholder="Owner first name" value={f.firstName} onChange={(e) => set("firstName", e.target.value)} className={inputCls} disabled={isLoading} autoFocus />
              <Input placeholder="Owner last name" value={f.lastName} onChange={(e) => set("lastName", e.target.value)} className={inputCls} disabled={isLoading} />
            </div>
            <Input placeholder="Username" value={f.username} onChange={(e) => set("username", e.target.value)} className={inputCls} disabled={isLoading} />
            <Input type="email" placeholder="Email address" value={f.email} onChange={(e) => set("email", e.target.value)} className={inputCls} disabled={isLoading} />
            <Input type="tel" placeholder="Phone number" value={f.phoneNumber} onChange={(e) => set("phoneNumber", e.target.value)} className={inputCls} disabled={isLoading} />
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

            {/* First company — fully optional and opt-in. Ticking the box reveals
                the type icons and the company-name field together. */}
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
                <div className="mt-3 space-y-3">
                  <p className="text-[11px] text-slate-400">Pick a company type and give it a name.</p>
                  <div className="grid grid-cols-3 gap-2">
                    {([
                      { value: "Poultry", emoji: "🐔", title: "Poultry" },
                      { value: "Water", emoji: "💧", title: "Water" },
                      { value: "Generic", emoji: "🏪", title: "Generic" },
                    ] as const).map((opt) => {
                      const selected = f.companyType === opt.value
                      // Clicking a selected type again clears it.
                      return (
                        <button key={opt.value} type="button" onClick={() => set("companyType", selected ? "" : opt.value)} disabled={isLoading} aria-pressed={selected}
                          className={`p-3 rounded-lg border-2 text-center transition-all ${selected ? "border-orange-500 bg-orange-500/10 ring-2 ring-orange-500/40" : "border-slate-600 bg-slate-700/30 hover:border-slate-500"} disabled:opacity-50`}>
                          <div className="text-2xl mb-1">{opt.emoji}</div>
                          <div className="text-xs font-semibold text-white">{opt.title}</div>
                        </button>
                      )
                    })}
                  </div>
                  <Input placeholder="Company name" value={f.companyName} onChange={(e) => set("companyName", e.target.value)} className={inputCls} disabled={isLoading} />
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

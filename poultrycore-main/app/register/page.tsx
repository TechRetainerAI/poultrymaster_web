"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Eye, EyeOff, ChevronLeft, ChevronRight, Check } from "lucide-react"
import { register } from "@/lib/api/auth"
import Link from "next/link"

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

type Step = 1 | 2 | 3
type CType = "" | "Poultry" | "Water" | "Generic"

const STEPS: { n: Step; title: string }[] = [
  { n: 1, title: "Owner account" },
  { n: 2, title: "Business Office" },
  { n: 3, title: "First company" },
]

const inputCls = "h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"

export default function RegisterPage() {
  const router = useRouter()
  const [step, setStep] = useState<Step>(1)
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [errorList, setErrorList] = useState<string[]>([])
  const [success, setSuccess] = useState(false)

  const [f, setF] = useState({
    // Step 1 — owner
    firstName: "", lastName: "", username: "", email: "", phoneNumber: "",
    password: "", confirmPassword: "",
    // Step 2 — business office
    businessOfficeName: "", currency: "GHS", country: "Ghana",
    // Step 3 — first company
    companyType: "" as CType, farmName: "", companyLocation: "",
  })
  const set = (k: keyof typeof f, v: string) => setF((p) => ({ ...p, [k]: v }))

  function validateStep1(): string | null {
    if (!f.firstName.trim() || !f.lastName.trim()) return "Please enter your first and last name."
    if (!USERNAME_RE.test(f.username.trim())) return "Username must be 3–30 characters: letters, numbers, dot, underscore, or hyphen (no spaces)."
    if (!f.email.trim()) return "Please enter your email address."
    if (!PHONE_RE.test(f.phoneNumber.replace(/[\s()-]/g, ""))) return "Enter a valid phone number including the country code (e.g. +233XXXXXXXXX)."
    if (f.password.length < 6) return "Password must be at least 6 characters."
    if (f.password !== f.confirmPassword) return "Passwords do not match."
    return null
  }
  function validateStep2(): string | null {
    if (!f.businessOfficeName.trim()) return "Please name your Business Office (e.g. “Evans Businesses”)."
    return null
  }
  function validateStep3(): string | null {
    if (f.companyType !== "Poultry" && f.companyType !== "Water" && f.companyType !== "Generic")
      return "Please choose your first company's type."
    if (!f.farmName.trim()) return "Please enter your first company's name."
    return null
  }

  function next() {
    setError(""); setErrorList([])
    const v = step === 1 ? validateStep1() : step === 2 ? validateStep2() : null
    if (v) { setError(v); return }
    setStep((s) => (s < 3 ? ((s + 1) as Step) : s))
  }
  function back() { setError(""); setErrorList([]); setStep((s) => (s > 1 ? ((s - 1) as Step) : s)) }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(""); setErrorList([])
    const v = validateStep3()
    if (v) { setError(v); return }

    setIsLoading(true)
    const result = await register({
      farmName: f.farmName.trim(),            // first company name
      username: f.username.trim(),
      email: f.email.trim(),
      password: f.password,
      firstName: f.firstName.trim(),
      lastName: f.lastName.trim(),
      phoneNumber: f.phoneNumber.replace(/[\s()-]/g, ""),
      companyType: f.companyType as "Poultry" | "Water" | "Generic",
      roles: ["Admin"], // the registrant is the Business Office owner/admin
      businessOfficeName: f.businessOfficeName.trim(),
      businessOfficeCurrency: f.currency.trim() || undefined,
      businessOfficeCountry: f.country.trim() || undefined,
    })

    if (result.success) {
      // Persist the Business Office name so the headquarters page shows it.
      try { localStorage.setItem("businessOfficeName", f.businessOfficeName.trim()) } catch {}
      setSuccess(true)
      setTimeout(() => router.push("/login"), 1800)
    } else {
      setError(result.message || "Registration failed. Please try again.")
      setErrorList(flattenErrors(result.errors))
      // Validation errors usually belong to step 1 (account); send the user back.
      setStep(1)
    }
    setIsLoading(false)
  }

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 p-4">
        <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md w-full text-center">
          <div className="mb-6 flex justify-center"><div className="text-6xl">🎉</div></div>
          <h2 className="text-2xl font-bold text-slate-900 mb-3">Business Office created!</h2>
          <p className="text-slate-500 mb-2">Your account, <span className="font-medium">{f.businessOfficeName.trim() || "Business Office"}</span>, and your first company are ready.</p>
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

      {/* Right Panel - Wizard */}
      <div className="w-full lg:w-1/2 bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center p-8">
        <div className="w-full max-w-md">
          <Link href="/login" className="inline-flex items-center gap-2 text-orange-400 hover:text-orange-300 mb-6 transition-colors">
            <ChevronLeft className="w-5 h-5" /><span className="font-medium">Back to login</span>
          </Link>

          {/* Stepper */}
          <div className="flex items-center justify-between mb-6">
            {STEPS.map((s, i) => (
              <div key={s.n} className="flex items-center flex-1 last:flex-none">
                <div className="flex flex-col items-center">
                  <div className={`flex h-8 w-8 items-center justify-center rounded-full text-sm font-semibold ${
                    step > s.n ? "bg-emerald-500 text-white" : step === s.n ? "bg-orange-500 text-white" : "bg-slate-700 text-slate-400"}`}>
                    {step > s.n ? <Check className="h-4 w-4" /> : s.n}
                  </div>
                  <span className={`mt-1 text-[10px] ${step === s.n ? "text-orange-300" : "text-slate-400"}`}>{s.title}</span>
                </div>
                {i < STEPS.length - 1 && <div className={`h-0.5 flex-1 mx-2 ${step > s.n ? "bg-emerald-500" : "bg-slate-700"}`} />}
              </div>
            ))}
          </div>

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
            {/* STEP 1 — Owner account */}
            {step === 1 && (
              <>
                <div className="text-center mb-2"><h2 className="text-xl font-bold text-white">Create your owner account</h2></div>
                <div className="grid grid-cols-2 gap-3">
                  <Input placeholder="First name" value={f.firstName} onChange={(e) => set("firstName", e.target.value)} className={inputCls} disabled={isLoading} />
                  <Input placeholder="Last name" value={f.lastName} onChange={(e) => set("lastName", e.target.value)} className={inputCls} disabled={isLoading} />
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
              </>
            )}

            {/* STEP 2 — Business Office */}
            {step === 2 && (
              <>
                <div className="text-center mb-2">
                  <h2 className="text-xl font-bold text-white">Name your Business Office</h2>
                  <p className="text-sm text-slate-300">Your headquarters that holds all your companies.</p>
                </div>
                <Input placeholder="Business Office name (e.g. Evans Businesses)" value={f.businessOfficeName} onChange={(e) => set("businessOfficeName", e.target.value)} className={inputCls} disabled={isLoading} />
                <div className="grid grid-cols-2 gap-3">
                  <Input placeholder="Default currency (e.g. GHS)" value={f.currency} onChange={(e) => set("currency", e.target.value)} className={inputCls} disabled={isLoading} />
                  <Input placeholder="Country" value={f.country} onChange={(e) => set("country", e.target.value)} className={inputCls} disabled={isLoading} />
                </div>
              </>
            )}

            {/* STEP 3 — First company */}
            {step === 3 && (
              <>
                <div className="text-center mb-2">
                  <h2 className="text-xl font-bold text-white">Create your first company</h2>
                  <p className="text-sm text-slate-300">You can add more from the Business Office anytime.</p>
                </div>
                <div className="grid grid-cols-3 gap-2">
                  {([
                    { value: "Poultry", emoji: "🐔", title: "Poultry" },
                    { value: "Water", emoji: "💧", title: "Water" },
                    { value: "Generic", emoji: "🏪", title: "Generic" },
                  ] as const).map((opt) => {
                    const selected = f.companyType === opt.value
                    return (
                      <button key={opt.value} type="button" onClick={() => set("companyType", opt.value)} disabled={isLoading} aria-pressed={selected}
                        className={`p-3 rounded-lg border-2 text-center transition-all ${selected ? "border-orange-500 bg-orange-500/10 ring-2 ring-orange-500/40" : "border-slate-600 bg-slate-700/30 hover:border-slate-500"} disabled:opacity-50`}>
                        <div className="text-2xl mb-1">{opt.emoji}</div>
                        <div className="text-xs font-semibold text-white">{opt.title}</div>
                      </button>
                    )
                  })}
                </div>
                <Input placeholder="Company name (e.g. Great Favour Water Co.)" value={f.farmName} onChange={(e) => set("farmName", e.target.value)} className={inputCls} disabled={isLoading} />
                <Input placeholder="Location (optional)" value={f.companyLocation} onChange={(e) => set("companyLocation", e.target.value)} className={inputCls} disabled={isLoading} />
              </>
            )}

            {/* Nav buttons */}
            <div className="flex items-center gap-3 pt-2">
              {step > 1 && (
                <Button type="button" variant="outline" onClick={back} disabled={isLoading} className="h-12 flex-1 border-slate-600 bg-transparent text-white hover:bg-slate-700">
                  <ChevronLeft className="w-4 h-4 mr-1" /> Back
                </Button>
              )}
              {step < 3 ? (
                <Button type="button" onClick={next} disabled={isLoading} className="h-12 flex-1 bg-orange-500 hover:bg-orange-600 text-white font-medium">
                  Next <ChevronRight className="w-4 h-4 ml-1" />
                </Button>
              ) : (
                <Button type="submit" disabled={isLoading} className="h-12 flex-1 bg-orange-500 hover:bg-orange-600 text-white font-medium">
                  {isLoading ? "Creating…" : "Create Business Office"}
                </Button>
              )}
            </div>

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

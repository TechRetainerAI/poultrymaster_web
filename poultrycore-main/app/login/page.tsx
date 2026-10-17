"use client"

import type React from "react"

import { useState } from "react"
import Image from "next/image"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Eye, EyeOff, Lock, User, Check } from "lucide-react"
import { login } from "@/lib/api/auth"
import Link from "next/link"
import { SuccessModal } from "@/components/auth/success-modal"
import { FarmIllustration } from "@/components/login/farm-illustration"
import { useAuthStore } from "@/lib/store/auth-store"

export default function LoginPage() {
  const router = useRouter()
  const [showPassword, setShowPassword] = useState(false)
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [rememberMe, setRememberMe] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [showSuccess, setShowSuccess] = useState(false)
  // Home route resolved from /Companies/mine after a successful login. Used by
  // the SuccessModal's "Go to Dashboard" button so Water/Generic signups don't
  // land on the Poultry dashboard.
  const [postLoginHome, setPostLoginHome] = useState<string>("/dashboard")

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    const result = await login({
      username,
      password,
      rememberMe,
    })

    if (result.success) {
      // Check if 2FA is required
      const requires2FA = result.data?.requiresTwoFactor || result.data?.RequiresTwoFactor
      console.log("[Login] Checking 2FA requirement:", requires2FA)
      
      if (requires2FA) {
        // Handle both case variations for userId and userName
        const userId = result.data?.userId || result.data?.UserId
        const userName = result.data?.userName || result.data?.UserName || result.data?.username || result.data?.Username
        
        console.log("[Login] Redirecting to 2FA page with:", {
          userId,
          userName
        })
        
        // Store employee info temporarily for 2FA flow
        if (result.data?.isStaff !== undefined || result.data?.IsStaff !== undefined) {
          const isStaff = result.data?.isStaff || result.data?.IsStaff || false
          localStorage.setItem("isStaff", String(isStaff))
        }
        
        // Redirect to 2FA page
        router.push(`/login-2fa?userId=${userId}&userName=${encodeURIComponent(userName || '')}`)
        return
      }
      
      console.log("[Login] No 2FA required, showing success modal")

      // Check if user is an employee and log it
      const isStaff = localStorage.getItem("isStaff") === "true"
      if (isStaff) {
        console.log("[Login] Employee login successful")
      } else {
        console.log("[Login] Admin login successful")
      }

      // Everyone lands in the company-neutral Business Office; no company is
      // auto-selected. The user picks a company from the BO selector / Companies
      // page, which sets the active context. Username-or-email resolution and all
      // account/organization lookup now live in the Login API — the client only
      // sends the credential + password and trusts the backend.
      try {
        useAuthStore.getState().clearActiveCompany()
      } catch {}
      setPostLoginHome("/business-office")

      setShowSuccess(true)
    } else {
      // Show user-friendly error message
      let errorMessage = result.message || "Login failed. Please try again."
      
      // Keep timeout / proxy diagnostics verbatim (multiline). Only simplify short credential errors.
      const isDiagnostic =
        errorMessage.includes("Login flow:") ||
        errorMessage.includes("timed out") ||
        errorMessage.includes("PROXY_UPSTREAM_TIMEOUT")
      if (
        !isDiagnostic &&
        (errorMessage.includes("not found") || errorMessage.includes("doesnot exist"))
      ) {
        errorMessage =
          "Username or email not found. Please verify your credentials or contact your administrator."
      } else if (!isDiagnostic && errorMessage.includes("Invalid password")) {
        errorMessage = "Invalid password. Please check your password and try again."
      }
      
      setError(errorMessage)
      console.error("[Login] Login failed:", result)
    }

    setIsLoading(false)
  }

  const handleSuccessClose = () => {
    setShowSuccess(false)
    router.push(postLoginHome)
  }

  return (
    <>
      <div className="min-h-screen flex">
        {/* Left Panel - Illustration */}
        <div className="relative hidden lg:flex lg:w-1/2 items-center justify-center overflow-hidden bg-gradient-to-b from-orange-50/60 via-white to-white p-12">
          {/* soft corner wash, keeps the panel from reading as a blank sheet */}
          <div className="pointer-events-none absolute -left-24 -top-24 h-72 w-72 rounded-full bg-orange-100/50 blur-3xl" />
          <div className="pointer-events-none absolute -bottom-32 -right-16 h-80 w-80 rounded-full bg-emerald-100/40 blur-3xl" />

          <div className="relative w-full max-w-md">
            {/* System Name */}
            <div className="mb-6">
              <h1 className="mb-2 text-4xl font-bold tracking-tight text-slate-900">VisibilityCore</h1>
              <p className="text-slate-600">Farm Management System</p>
            </div>

            <FarmIllustration className="h-80 w-full" />

            {/* Grounds the panel with what the product actually does */}
            <ul className="mt-6 space-y-3">
              {[
                "Track production, stock and sales in one place",
                "Costs and expenses reconciled automatically",
                "Every company in your organisation, one login",
              ].map((line) => (
                <li key={line} className="flex items-start gap-3 text-sm text-slate-600">
                  <Check className="mt-0.5 h-4 w-4 shrink-0 text-orange-500" aria-hidden="true" />
                  <span>{line}</span>
                </li>
              ))}
            </ul>
          </div>
        </div>

        {/* Right Panel - Login Form */}
        <div className="w-full lg:w-1/2 bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center p-8">
          <div className="w-full max-w-md">
            {/* Logo */}
            <div className="flex justify-center mb-8">
              <div className="w-16 h-16 bg-white/10 rounded-full flex items-center justify-center shadow-lg">
                <Image
                  src="/logo.png"
                  alt="VisibilityCore logo"
                  width={56}
                  height={56}
                  className="object-contain"
                  priority
                />
              </div>
            </div>

            {/* Title */}
            <div className="text-center mb-8">
              <h1 className="text-3xl font-bold text-white mb-2">Sign In</h1>
            </div>

            {/* Error Message */}
            {error && (
              <div className="mb-6 p-4 bg-red-900/20 border border-red-500/30 rounded-lg max-h-72 overflow-y-auto text-left">
                <p className="text-sm text-red-300 whitespace-pre-line break-words">{error}</p>
              </div>
            )}

            {/* Login Form */}
            <form onSubmit={handleSubmit} className="space-y-6">
              {/* Username or email — the Login API resolves either one */}
              <div className="space-y-2">
                <div className="relative">
                  <User className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-300" />
                  <Input
                    id="username"
                    type="text"
                    placeholder="Username or email"
                    autoComplete="username"
                    value={username}
                    onChange={(e) => setUsername(e.target.value)}
                    className="h-12 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500 pl-10"
                    required
                    disabled={isLoading}
                  />
                </div>
              </div>

              {/* Password Field */}
              <div className="space-y-2">
                <div className="relative">
                  <Lock className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-300" />
                  <Input
                    id="password"
                    type={showPassword ? "text" : "password"}
                    placeholder="Password"
                    value={password}
                    onChange={(e) => setPassword(e.target.value)}
                    className="h-12 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500 pl-10 pr-12"
                    required
                    disabled={isLoading}
                  />
                  <button
                    type="button"
                    onClick={() => setShowPassword(!showPassword)}
                    className="absolute right-2 top-1/2 inline-flex h-8 w-8 -translate-y-1/2 items-center justify-center rounded-md border border-slate-500 bg-slate-600/60 text-slate-200 hover:bg-slate-500/70 hover:text-white transition-colors"
                    aria-label={showPassword ? "Hide password" : "Show password"}
                    disabled={isLoading}
                  >
                    {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                  </button>
                </div>
              </div>

              {/* Remember Me & Forgot Password */}
              <div className="flex items-center justify-between">
                <div className="flex items-center gap-2">
                  <Checkbox
                    id="remember"
                    checked={rememberMe}
                    onCheckedChange={(checked) => setRememberMe(checked as boolean)}
                    className="border-slate-500 data-[state=checked]:bg-orange-500 data-[state=checked]:border-orange-500"
                    disabled={isLoading}
                  />
                  <Label htmlFor="remember" className="text-sm font-medium text-white cursor-pointer">
                    Remember me
                  </Label>
                </div>
                <Link
                  href="/forgot-password"
                  className="text-sm font-medium text-orange-400 hover:text-orange-300 transition-colors"
                >
                  Forgot password?
                </Link>
              </div>

              {/* Login Button */}
              <Button
                type="submit"
                className="w-full h-12 bg-orange-500 hover:bg-orange-600 text-white font-medium text-base rounded-lg transition-colors disabled:opacity-50"
                disabled={isLoading}
              >
                {isLoading ? "Signing in..." : "Sign In"}
              </Button>

              {/* Sign Up Link */}
              <div className="text-center">
                <p className="text-sm text-slate-300">
                  Not registered?{" "}
                  <Link href="/register" className="font-medium text-orange-400 hover:text-orange-300 transition-colors">
                    Create an account
                  </Link>
                </p>
              </div>
            </form>
          </div>
        </div>
      </div>

      {showSuccess && (
        <SuccessModal
          title="Login Successful!"
          message="You have successfully logged in to your account"
          onClose={handleSuccessClose}
          buttonText="Go to Dashboard"
        />
      )}
    </>
  )
}

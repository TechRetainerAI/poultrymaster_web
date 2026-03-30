"use client"

import type React from "react"

import { useState } from "react"
import Image from "next/image"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Checkbox } from "@/components/ui/checkbox"
import { Eye, EyeOff, Lock, User } from "lucide-react"
import { login } from "@/lib/api/auth"
import Link from "next/link"
import { SuccessModal } from "@/components/auth/success-modal"

export default function LoginPage() {
  const router = useRouter()
  const [showPassword, setShowPassword] = useState(false)
  const [username, setUsername] = useState("")
  const [password, setPassword] = useState("")
  const [rememberMe, setRememberMe] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [showSuccess, setShowSuccess] = useState(false)

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
    router.push("/dashboard")
  }

  return (
    <>
      <div className="min-h-screen flex">
        {/* Left Panel - Illustration */}
        <div className="hidden lg:flex lg:w-1/2 bg-white items-center justify-center p-12">
          <div className="max-w-md text-center">
            {/* System Name */}
            <div className="mb-8">
              <h1 className="text-4xl font-bold text-slate-900 mb-2">Poultry Master</h1>
              <p className="text-slate-600">Farm Management System</p>
            </div>
            
            {/* Farmer Illustration */}
            <div className="relative">
              {/* Real farmer image - displayed directly without card */}
              <img 
                src="/farmer-illustration.png" 
                alt="Farmer with watermelon - Poultry Master" 
                className="w-full h-96 object-contain"
              />
            </div>
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
                  alt="Poultry Master logo"
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
              {/* Username Field */}
              <div className="space-y-2">
                <div className="relative">
                  <User className="pointer-events-none absolute left-3 top-1/2 h-4 w-4 -translate-y-1/2 text-slate-300" />
                  <Input
                    id="username"
                    type="text"
                    placeholder="Username"
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

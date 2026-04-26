"use client"

import { useState, useEffect, Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Button } from "@/components/ui/button"
import { Label } from "@/components/ui/label"
import { AuthService } from "@/lib/services/auth.service"
import { useAuthStore } from "@/lib/store/auth-store"
import { Shield } from "lucide-react"

function Login2FAForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const { login } = useAuthStore()
  
  const userId = searchParams.get("userId")
  const userName = searchParams.get("userName")
  
  const [otpCode, setOtpCode] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [resending, setResending] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!otpCode || otpCode.length !== 6) {
      setError("Please enter a valid 6-digit OTP code")
      return
    }

    if (!userId || !userName) {
      setError("Missing required information. Please try logging in again.")
      return
    }

    setIsLoading(true)
    setError("")

    try {
      const response = await AuthService.login2FA({
        userId,
        userName,
        otpCode,
      })

      // Store auth data
      login(
        response.token,
        response.refreshToken,
        response.user
      )

      // Ensure employee information is stored (should already be done in AuthService, but double-check)
      if (typeof window !== 'undefined') {
        const isStaff = response.user?.isStaff || false
        localStorage.setItem("isStaff", String(isStaff))
        console.log("[2FA Login] Employee status stored - isStaff:", isStaff)
      }

      // Redirect to dashboard
      router.push("/dashboard")
    } catch (err: any) {
      setError(err?.response?.data?.message || "Invalid OTP code. Please try again.")
    } finally {
      setIsLoading(false)
    }
  }

  const handleResendCode = async () => {
    setResending(true)
    setError("")
    
    try {
      // TODO: Implement resend OTP API call
      // await AuthService.resendOTP(userId)
      alert("New OTP code sent to your email")
    } catch (err) {
      setError("Failed to resend OTP code. Please try again.")
    } finally {
      setResending(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="mx-auto mb-4 w-12 h-12 bg-blue-100 rounded-full flex items-center justify-center">
            <Shield className="w-6 h-6 text-blue-600" />
          </div>
          <CardTitle className="text-2xl font-bold">Two-Factor Authentication</CardTitle>
          <CardDescription>
            Enter the 6-digit code sent to your email to complete login
          </CardDescription>
        </CardHeader>
        <CardContent>
          <form onSubmit={handleSubmit} className="space-y-4">
            <div className="space-y-2">
              <Label htmlFor="otp">OTP Code</Label>
              <Input
                id="otp"
                type="text"
                placeholder="000000"
                value={otpCode}
                onChange={(e) => {
                  const value = e.target.value.replace(/\D/g, "").slice(0, 6)
                  setOtpCode(value)
                  setError("")
                }}
                className="text-center text-2xl tracking-widest font-mono"
                maxLength={6}
                disabled={isLoading}
                autoFocus
              />
              <p className="text-sm text-slate-500">
                Please check your email for the verification code
              </p>
            </div>

            {error && (
              <div className="p-3 text-sm text-red-600 bg-red-50 border border-red-200 rounded-md">
                {error}
              </div>
            )}

            <Button
              type="submit"
              className="w-full"
              disabled={isLoading || otpCode.length !== 6}
            >
              {isLoading ? "Verifying..." : "Verify & Login"}
            </Button>

            <div className="text-center">
              <button
                type="button"
                onClick={handleResendCode}
                disabled={resending}
                className="text-sm text-blue-600 hover:text-blue-700 disabled:text-slate-400"
              >
                {resending ? "Resending..." : "Resend Code"}
              </button>
            </div>

            <div className="text-center">
              <button
                type="button"
                onClick={() => router.push("/login")}
                className="text-sm text-slate-600 hover:text-slate-700"
              >
                Back to Login
              </button>
            </div>
          </form>
        </CardContent>
      </Card>
    </div>
  )
}

export default function Login2FAPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <div className="text-slate-600">Loading...</div>
      </div>
    }>
      <Login2FAForm />
    </Suspense>
  )
}

"use client"

import type React from "react"

import { useState, useEffect } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Eye, EyeOff, ChevronLeft } from "lucide-react"
import { resetPassword } from "@/lib/api/auth"
import Link from "next/link"
import { SuccessModal } from "@/components/auth/success-modal"

export default function ResetPasswordPage() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const [showPassword, setShowPassword] = useState(false)
  const [showConfirmPassword, setShowConfirmPassword] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [showSuccess, setShowSuccess] = useState(false)

  const [formData, setFormData] = useState({
    email: "",
    token: "",
    password: "",
    confirmPassword: "",
  })

  useEffect(() => {
    // Get email and token from URL params
    const emailParam = searchParams.get("email")
    const tokenParam = searchParams.get("token")
    
    if (emailParam) {
      setFormData((prev) => ({ ...prev, email: emailParam }))
    }
    
    if (tokenParam) {
      // Token comes URL encoded, decode it
      const decodedToken = decodeURIComponent(tokenParam)
      setFormData((prev) => ({ ...prev, token: decodedToken }))
    }
  }, [searchParams])

  const handleChange = (field: string, value: string) => {
    setFormData((prev) => ({ ...prev, [field]: value }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")

    // Validate passwords match
    if (formData.password !== formData.confirmPassword) {
      setError("Passwords do not match")
      return
    }

    setIsLoading(true)

    const result = await resetPassword(formData)

    if (result.success) {
      setShowSuccess(true)
    } else {
      setError(result.message || "Password reset failed. Please try again.")
    }

    setIsLoading(false)
  }

  const handleSuccessClose = () => {
    setShowSuccess(false)
    router.push("/login")
  }

  return (
    <>
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 p-4">
        <div className="w-full max-w-md p-8 bg-white rounded-2xl shadow-sm">
          {/* Back Button */}
          <Link
            href="/forgot-password"
            className="inline-flex items-center gap-2 text-slate-600 hover:text-slate-900 mb-8 transition-colors"
          >
            <ChevronLeft className="w-5 h-5" />
            <span className="font-medium">Back</span>
          </Link>

          {/* Title */}
          <div className="mb-8">
            <h2 className="text-3xl font-bold text-slate-900 mb-3">Reset Password</h2>
            <p className="text-slate-500 leading-relaxed">
              Enter the code sent to your email and create a new password.
            </p>
          </div>

          {/* Error Message */}
          {error && (
            <div className="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
              <p className="text-sm text-red-600">{error}</p>
            </div>
          )}

          {/* Reset Password Form */}
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Email Field (read-only) */}
            <div className="space-y-2">
              <Label htmlFor="email" className="text-sm font-medium text-blue-600">
                Email Address
              </Label>
              <Input
                id="email"
                type="email"
                value={formData.email}
                onChange={(e) => handleChange("email", e.target.value)}
                className="h-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500 bg-slate-50"
                required
                disabled={isLoading}
              />
            </div>

            {/* Token/Code Field */}
            <div className="space-y-2">
              <Label htmlFor="token" className="text-sm font-medium text-blue-600">
                Reset Code
              </Label>
              <Input
                id="token"
                type="text"
                placeholder="Enter the code from your email"
                value={formData.token}
                onChange={(e) => handleChange("token", e.target.value)}
                className="h-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* New Password Field */}
            <div className="space-y-2">
              <Label htmlFor="password" className="text-sm font-medium text-blue-600">
                New Password
              </Label>
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="Create a new password"
                  value={formData.password}
                  onChange={(e) => handleChange("password", e.target.value)}
                  className="h-12 pr-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500"
                  required
                  disabled={isLoading}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 transition-colors"
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  disabled={isLoading}
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            {/* Confirm Password Field */}
            <div className="space-y-2">
              <Label htmlFor="confirmPassword" className="text-sm font-medium text-blue-600">
                Confirm Password
              </Label>
              <div className="relative">
                <Input
                  id="confirmPassword"
                  type={showConfirmPassword ? "text" : "password"}
                  placeholder="Confirm your new password"
                  value={formData.confirmPassword}
                  onChange={(e) => handleChange("confirmPassword", e.target.value)}
                  className="h-12 pr-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500"
                  required
                  disabled={isLoading}
                />
                <button
                  type="button"
                  onClick={() => setShowConfirmPassword(!showConfirmPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-600 transition-colors"
                  aria-label={showConfirmPassword ? "Hide password" : "Show password"}
                  disabled={isLoading}
                >
                  {showConfirmPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            {/* Reset Password Button */}
            <Button
              type="submit"
              className="w-full h-12 bg-blue-600 hover:bg-blue-700 text-white font-medium text-base rounded-lg transition-colors disabled:opacity-50"
              disabled={isLoading}
            >
              {isLoading ? "Resetting..." : "Reset Password"}
            </Button>
          </form>
        </div>
      </div>

      {/* Success Modal */}
      {showSuccess && (
        <SuccessModal
          title="Password Update Successfully"
          message="Your password has been update successfully"
          onClose={handleSuccessClose}
          buttonText="Back to Login"
        />
      )}
    </>
  )
}

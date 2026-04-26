"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { ChevronLeft } from "lucide-react"
import { forgotPassword } from "@/lib/api/auth"
import Link from "next/link"

export default function ForgotPasswordPage() {
  const router = useRouter()
  const [email, setEmail] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState(false)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    const result = await forgotPassword({ email })

    if (result.success) {
      setSuccess(true)
      // Redirect to reset password page with email
      setTimeout(() => {
        router.push(`/reset-password?email=${encodeURIComponent(email)}`)
      }, 2000)
    } else {
      setError(result.message || "Failed to send reset code. Please try again.")
    }

    setIsLoading(false)
  }

  if (success) {
    return (
      <div className="min-h-screen flex">
        {/* Left Panel - Illustration */}
        <div className="hidden lg:flex lg:w-1/2 bg-white items-center justify-center p-12">
          <div className="max-w-md text-center">
            {/* System Name */}
            <div className="mb-8">
              <h1 className="text-4xl font-bold text-slate-900 mb-2">Poultry Core</h1>
              <p className="text-slate-600">Farm Management System</p>
            </div>
            
            {/* Farmer Illustration */}
            <div className="relative">
              {/* Real farmer image - displayed directly without card */}
              <img 
                src="/farmer-illustration.png" 
                alt="Farmer with watermelon - Poultry Core" 
                className="w-full h-96 object-contain"
              />
            </div>
          </div>
        </div>

        {/* Right Panel - Success Message */}
        <div className="w-full lg:w-1/2 bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center p-8">
          <div className="w-full max-w-md text-center">
            {/* Logo */}
            <div className="flex justify-center mb-8">
              <div className="w-12 h-12 bg-yellow-400 rounded-full flex items-center justify-center">
                <span className="text-2xl">🏢</span>
              </div>
            </div>

            {/* Success Icon */}
            <div className="flex justify-center mb-8">
              <div className="text-6xl">📧</div>
            </div>

            {/* Success Message */}
            <div className="mb-8">
              <h2 className="text-3xl font-bold text-white mb-3">Check Your Email</h2>
              <p className="text-slate-300 leading-relaxed">
                We've sent a reset code to your email address. Please check your inbox and follow the instructions to reset your password.
              </p>
            </div>

            {/* Back to Login Button */}
            <Link href="/login">
              <Button className="w-full h-12 bg-orange-500 hover:bg-orange-600 text-white font-medium text-base rounded-lg transition-colors">
                Back to Login
              </Button>
            </Link>
          </div>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen flex">
      {/* Left Panel - Illustration */}
      <div className="hidden lg:flex lg:w-1/2 bg-white items-center justify-center p-12">
        <div className="max-w-md text-center">
          {/* System Name */}
          <div className="mb-8">
            <h1 className="text-4xl font-bold text-slate-900 mb-2">Poultry Core</h1>
            <p className="text-slate-600">Farm Management System</p>
          </div>
          
          {/* Farmer Illustration */}
          <div className="relative">
            {/* Real farmer image - displayed directly without card */}
            <img 
              src="/farmer-illustration.png" 
              alt="Farmer with watermelon - Poultry Core" 
              className="w-full h-96 object-contain"
            />
          </div>
        </div>
      </div>

      {/* Right Panel - Forgot Password Form */}
      <div className="w-full lg:w-1/2 bg-gradient-to-br from-slate-800 to-slate-900 flex items-center justify-center p-8">
        <div className="w-full max-w-md">
          {/* Back Button */}
          <Link
            href="/login"
            className="inline-flex items-center gap-2 text-orange-400 hover:text-orange-300 mb-6 transition-colors"
          >
            <ChevronLeft className="w-5 h-5" />
            <span className="font-medium">Back</span>
          </Link>

          {/* Logo */}
          <div className="flex justify-center mb-8">
            <div className="w-12 h-12 bg-yellow-400 rounded-full flex items-center justify-center">
              <span className="text-2xl">🏢</span>
            </div>
          </div>

          {/* Title */}
          <div className="text-center mb-8">
            <h1 className="text-3xl font-bold text-white mb-2">Forgot Password</h1>
            <p className="text-slate-300 leading-relaxed">
              Enter your registered email address. We'll send you a code to reset your password.
            </p>
          </div>

          {/* Error Message */}
          {error && (
            <div className="mb-6 p-4 bg-red-900/20 border border-red-500/30 rounded-lg">
              <p className="text-sm text-red-300">{error}</p>
            </div>
          )}

          {/* Forgot Password Form */}
          <form onSubmit={handleSubmit} className="space-y-6">
            {/* Email Field */}
            <div className="space-y-2">
              <Input
                id="email"
                type="email"
                placeholder="Enter your email address"
                value={email}
                onChange={(e) => setEmail(e.target.value)}
                className="h-12 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* Send OTP Button */}
            <Button
              type="submit"
              className="w-full h-12 bg-orange-500 hover:bg-orange-600 text-white font-medium text-base rounded-lg transition-colors disabled:opacity-50"
              disabled={isLoading}
            >
              {isLoading ? "Sending..." : "Send OTP"}
            </Button>

            {/* Login Link */}
            <div className="text-center">
              <p className="text-sm text-slate-300">
                Remember your password?{" "}
                <Link href="/login" className="font-medium text-orange-400 hover:text-orange-300 transition-colors">
                  Login
                </Link>
              </p>
            </div>
          </form>
        </div>
      </div>
    </div>
  )
}

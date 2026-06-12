"use client"

import type React from "react"
import { useState, useEffect, Suspense } from "react"
import { useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { confirmEmail } from "@/lib/api/auth"

function EmailConfirmationForm() {
  const searchParams = useSearchParams()
  const [email, setEmail] = useState("")
  const [token, setToken] = useState("")
  const [isLoading, setIsLoading] = useState(false)
  const [result, setResult] = useState<any>(null)
  const [error, setError] = useState("")

  useEffect(() => {
    // Auto-fill from URL params if present
    const emailParam = searchParams.get("email")
    const tokenParam = searchParams.get("token")
    
    if (emailParam) {
      setEmail(emailParam)
    }
    
    if (tokenParam) {
      const decodedToken = decodeURIComponent(tokenParam)
      setToken(decodedToken)
      
      // Auto-confirm if both email and token are present
      if (emailParam) {
        handleAutoConfirm(emailParam, decodedToken)
      }
    }
  }, [searchParams])

  const handleAutoConfirm = async (emailValue: string, tokenValue: string) => {
    setIsLoading(true)
    setError("")
    setResult(null)

    try {
      const response = await confirmEmail({ email: emailValue, token: tokenValue })
      setResult(response)
      
      if (!response.success) {
        setError(response.message || "Email confirmation failed")
      }
    } catch (err) {
      setError("An unexpected error occurred")
      setResult({ success: false, message: "An unexpected error occurred" })
    }

    setIsLoading(false)
  }

  const handleConfirmEmail = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setResult(null)
    setIsLoading(true)

    try {
      const response = await confirmEmail({ email, token })
      setResult(response)
      
      if (!response.success) {
        setError(response.message || "Email confirmation failed")
      }
    } catch (err) {
      setError("An unexpected error occurred")
      setResult({ success: false, message: "An unexpected error occurred" })
    }

    setIsLoading(false)
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 p-4">
      <div className="w-full max-w-md p-8 bg-white rounded-2xl shadow-sm">
        <div className="mb-8">
          <h2 className="text-3xl font-bold text-slate-900 mb-2">Test Email Confirmation</h2>
          <p className="text-slate-500">Test the email confirmation API endpoint</p>
        </div>

        <form onSubmit={handleConfirmEmail} className="space-y-6">
          <div className="space-y-2">
            <Label htmlFor="email" className="text-sm font-medium text-blue-600">
              Email Address
            </Label>
            <Input
              id="email"
              type="email"
              placeholder="your.email@example.com"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              className="h-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500"
              required
              disabled={isLoading}
            />
          </div>

          <div className="space-y-2">
            <Label htmlFor="token" className="text-sm font-medium text-blue-600">
              Confirmation Token
            </Label>
            <Input
              id="token"
              type="text"
              placeholder="Enter the confirmation token from your email"
              value={token}
              onChange={(e) => setToken(e.target.value)}
              className="h-12 border-blue-200 focus:border-blue-500 focus:ring-blue-500"
              required
              disabled={isLoading}
            />
          </div>

          <Button
            type="submit"
            className="w-full h-12 bg-blue-600 hover:bg-blue-700 text-white font-medium text-base rounded-lg transition-colors disabled:opacity-50"
            disabled={isLoading}
          >
            {isLoading ? "Confirming Email..." : "Confirm Email"}
          </Button>
        </form>

        {/* Error Message */}
        {error && (
          <div className="mt-6 p-4 bg-red-50 border border-red-200 rounded-lg">
            <p className="text-sm text-red-600">{error}</p>
          </div>
        )}

        {/* Success Message */}
        {result && result.success && (
          <div className="mt-6 p-4 bg-green-50 border border-green-200 rounded-lg">
            <p className="text-sm text-green-600">{result.message}</p>
          </div>
        )}

        {/* Result Display */}
        {result && (
          <div className="mt-6 p-4 bg-slate-50 border border-slate-200 rounded-lg">
            <h3 className="text-sm font-medium text-slate-700 mb-2">API Response:</h3>
            <pre className="text-xs text-slate-600 overflow-auto">
              {JSON.stringify(result, null, 2)}
            </pre>
          </div>
        )}
      </div>
    </div>
  )
}

export default function TestEmailConfirmationPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100">
        <div className="text-slate-600">Loading...</div>
      </div>
    }>
      <EmailConfirmationForm />
    </Suspense>
  )
}

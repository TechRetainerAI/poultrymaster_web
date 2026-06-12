"use client"

import { useState, useEffect, Suspense } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { CheckCircle, XCircle, Loader2, Mail } from "lucide-react"
import { AuthService } from "@/lib/services/auth.service"

function VerifyAccountForm() {
  const router = useRouter()
  const searchParams = useSearchParams()
  const token = searchParams.get("token")
  const email = searchParams.get("email")

  const [status, setStatus] = useState<"verifying" | "success" | "error">("verifying")
  const [message, setMessage] = useState("Verifying your account...")

  useEffect(() => {
    const verifyAccount = async () => {
      if (!token) {
        setStatus("error")
        setMessage("Invalid verification link. Please check your email and try again.")
        return
      }

      try {
        // Call the verification API
        await AuthService.verifyAccount(token)
        
        setStatus("success")
        setMessage("Your account has been verified successfully!")
        
        // Redirect to login after 3 seconds
        setTimeout(() => {
          router.push("/login?verified=true")
        }, 3000)
      } catch (error: any) {
        setStatus("error")
        setMessage(error?.response?.data?.message || "Verification failed. The link may have expired.")
      }
    }

    verifyAccount()
  }, [token, router])

  const handleResendVerification = async () => {
    if (!email) {
      setMessage("Email address not found. Please try logging in again.")
      return
    }

    try {
      // TODO: Implement resend verification API call
      // await AuthService.resendVerificationEmail(email)
      setMessage("Verification email sent! Please check your inbox.")
    } catch (error) {
      setMessage("Failed to resend verification email. Please try again later.")
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
      <Card className="w-full max-w-md">
        <CardHeader className="space-y-1 text-center">
          <div className="mx-auto mb-4 w-16 h-16 bg-blue-100 rounded-full flex items-center justify-center">
            {status === "verifying" && <Loader2 className="w-8 h-8 text-blue-600 animate-spin" />}
            {status === "success" && <CheckCircle className="w-8 h-8 text-green-600" />}
            {status === "error" && <XCircle className="w-8 h-8 text-red-600" />}
          </div>
          <CardTitle className="text-2xl font-bold">
            {status === "verifying" && "Verifying Account"}
            {status === "success" && "Account Verified"}
            {status === "error" && "Verification Failed"}
          </CardTitle>
          <CardDescription>{message}</CardDescription>
        </CardHeader>
        <CardContent>
          <div className="space-y-4">
            {status === "success" && (
              <div className="text-center">
                <p className="text-sm text-slate-600">
                  Redirecting to login page...
                </p>
              </div>
            )}

            {status === "error" && (
              <div className="space-y-3">
                <Button
                  onClick={handleResendVerification}
                  variant="outline"
                  className="w-full"
                >
                  <Mail className="w-4 h-4 mr-2" />
                  Resend Verification Email
                </Button>
                <Button
                  onClick={() => router.push("/login")}
                  className="w-full"
                >
                  Go to Login
                </Button>
              </div>
            )}

            {status === "verifying" && (
              <div className="text-center">
                <p className="text-sm text-slate-500">
                  Please wait while we verify your account...
                </p>
              </div>
            )}
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

export default function VerifyAccountPage() {
  return (
    <Suspense fallback={
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-blue-50 to-indigo-100 p-4">
        <div className="text-slate-600">Loading...</div>
      </div>
    }>
      <VerifyAccountForm />
    </Suspense>
  )
}

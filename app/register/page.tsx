"use client"

import type React from "react"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Eye, EyeOff, ChevronLeft } from "lucide-react"
import { InventoryLogo } from "@/components/auth/logo"
import { register } from "@/lib/api/auth"
import Link from "next/link"

export default function RegisterPage() {
  const router = useRouter()
  const [showPassword, setShowPassword] = useState(false)
  const [isLoading, setIsLoading] = useState(false)
  const [error, setError] = useState("")
  const [success, setSuccess] = useState(false)

  const [formData, setFormData] = useState({
    farmName: "",
    username: "",
    email: "",
    password: "",
    firstName: "",
    lastName: "",
    phoneNumber: "",
  })

  const handleChange = (field: string, value: string) => {
    setFormData((prev) => ({ ...prev, [field]: value }))
  }

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    setError("")
    setIsLoading(true)

    const result = await register({
      ...formData,
      roles: ["Admin"], // Person registering is the farm owner/admin
    })

    if (result.success) {
      setSuccess(true)
      // Redirect to login after 2 seconds
      setTimeout(() => {
        router.push("/login")
      }, 2000)
    } else {
      setError(result.message || "Registration failed. Please try again.")
    }

    setIsLoading(false)
  }

  if (success) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gradient-to-br from-slate-50 to-slate-100 p-4">
        <div className="bg-white rounded-2xl shadow-xl p-8 max-w-md w-full text-center">
          <div className="mb-6 flex justify-center">
            <div className="text-6xl">🎉</div>
          </div>
          <h2 className="text-2xl font-bold text-slate-900 mb-3">Registration Successful!</h2>
          <p className="text-slate-500 mb-8">Your account has been created successfully. Redirecting to login...</p>
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

      {/* Right Panel - Registration Form */}
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
            <h1 className="text-3xl font-bold text-white mb-2">Create Account</h1>
            <p className="text-slate-300">Please fill in your details to register</p>
          </div>

          {/* Error Message */}
          {error && (
            <div className="mb-6 p-4 bg-red-900/20 border border-red-500/30 rounded-lg">
              <p className="text-sm text-red-300">{error}</p>
            </div>
          )}

          {/* Registration Form */}
          <form onSubmit={handleSubmit} className="space-y-4">
            {/* Farm Name */}
            <div className="space-y-2">
              <Input
                id="farmName"
                type="text"
                placeholder="Farm Name"
                value={formData.farmName}
                onChange={(e) => handleChange("farmName", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* First Name and Last Name */}
            <div className="grid grid-cols-2 gap-4">
              <Input
                id="firstName"
                type="text"
                placeholder="First Name"
                value={formData.firstName}
                onChange={(e) => handleChange("firstName", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
              <Input
                id="lastName"
                type="text"
                placeholder="Last Name"
                value={formData.lastName}
                onChange={(e) => handleChange("lastName", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* Username */}
            <div className="space-y-2">
              <Input
                id="username"
                type="text"
                placeholder="Username"
                value={formData.username}
                onChange={(e) => handleChange("username", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* Email */}
            <div className="space-y-2">
              <Input
                id="email"
                type="email"
                placeholder="Email Address"
                value={formData.email}
                onChange={(e) => handleChange("email", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* Phone Number */}
            <div className="space-y-2">
              <Input
                id="phoneNumber"
                type="tel"
                placeholder="Phone Number"
                value={formData.phoneNumber}
                onChange={(e) => handleChange("phoneNumber", e.target.value)}
                className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500"
                required
                disabled={isLoading}
              />
            </div>

            {/* Password */}
            <div className="space-y-2">
              <div className="relative">
                <Input
                  id="password"
                  type={showPassword ? "text" : "password"}
                  placeholder="Password"
                  value={formData.password}
                  onChange={(e) => handleChange("password", e.target.value)}
                  className="h-10 bg-slate-700/50 border-slate-600 text-white placeholder:text-slate-400 focus:border-orange-500 focus:ring-orange-500 pr-12"
                  required
                  disabled={isLoading}
                />
                <button
                  type="button"
                  onClick={() => setShowPassword(!showPassword)}
                  className="absolute right-3 top-1/2 -translate-y-1/2 text-slate-400 hover:text-slate-300 transition-colors"
                  aria-label={showPassword ? "Hide password" : "Show password"}
                  disabled={isLoading}
                >
                  {showPassword ? <EyeOff className="w-5 h-5" /> : <Eye className="w-5 h-5" />}
                </button>
              </div>
            </div>

            {/* Register Button */}
            <Button
              type="submit"
              className="w-full h-12 bg-orange-500 hover:bg-orange-600 text-white font-medium text-base rounded-lg transition-colors disabled:opacity-50 mt-6"
              disabled={isLoading}
            >
              {isLoading ? "Creating Account..." : "Create Account"}
            </Button>

            {/* Login Link */}
            <div className="text-center">
              <p className="text-sm text-slate-300">
                Already have an account?{" "}
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

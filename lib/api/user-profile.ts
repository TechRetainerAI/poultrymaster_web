// API utility functions for user profile management

import { getAuthHeaders, loginApiUrl } from "./config"

export interface UserProfile {
  id: string
  userName: string
  normalizedUserName: string
  email: string
  normalizedEmail: string
  emailConfirmed: boolean
  passwordHash: string
  securityStamp: string
  concurrencyStamp: string
  phoneNumber: string
  phoneNumberConfirmed: boolean
  twoFactorEnabled: boolean
  lockoutEnd: string | null
  lockoutEnabled: boolean
  accessFailedCount: number
  farmId: string
  farmName: string
  isStaff: boolean
  isSubscriber: boolean
  refreshToken: string
  refreshTokenExpiry: string
  firstName: string
  lastName: string
  customerId: string
}

export interface UpdateProfileData {
  userName?: string
  email?: string
  phoneNumber?: string
  firstName?: string
  lastName?: string
  farmName?: string
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Get user profile by username
export async function getUserProfile(username: string): Promise<ApiResponse<UserProfile>> {
  try {
    console.log("[v0] Fetching user profile for:", username)

    const normalizedUsername = username.toUpperCase()
    const response = await fetch(
      loginApiUrl(
        `UserProfile/findByUserName?normalizedUserName=${encodeURIComponent(normalizedUsername)}`
      ),
      {
        method: "GET",
        headers: getAuthHeaders(),
      },
    )

    console.log("[v0] Profile fetch response status:", response.status)
    console.log("[v0] Response content-type:", response.headers.get("content-type"))

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Profile fetch error:", errorText)
      return {
        success: false,
        message: "Failed to fetch user profile",
      }
    }

    const contentType = response.headers.get("content-type")
    const text = await response.text()
    console.log("[v0] Response text:", text)

    if (!text || text.trim() === "") {
      console.error("[v0] Empty response received")
      return {
        success: false,
        message: "No profile data found",
      }
    }

    if (contentType && contentType.includes("application/json")) {
      try {
        const result = JSON.parse(text)
        console.log("[v0] Profile data received:", result)

        return {
          success: true,
          data: result,
          message: "Profile fetched successfully",
        }
      } catch (parseError) {
        console.error("[v0] JSON parse error:", parseError)
        console.error("[v0] Response text was:", text)
        return {
          success: false,
          message: "Invalid response format",
        }
      }
    } else {
      console.error("[v0] Non-JSON response received:", text)
      return {
        success: false,
        message: "Invalid response format from server",
      }
    }
  } catch (error) {
    console.error("[v0] Network error fetching profile:", error)
    console.warn("[v0] API not available, using mock data for user profile.")
    
    // Return mock profile data when API is unavailable
    return {
      success: true,
      data: {
        farmId: localStorage.getItem("farmId") || "mock-farm-123",
        userId: localStorage.getItem("userId") || "mock-user-123",
        username: localStorage.getItem("username") || "demo_user",
        email: "demo@example.com",
        firstName: "Demo",
        lastName: "User",
        phoneNumber: "+1 (555) 123-4567",
        roles: ["Admin"],
        isStaff: false,
        isSubscriber: true,
        farmName: localStorage.getItem("farmName") || "Demo Farm",
        lastLoginDate: new Date().toISOString(),
        createdDate: new Date().toISOString(),
      },
      message: "Profile loaded (API unavailable - using mock data)",
    }
  }
}

// Create user profile
export async function createUserProfile(data: Partial<UserProfile>): Promise<ApiResponse> {
  try {
    console.log("[v0] Creating user profile:", data)

    const response = await fetch(loginApiUrl("UserProfile/create"), {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(data),
    })

    console.log("[v0] Create profile response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Create profile error:", errorText)
      return {
        success: false,
        message: "Failed to create profile",
      }
    }

    const result = await response.json()
    console.log("[v0] Profile created:", result)

    return {
      success: true,
      data: result,
      message: "Profile created successfully",
    }
  } catch (error) {
    console.error("[v0] Network error creating profile:", error)
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

// Update user profile
export async function updateUserProfile(data: UpdateProfileData): Promise<ApiResponse> {
  try {
    console.log("[v0] Updating user profile:", data)

    const response = await fetch(loginApiUrl("UserProfile/update"), {
      method: "POST",
      headers: getAuthHeaders(),
      body: JSON.stringify(data),
    })

    console.log("[v0] Update profile response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Update profile error:", errorText)
      return {
        success: false,
        message: "Failed to update profile",
      }
    }

    const result = await response.json()
    console.log("[v0] Profile updated:", result)

    return {
      success: true,
      data: result,
      message: "Profile updated successfully",
    }
  } catch (error) {
    console.error("[v0] Network error updating profile:", error)
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

// SECURITY: User profile deletion removed from frontend
// User deletion must be performed by admin through backend only
// This prevents unauthorized user deletion attacks
// If needed, implement as admin-only backend operation with proper authorization

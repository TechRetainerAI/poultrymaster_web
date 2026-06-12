import { DEFAULT_LOGIN_API_ORIGIN } from "@/lib/api/default-api-hosts"
import { getAuthHeaders } from "./config"


function buildAdminApiUrl(endpoint: string): string {
  const IS_BROWSER = typeof window !== 'undefined'
  const cleanEndpoint = endpoint.startsWith('/') ? endpoint : `/${endpoint}`
  
  // LoginAPI base URL (User Management API)
  // Prefer environment variable, fall back to production host
  const backendAdminApiUrl =
    process.env.NEXT_PUBLIC_LOGIN_API_URL ||
    process.env.NEXT_PUBLIC_ADMIN_API_URL ||
    DEFAULT_LOGIN_API_ORIGIN
  
  if (IS_BROWSER) {
    // In the browser we always go through the Next.js proxy to avoid CORS
    const proxyPath = cleanEndpoint.replace(/^\/api\//, '/')
    console.log("[Admin API] Using proxy for backend API:", `/api/proxy${proxyPath}`)
    return `/api/proxy${proxyPath}`
  } else {
    // Server-side: use direct backend API URL
    const apiPath = cleanEndpoint.startsWith('/api/') ? cleanEndpoint : `/api${cleanEndpoint}`
    const fullUrl = `${backendAdminApiUrl}${apiPath}`
    console.log("[Admin API] Using direct backend API URL:", fullUrl)
    return fullUrl
  }
}

export interface Employee {
  id: string
  email: string
  firstName: string
  lastName: string
  phoneNumber: string
  userName: string
  farmId: string
  farmName: string
  isStaff: boolean
  isAdmin?: boolean
  emailConfirmed: boolean
  createdDate: string
  adminTitle?: string | null
  permissions?: Record<string, boolean> | null
  featurePermissions?: Record<string, boolean> | null
  featureAccess?: Record<string, boolean> | null
  // lastLoginTime?: string | null // Commented out until database column is added
}

export interface CreateEmployeeData {
  email: string
  firstName: string
  lastName: string
  phoneNumber: string
  userName: string
  password: string
  farmId: string
  farmName: string
  isAdmin?: boolean
  adminTitle?: string
  adminPermissions?: Record<string, boolean>
  featurePermissions?: Record<string, boolean>
}

export interface UpdateEmployeeData {
  id: string
  firstName: string
  lastName: string
  phoneNumber: string
  email: string
  isAdmin?: boolean
  adminTitle?: string
  adminPermissions?: Record<string, boolean>
  featurePermissions?: Record<string, boolean>
}

interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Mock employees data
const mockEmployees: Employee[] = [
  {
    id: "emp-1",
    userName: "john_staff",
    email: "john@example.com",
    firstName: "John",
    lastName: "Doe",
    phoneNumber: "+1 (555) 111-2222",
    farmId: "farm-1",
    farmName: "Demo Farm",
    isStaff: true,
    emailConfirmed: true,
    createdDate: new Date().toISOString(),
  },
  {
    id: "emp-2",
    userName: "jane_staff",
    email: "jane@example.com",
    firstName: "Jane",
    lastName: "Smith",
    phoneNumber: "+1 (555) 333-4444",
    farmId: "farm-1",
    farmName: "Demo Farm",
    isStaff: true,
    emailConfirmed: true,
    createdDate: new Date().toISOString(),
  },
]

// Get all employees from backend API
// This calls the backend API (LoginAPI) endpoint: /api/Admin/employees
export async function getEmployees(): Promise<ApiResponse<Employee[]>> {
  try {
    const url = buildAdminApiUrl('/Admin/employees')
    console.log("[Admin API] Fetching employees from backend API:", url)
    
    // Log token presence for debugging
    if (typeof window !== "undefined") {
      const token = localStorage.getItem("auth_token")
      console.log("[Admin API] Token present:", !!token, "Token length:", token?.length)
    }

    const headers = getAuthHeaders()
    console.log("[Admin API] Request headers:", headers)

    const response = await fetch(url, {
      method: "GET",
      headers,
    })

    console.log("[Admin API] Response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      
      // Only log error details if not 401 (auth issue) and if error text exists
      if (response.status !== 401 && errorText && errorText.trim() !== '') {
        // Check if it's an HTML error page (like 404 pages from IIS)
        const isHtmlError = errorText.trim().toLowerCase().startsWith('<!doctype html') || 
                           errorText.includes('<html') || 
                           errorText.includes('404 - File or directory not found')
        
        if (isHtmlError) {
          console.warn("[Admin API] Received HTML error page (likely 404):", response.status)
        } else {
          console.warn("[Admin API] Fetch error:", errorText.substring(0, 500))
        }
        console.warn("[Admin API] Response status:", response.status)
      }
      
      // Handle authentication errors
      if (response.status === 401) {
        return {
          success: false,
          message: "Your session has expired. Please log in again to continue.",
        }
      }
      
      // Handle 404 errors gracefully (endpoint may not be deployed)
      if (response.status === 404) {
        const isHtmlError = errorText && (
          errorText.trim().toLowerCase().startsWith('<!doctype html') || 
          errorText.includes('<html') || 
          errorText.includes('404 - File or directory not found')
        )
        
        if (isHtmlError) {
          return {
            success: false,
            message: "Employees API endpoint not found. The backend API may not be deployed or the endpoint is unavailable.",
          }
        }
      }
      
      // Handle empty error response
      if (!errorText || errorText.trim() === '') {
        return {
          success: false,
          message: `API returned ${response.status} ${response.statusText}. The employees API may be unavailable.`,
        }
      }
      
      // Check if error is HTML (like IIS 404 page)
      const isHtmlError = errorText.trim().toLowerCase().startsWith('<!doctype html') || 
                         errorText.includes('<html') || 
                         errorText.includes('404 - File or directory not found')
      
      if (isHtmlError) {
        return {
          success: false,
          message: `API endpoint not found (${response.status}). The backend API may not be deployed or the URL is incorrect.`,
        }
      }
      
      // Parse error message
      try {
        const errorData = JSON.parse(errorText)
        const errorMessages = errorData.errors 
          ? Object.values(errorData.errors).flat().join(', ')
          : errorData.title || errorData.message || 'Failed to fetch employees'
        
        return {
          success: false,
          message: `API Error: ${errorMessages}`,
        }
      } catch (e) {
        // If not JSON, return a more helpful message
        const errorPreview = errorText.length > 200 ? errorText.substring(0, 200) + '...' : errorText
        return {
          success: false,
          message: `Failed to fetch employees (${response.status}): ${errorPreview}`,
        }
      }
    }

    const data = await response.json()
    console.log("[Admin API] Data received:", data)

    return {
      success: true,
      message: "Employees fetched successfully",
      data: data as Employee[],
    }
  } catch (error) {
    // Handle network errors and other exceptions
    const errorMessage = error instanceof Error ? error.message : 'Unknown error'
    const errorName = error instanceof Error ? error.name : 'Unknown'
    
    // Log all errors for debugging
    console.error("[Admin API] Exception fetching employees:", {
      name: errorName,
      message: errorMessage,
      error: error
    })
    
    // Handle network errors (connection refused, CORS, timeout, etc.)
    if (errorMessage.includes('Failed to fetch') || 
        errorMessage.includes('NetworkError') ||
        errorMessage.includes('Network request failed') ||
        errorName === 'TypeError' && errorMessage.includes('fetch')) {
      const fallbackUrl =
        process.env.NEXT_PUBLIC_LOGIN_API_URL ||
        process.env.NEXT_PUBLIC_ADMIN_API_URL ||
        DEFAULT_LOGIN_API_ORIGIN
      return {
        success: false,
        message: `Unable to connect to the Admin API. Please ensure the server is running and accessible at ${fallbackUrl}.`,
      }
    }
    
    // Handle timeout errors
    if (errorMessage.includes('timeout') || errorMessage.includes('aborted')) {
      return {
        success: false,
        message: `Request timed out. The Admin API may be slow or unavailable.`,
      }
    }
    
    return {
      success: false,
      message: `Error fetching employees: ${errorMessage}`,
    }
  }
}

// Get employee count
export async function getEmployeeCount(): Promise<ApiResponse<number>> {
  try {
    const url = buildAdminApiUrl('/Admin/employees/count')
    console.log("[Admin API] Fetching employee count:", url)

    const response = await fetch(url, {
      method: "GET",
      headers: getAuthHeaders(),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[Admin API] Employee count error:", errorText)
      return {
        success: false,
        message: "Failed to fetch employee count",
      }
    }

    const data = await response.json()
    return {
      success: true,
      message: "Employee count fetched successfully",
      data: data.count || data,
    }
  } catch (error) {
    console.error("[Admin API] Employee count error:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

// Get single employee by ID
export async function getEmployee(id: string): Promise<ApiResponse<Employee>> {
  try {
    const url = buildAdminApiUrl(`/Admin/employees/${id}`)
    console.log("[Admin API] Fetching employee:", url)

    const response = await fetch(url, {
      method: "GET",
      // headers: getAuthHeaders(),
      headers:getAuthHeaders(),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[Admin API] Employee fetch error:", errorText)
      return {
        success: false,
        message: "Failed to fetch employee",
      }
    }

    const data = await response.json()
    return {
      success: true,
      message: "Employee fetched successfully",
      data: data as Employee,
    }
  } catch (error) {
    console.error("[Admin API] Employee fetch error:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

// Create new employee (staff member) using backend API
// This calls the backend API (LoginAPI) endpoint: /api/Admin/employees
// The backend API handles employee creation with proper FarmId assignment
export async function createEmployee(employee: CreateEmployeeData): Promise<ApiResponse<Employee>> {
  try {
    const url = buildAdminApiUrl('/Admin/employees')
    console.log("[Admin API] Creating employee via backend API:", url)

    // Match the API request body structure exactly - backend expects PascalCase
    const requestBody = {
      Email: employee.email,
      FirstName: employee.firstName,
      LastName: employee.lastName,
      PhoneNumber: employee.phoneNumber,
      UserName: employee.userName,
      Password: employee.password,
      FarmId: employee.farmId,
      FarmName: employee.farmName,
      IsAdmin: employee.isAdmin ?? false,
      AdminTitle: employee.adminTitle || null,
      Permissions: employee.adminPermissions || null,
      FeaturePermissions: employee.featurePermissions || null,
      FeatureAccess: employee.featurePermissions || null,
    }

    console.log("[Admin API] Request body:", JSON.stringify(requestBody, null, 2))
    console.log("[Admin API] Request URL:", url)

    // Use custom headers for Admin API
    const headers = {
      ...getAuthHeaders(),
      Accept: "application/json", // Backend returns JSON (EmployeeModel)
    }

    console.log("[Admin API] Request headers:", headers)

    const response = await fetch(url, {
      method: "POST",
      headers,
      body: JSON.stringify(requestBody),
    })

    console.log("[Admin API] Create response status:", response.status, response.statusText)
    console.log("[Admin API] Response headers:", [...response.headers.entries()])
    console.log("[Admin API] Response OK:", response.ok)

    // Read response body once (can only be read once)
    const responseText = await response.text()
    console.log("[Admin API] Raw response text:", responseText)

    if (!response.ok) {
      console.error("[Admin API] Create error (status):", response.status, response.statusText)
      console.error("[Admin API] Create error (body):", responseText)
      
      // Handle authentication errors
      if (response.status === 401) {
        console.error("[Admin API] Authentication failed - token may be invalid or expired")
        return {
          success: false,
          message: "Your session has expired. Please log in again to continue.",
        }
      }
      
      // Handle empty error response
      if (!responseText || responseText.trim() === '') {
        return {
          success: false,
          message: `API returned ${response.status} ${response.statusText}. Please check the API connection.`,
        }
      }
      
      // Parse error for better message
      try {
        const errorData = JSON.parse(responseText)
        let errorMessage = 'Failed to create employee'
        
        // Try to extract the actual error message
        if (errorData.message) {
          errorMessage = errorData.message
        } else if (errorData.errors) {
          errorMessage = Object.values(errorData.errors).flat().join(', ')
        } else if (errorData.title) {
          errorMessage = errorData.title
        }
        
        return {
          success: false,
          message: errorMessage,
        }
      } catch (e) {
        // If not JSON, use the text as-is
        return {
          success: false,
          message: responseText || `Failed to create employee: ${response.status} ${response.statusText}`,
        }
      }
    }

    // Backend returns JSON (EmployeeModel) with 201 Created status
    let responseData: any = {}
    if (responseText && responseText.trim()) {
      try {
        responseData = JSON.parse(responseText)
        console.log("[Admin API] Success response (parsed):", responseData)
      } catch (e) {
        console.warn("[Admin API] Could not parse response as JSON:", e)
        console.warn("[Admin API] Response text was:", responseText)
      }
    }

    return {
      success: true,
      data: responseData as Employee,
      message: "Employee created successfully",
    }
  } catch (error) {
    console.error("[Admin API] Create exception:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

// Update employee
export async function updateEmployee(id: string, data: UpdateEmployeeData): Promise<ApiResponse> {
  try {
    const url = buildAdminApiUrl(`/Admin/employees/${id}`)
    console.log("[Admin API] Updating employee:", url)

    const requestBody = {
      Id: data.id,
      FirstName: data.firstName,
      LastName: data.lastName,
      PhoneNumber: data.phoneNumber,
      Email: data.email,
      IsAdmin: data.isAdmin ?? false,
      AdminTitle: data.adminTitle || null,
      Permissions: data.adminPermissions || null,
      FeaturePermissions: data.featurePermissions || null,
      FeatureAccess: data.featurePermissions || null,
    }

    const response = await fetch(url, {
      method: "PUT",
      headers: getAuthHeaders(),
      body: JSON.stringify(requestBody),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[Admin API] Update error:", errorText)
      return {
        success: false,
        message: "Failed to update employee",
      }
    }

    return {
      success: true,
      message: "Employee updated successfully",
    }
  } catch (error) {
    console.error("[Admin API] Update error:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

// Delete employee
// SECURITY: This operation requires admin privileges and should only be called from admin-protected pages
export async function deleteEmployee(id: string): Promise<ApiResponse> {
  try {
    // SECURITY: Validate required parameters
    if (!id || id.trim() === '') {
      console.error("[Admin API] Security: Invalid employee ID")
      return {
        success: false,
        message: "Invalid employee ID",
      }
    }
    
    // SECURITY: Verify user context exists (should be checked by calling component)
    if (typeof window !== 'undefined') {
      const userId = localStorage.getItem('userId')
      const farmId = localStorage.getItem('farmId')
      if (!userId || !farmId) {
        console.error("[Admin API] Security: Missing user context")
        return {
          success: false,
          message: "Authorization required. Please log in again.",
        }
      }
    }
    
    const url = buildAdminApiUrl(`/Admin/employees/${id}`)
    console.log("[Admin API] Deleting employee:", url)

    const response = await fetch(url, {
      method: "DELETE",
      headers: getAuthHeaders(),
    })

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[Admin API] Delete error:", errorText)
      return {
        success: false,
        message: "Failed to delete employee",
      }
    }

    return {
      success: true,
      message: "Employee deleted successfully",
    }
  } catch (error) {
    console.error("[Admin API] Delete error:", error)
    return {
      success: false,
      message: `Network error: ${error instanceof Error ? error.message : 'Unknown error'}`,
    }
  }
}

// Get employees who logged in today
export async function getTodayLogins(): Promise<ApiResponse<Employee[]>> {
  try {
    const url = buildAdminApiUrl('/Admin/employees/today-logins')
    const headers = getAuthHeaders()
    
    console.log("[Admin API] Fetching today's logins from:", url)
    
    const response = await fetch(url, {
      method: "GET",
      headers,
    })

    console.log("[Admin API] Today logins response status:", response.status)

    if (!response.ok) {
      // Handle 404 gracefully - endpoint may not be deployed yet
      if (response.status === 404) {
        console.warn("[Admin API] Today logins endpoint not found (404) - returning empty array")
        return {
          success: true,
          data: [],
          message: "Today logins endpoint not available",
        }
      }
      
      const errorText = await response.text()
      console.error("[Admin API] Today logins error:", errorText)
      
      if (response.status === 401) {
        return {
          success: false,
          message: "Your session has expired. Please log in again to continue.",
        }
      }
      
      if (!errorText || errorText.trim() === '') {
        return {
          success: false,
          message: `API returned ${response.status} ${response.statusText}. The logins API may be unavailable.`,
        }
      }
      
      try {
        const errorData = JSON.parse(errorText)
        const errorMessages = errorData.errors 
          ? Object.values(errorData.errors).flat().join(', ')
          : errorData.title || 'Failed to fetch today logins'
        
        return {
          success: false,
          message: `API Error: ${errorMessages}`,
        }
      } catch (e) {
        return {
          success: false,
          message: `Failed to fetch today logins: ${errorText || response.statusText}`,
        }
      }
    }

    const data = await response.json()
    console.log("[Admin API] Today logins data:", data)

    return {
      success: true,
      data,
      message: "Today logins retrieved successfully",
    }
  } catch (error) {
    console.error("[Admin API] Network error fetching today logins:", error)
    return {
      success: false,
      message: "Failed to fetch today logins. Please check your connection.",
    }
  }
}


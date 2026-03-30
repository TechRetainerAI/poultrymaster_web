// API utility functions for Report management

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

const API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

export interface ReportRequest {
  farmId: string
  userId: string
  reportType: string
  startDate: string
  endDate: string
  flockId?: number
  customerId?: number
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

// Export report to CSV
export async function exportReportToCSV(reportRequest: ReportRequest): Promise<ApiResponse<Blob>> {
  try {
    const url = `${API_BASE_URL}/api/Report/export/csv`
    console.log("[v0] Exporting report to CSV:", url)
    console.log("[v0] Report request:", reportRequest)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "text/csv, application/csv, */*",
      },
      body: JSON.stringify(reportRequest),
    })

    console.log("[v0] CSV export response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] CSV export error:", errorText)
      return {
        success: false,
        message: "Failed to export report to CSV",
        errors: [errorText],
      }
    }

    const blob = await response.blob()
    console.log("[v0] CSV export successful, blob size:", blob.size)

    return {
      success: true,
      message: "Report exported to CSV successfully",
      data: blob,
    }
  } catch (error) {
    console.error("[v0] CSV export error:", error)
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

// Export report to PDF
export async function exportReportToPDF(reportRequest: ReportRequest): Promise<ApiResponse<Blob>> {
  try {
    const url = `${API_BASE_URL}/api/Report/export/pdf`
    console.log("[v0] Exporting report to PDF:", url)
    console.log("[v0] Report request:", reportRequest)

    // Match ASP.NET ReportRequestModel property casing exactly
    const payload: any = {
      FarmId: reportRequest.farmId,
      UserId: reportRequest.userId,
      ReportType: reportRequest.reportType,
      StartDate: reportRequest.startDate,
      EndDate: reportRequest.endDate,
    }
    if (reportRequest.flockId !== undefined) payload.FlockId = reportRequest.flockId
    if (reportRequest.customerId !== undefined) payload.CustomerId = reportRequest.customerId

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/pdf, */*",
      },
      body: JSON.stringify(payload),
    })

    console.log("[v0] PDF export response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] PDF export error:", errorText)
      return {
        success: false,
        message: "Failed to export report to PDF",
        errors: [errorText],
      }
    }

    const blob = await response.blob()
    console.log("[v0] PDF export successful, blob size:", blob.size)

    return {
      success: true,
      message: "Report exported to PDF successfully",
      data: blob,
    }
  } catch (error) {
    console.error("[v0] PDF export error:", error)
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

// Export report to Excel
export async function exportReportToExcel(reportRequest: ReportRequest): Promise<ApiResponse<Blob>> {
  try {
    const url = `${API_BASE_URL}/api/Report/export/excel`
    console.log("[v0] Exporting report to Excel:", url)
    console.log("[v0] Report request:", reportRequest)

    const response = await fetch(url, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Accept: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet, application/vnd.ms-excel, */*",
      },
      body: JSON.stringify(reportRequest),
    })

    console.log("[v0] Excel export response status:", response.status)

    if (!response.ok) {
      const errorText = await response.text()
      console.error("[v0] Excel export error:", errorText)
      return {
        success: false,
        message: "Failed to export report to Excel",
        errors: [errorText],
      }
    }

    const blob = await response.blob()
    console.log("[v0] Excel export successful, blob size:", blob.size)

    return {
      success: true,
      message: "Report exported to Excel successfully",
      data: blob,
    }
  } catch (error) {
    console.error("[v0] Excel export error:", error)
    return {
      success: false,
      message: "Network error. Please try again.",
    }
  }
}

// Helper function to download blob as file
export function downloadBlob(blob: Blob, filename: string): void {
  const url = window.URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = filename
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  window.URL.revokeObjectURL(url)
}

// Helper function to get user context for reports
export function getReportContext(): { farmId: string; userId: string } {
  if (typeof window === "undefined") {
    return { farmId: "", userId: "" }
  }

  const farmId = localStorage.getItem("farmId") || ""
  const userId = localStorage.getItem("userId") || ""

  return { farmId, userId }
}

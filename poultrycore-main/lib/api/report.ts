// Report helpers.
//
// Server-side report export (POST /Report/export/{pdf,csv,excel}) used to live
// here, but the live app generates report PDFs client-side via
// lib/utils/pdf-export.ts (jsPDF), so those upload helpers were removed as dead
// code. Only the user-context helper below is still used (by app/reports/page).

// Helper function to get user context for reports
export function getReportContext(): { farmId: string; userId: string } {
  if (typeof window === "undefined") {
    return { farmId: "", userId: "" }
  }

  const farmId = localStorage.getItem("farmId") || ""
  const userId = localStorage.getItem("userId") || ""

  return { farmId, userId }
}

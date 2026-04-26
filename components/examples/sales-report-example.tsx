"use client"

import { useState } from "react"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Download, FileText, FileSpreadsheet, File } from "lucide-react"
import { exportReportToCSV, exportReportToPDF, exportReportToExcel, downloadBlob, getReportContext, type ReportRequest } from "@/lib/api"
import { getSales, createSale, type SaleInput } from "@/lib/api"
import { useToast } from "@/hooks/use-toast"

export function SalesReportExample() {
  const [isGenerating, setIsGenerating] = useState(false)
  const [isCreatingSale, setIsCreatingSale] = useState(false)
  const { toast } = useToast()

  // Example: Create a quick sale
  const handleCreateQuickSale = async () => {
    setIsCreatingSale(true)
    try {
      const { farmId, userId } = getReportContext()
      
      const newSale: SaleInput = {
        farmId,
        userId,
        saleDate: new Date().toISOString(),
        product: "Fresh Eggs",
        quantity: 100,
        unitPrice: 0.50,
        totalAmount: 50.00,
        paymentMethod: "Cash",
        customerName: "Example Customer",
        flockId: 1,
        saleDescription: "Quick sale example",
      }

      const response = await createSale(newSale)
      if (response.success) {
        toast({
          title: "Success",
          description: "Quick sale created successfully!",
        })
      } else {
        toast({
          title: "Error",
          description: response.message || "Failed to create sale",
          variant: "destructive",
        })
      }
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to create sale",
        variant: "destructive",
      })
    } finally {
      setIsCreatingSale(false)
    }
  }

  // Example: Export sales report
  const handleExportSalesReport = async (format: 'csv' | 'pdf' | 'excel') => {
    setIsGenerating(true)
    try {
      const { farmId, userId } = getReportContext()
      
      const reportRequest: ReportRequest = {
        farmId,
        userId,
        reportType: "sales",
        startDate: new Date(Date.now() - 30 * 24 * 60 * 60 * 1000).toISOString(), // Last 30 days
        endDate: new Date().toISOString(),
      }

      let response
      const filename = `sales_report_${format}.${format}`

      switch (format) {
        case 'csv':
          response = await exportReportToCSV(reportRequest)
          break
        case 'pdf':
          response = await exportReportToPDF(reportRequest)
          break
        case 'excel':
          response = await exportReportToExcel(reportRequest)
          break
      }

      if (response?.success && response.data) {
        downloadBlob(response.data, filename)
        toast({
          title: "Export Successful",
          description: `Sales report exported as ${format.toUpperCase()}`,
        })
      } else {
        toast({
          title: "Export Failed",
          description: response?.message || "Failed to export report",
          variant: "destructive",
        })
      }
    } catch (error) {
      toast({
        title: "Export Error",
        description: "An error occurred while exporting the report",
        variant: "destructive",
      })
    } finally {
      setIsGenerating(false)
    }
  }

  return (
    <div className="grid gap-6 md:grid-cols-2">
      {/* Quick Sale Creation */}
      <Card>
        <CardHeader>
          <CardTitle>Quick Sale Example</CardTitle>
          <CardDescription>
            Create a sample sale record to test the API
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="text-sm text-muted-foreground">
            <p>This will create a sample sale with:</p>
            <ul className="list-disc list-inside mt-2 space-y-1">
              <li>Product: Fresh Eggs</li>
              <li>Quantity: 100</li>
              <li>Unit Price: $0.50</li>
              <li>Total: $50.00</li>
              <li>Payment: Cash</li>
            </ul>
          </div>
          <Button 
            onClick={handleCreateQuickSale} 
            disabled={isCreatingSale}
            className="w-full"
          >
            {isCreatingSale ? "Creating..." : "Create Sample Sale"}
          </Button>
        </CardContent>
      </Card>

      {/* Report Export */}
      <Card>
        <CardHeader>
          <CardTitle>Export Sales Report</CardTitle>
          <CardDescription>
            Export the last 30 days of sales data
          </CardDescription>
        </CardHeader>
        <CardContent className="space-y-4">
          <div className="text-sm text-muted-foreground">
            <p>Export sales data from the last 30 days in your preferred format.</p>
          </div>
          
          <div className="grid grid-cols-3 gap-2">
            <Button
              variant="outline"
              size="sm"
              onClick={() => handleExportSalesReport('csv')}
              disabled={isGenerating}
            >
              <FileSpreadsheet className="h-4 w-4 mr-2" />
              CSV
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => handleExportSalesReport('pdf')}
              disabled={isGenerating}
            >
              <FileText className="h-4 w-4 mr-2" />
              PDF
            </Button>
            <Button
              variant="outline"
              size="sm"
              onClick={() => handleExportSalesReport('excel')}
              disabled={isGenerating}
            >
              <File className="h-4 w-4 mr-2" />
              Excel
            </Button>
          </div>
        </CardContent>
      </Card>
    </div>
  )
}

// Example usage in a page:
export default function ExampleUsage() {
  return (
    <div className="container mx-auto p-6">
      <h1 className="text-2xl font-bold mb-6">API Integration Examples</h1>
      <SalesReportExample />
      
      <div className="mt-8 p-4 bg-muted rounded-lg">
        <h3 className="font-semibold mb-2">How to use these APIs in your components:</h3>
        <pre className="text-sm overflow-x-auto">
{`// Import the APIs
import { getSales, createSale, exportReportToCSV } from "@/lib/api"

// In your component
const [sales, setSales] = useState([])

// Fetch sales data
const loadSales = async () => {
  const response = await getSales()
  if (response.success) {
    setSales(response.data)
  }
}

// Create a new sale
const handleCreateSale = async (saleData) => {
  const response = await createSale(saleData)
  if (response.success) {
    // Handle success
  }
}

// Export report
const handleExport = async () => {
  const reportRequest = {
    farmId: "your-farm-id",
    userId: "your-user-id",
    reportType: "sales",
    startDate: "2024-01-01T00:00:00.000Z",
    endDate: "2024-01-31T23:59:59.999Z"
  }
  
  const response = await exportReportToCSV(reportRequest)
  if (response.success) {
    downloadBlob(response.data, "sales_report.csv")
  }
}`}
        </pre>
      </div>
    </div>
  )
}

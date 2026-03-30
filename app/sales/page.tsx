"use client"

import { useState, useEffect, useRef, useMemo } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { Plus, Edit, Trash2, ShoppingCart, DollarSign, TrendingUp, Package, FileText, Printer, Loader2, Info, Search, Filter, ChevronDown, ChevronUp } from "lucide-react"
import { getSales, createSale, updateSale, deleteSale, getFlocks, getCustomers, createCustomer, type Sale, type SaleInput } from "@/lib/api"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import { formatCurrency, getSelectedCurrency, setSelectedCurrency } from "@/lib/utils/currency"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetHeader, SheetTitle, SheetTrigger } from "@/components/ui/sheet"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"

export default function SalesPage() {
  const router = useRouter()
  const [sales, setSales] = useState<Sale[]>([])
  const [loading, setLoading] = useState(true)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [currentPage, setCurrentPage] = useState(1)
  const pageSize = 10
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isInvoiceDialogOpen, setIsInvoiceDialogOpen] = useState(false)
  const [editingSale, setEditingSale] = useState<Sale | null>(null)
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null)
  const [flocks, setFlocks] = useState<any[]>([])
  const [customers, setCustomers] = useState<any[]>([])
  const [showNewCustomerInput, setShowNewCustomerInput] = useState(false)
  const [otherCustomerName, setOtherCustomerName] = useState("")
  const [farmInfo, setFarmInfo] = useState({
    name: "Farm Name",
    address: "",
    phone: "",
    email: "",
  })
  const { toast } = useToast()
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingSaleId, setDeletingSaleId] = useState<number | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)
  const invoicePrintRef = useRef<HTMLDivElement | null>(null)

  // Form state
  const [formData, setFormData] = useState<Partial<SaleInput>>({
    saleDate: new Date().toISOString().split('T')[0],
    product: "",
    quantity: 0,
    unitPrice: 0,
    totalAmount: 0,
    paymentMethod: "",
    customerName: "",
    flockId: 0,
    saleDescription: "",
  })

  const productOptions = ["Fresh Eggs", "Chicken", "Manure", "Other"]
  const paymentMethodOptions = ["Cash", "Credit Card", "Bank Transfer", "Check", "Mobile Money"]
  const currencyOptions = ["GHS", "USD", "EUR", "GBP", "NGN", "KES"]

  const [productSelection, setProductSelection] = useState<string | undefined>(undefined)
  const [productOther, setProductOther] = useState("")
  const [currencyCode, setCurrencyCode] = useState<string>(() => getSelectedCurrency())
  const [searchCustomer, setSearchCustomer] = useState("")
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [showAllColumnsMobile, setShowAllColumnsMobile] = useState(false)
  const isMobile = useIsMobile()
  const [crates, setCrates] = useState(0)
  const [looseEggs, setLooseEggs] = useState(0)
  const [overrideAmount, setOverrideAmount] = useState<number | undefined>(undefined)

  // Check if current product is eggs (for crates input)
  const isEggsProduct = (formData.product ?? "").toLowerCase().includes("egg")

  useEffect(() => {
    loadSales()
    loadFlocks()
    loadCustomers()
    
    // Check for global search query from header
    if (typeof window !== 'undefined') {
      const globalSearch = sessionStorage.getItem('globalSearchQuery')
      if (globalSearch) {
        setSearchCustomer(globalSearch)
        sessionStorage.removeItem('globalSearchQuery')
      }
      
      // Listen for global search events from header
      const handleGlobalSearch = (e: CustomEvent) => {
        setSearchCustomer(e.detail.query)
      }
      
      window.addEventListener('globalSearch', handleGlobalSearch as EventListener)
      return () => {
        window.removeEventListener('globalSearch', handleGlobalSearch as EventListener)
      }
    }
  }, [])

  useEffect(() => {
    if (typeof window === "undefined") return
    const storedFarmName = localStorage.getItem("farmName")
    const storedFarmAddress = localStorage.getItem("farmAddress")
    const storedFarmPhone = localStorage.getItem("farmPhone")
    const storedFarmEmail = localStorage.getItem("farmEmail")

    setFarmInfo({
      name: storedFarmName || "Farm Name",
      address: storedFarmAddress || "",
      phone: storedFarmPhone || "",
      email: storedFarmEmail || "",
    })
  }, [])
  
  const loadFlocks = async () => {
    const { userId, farmId } = getUserContext()
    if (userId && farmId) {
      const result = await getFlocks(userId, farmId)
      if (result.success && result.data) {
        setFlocks(result.data)
      }
    }
  }
  
  const loadCustomers = async () => {
    const { userId, farmId } = getUserContext()
    if (userId && farmId) {
      const result = await getCustomers(userId, farmId)
      if (result.success && result.data) {
        setCustomers(result.data)
      }
    }
  }

  const loadSales = async () => {
    try {
      setLoading(true)
      const { userId, farmId } = getUserContext()
      
      if (!userId || !farmId) {
        toast({
          title: "Error",
          description: "User context not found. Please log in again.",
          variant: "destructive",
        })
        return
      }
      
      const response = await getSales(userId, farmId)
      if (response.success && response.data) {
        setSales(response.data)
      } else {
        toast({
          title: "Error",
          description: response.message || "Failed to load sales",
          variant: "destructive",
        })
      }
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to load sales",
        variant: "destructive",
      })
    } finally {
      setLoading(false)
    }
  }

  const handleCreateSale = async () => {
    try {
      const { userId, farmId } = getUserContext()
      
      if (!userId || !farmId) {
        toast({
          title: "Error",
          description: "User context not found. Please log in again.",
          variant: "destructive",
        })
        return
      }
      
      if (!validateSaleForm()) return

      const quantity = Number(formData.quantity ?? 0)
      const unitPrice = Number(formData.unitPrice ?? 0)
      const calculatedAmount = isEggsProduct ? crates * unitPrice : quantity * unitPrice
      const totalAmount = (overrideAmount !== undefined && overrideAmount > 0) ? overrideAmount : calculatedAmount
      const saleData: SaleInput = {
        farmId,
        userId,
        saleId: 0,
        saleDate: formData.saleDate!,
        product: (formData.product ?? "").toString().trim(),
        quantity,
        unitPrice,
        totalAmount,
        paymentMethod: (formData.paymentMethod ?? "").toString(),
        customerName: (formData.customerName ?? "").toString(),
        flockId: formData.flockId ?? 0,
        saleDescription: formData.saleDescription ?? "",
      }
      
      const response = await createSale(saleData)
      if (response.success) {
        toast({
          title: "Success",
          description: "Sale created successfully",
        })
        setIsCreateDialogOpen(false)
        resetForm()
        loadSales()
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
    }
  }

  const handleUpdateSale = async () => {
    if (!editingSale) return

    try {
      const { userId, farmId } = getUserContext()
      
      if (!userId || !farmId) {
        toast({
          title: "Error",
          description: "User context not found. Please log in again.",
          variant: "destructive",
        })
        return
      }
      
      if (!validateSaleForm()) return

      const quantity = Number(formData.quantity ?? 0)
      const unitPrice = Number(formData.unitPrice ?? 0)
      const calculatedAmount = isEggsProduct ? crates * unitPrice : quantity * unitPrice
      const totalAmount = (overrideAmount !== undefined && overrideAmount > 0) ? overrideAmount : calculatedAmount

      const payload: Partial<SaleInput> = {
        farmId,
        userId,
        saleDate: formData.saleDate!,
        product: (formData.product ?? "").toString().trim(),
        quantity,
        unitPrice,
        totalAmount,
        paymentMethod: (formData.paymentMethod ?? "").toString(),
        customerName: (formData.customerName ?? "").toString(),
        flockId: formData.flockId ?? 0,
        saleDescription: formData.saleDescription ?? "",
      }
      
      const response = await updateSale(editingSale.saleId, payload)
      if (response.success) {
        toast({
          title: "Success",
          description: "Sale updated successfully",
        })
        setIsEditDialogOpen(false)
        setEditingSale(null)
        resetForm()
        loadSales()
      } else {
        toast({
          title: "Error",
          description: response.message || "Failed to update sale",
          variant: "destructive",
        })
      }
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to update sale",
        variant: "destructive",
      })
    }
  }

  const openDeleteSaleDialog = (id: number) => {
    setDeletingSaleId(id)
    setDeleteDialogOpen(true)
  }

  const handleDeleteSale = async () => {
    if (!deletingSaleId) return

    setIsDeleting(true)
    try {
      const { userId, farmId } = getUserContext()
      const response = await deleteSale(deletingSaleId, userId, farmId)
      if (response.success) {
        toast({
          title: "Sale deleted",
          description: "The sale record has been successfully deleted.",
        })
        loadSales()
      } else {
        toast({
          title: "Delete failed",
          description: response.message || "Failed to delete sale",
          variant: "destructive",
        })
      }
    } catch (error) {
      toast({
        title: "Delete failed",
        description: "Failed to delete sale. Please try again.",
        variant: "destructive",
      })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingSaleId(null)
  }

  const resetForm = () => {
    setFormData({
      saleDate: new Date().toISOString().split('T')[0],
      product: "",
      quantity: 0,
      unitPrice: 0,
      totalAmount: 0,
      paymentMethod: "",
      customerName: "",
      flockId: 0,
      saleDescription: "",
    })
    setProductSelection(undefined)
    setProductOther("")
    setShowNewCustomerInput(false)
    setOtherCustomerName("")
    setOverrideAmount(undefined)
    setCrates(0)
    setLooseEggs(0)
  }
  
  const handleCreateNewCustomer = async (customerName: string) => {
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) return
    
    try {
      const newCustomer = {
        farmId,
        userId,
        name: customerName,
        contactEmail: "",
        contactPhone: "",
        address: "",
        city: "",
      }
      
      const result = await createCustomer(newCustomer)
      if (result.success) {
        toast({
          title: "Success",
          description: "Customer created successfully",
        })
        loadCustomers()
        setShowNewCustomerInput(false)
      }
    } catch (error) {
      toast({
        title: "Error",
        description: "Failed to create customer",
        variant: "destructive",
      })
    }
  }

  const handleProductSelect = (value: string) => {
    setProductSelection(value)
    if (value === "Other") {
      const existing = productOther || (typeof formData.product === "string" && !productOptions.includes(formData.product) ? formData.product : "")
      setProductOther(existing)
      setFormData(prev => ({ ...prev, product: existing }))
    } else {
      setProductOther("")
      setFormData(prev => ({ ...prev, product: value }))
    }
    // Reset crate fields when switching away from egg products
    const isEgg = value.toLowerCase().includes("egg") || (value === "Other" && productOther.toLowerCase().includes("egg"))
    if (!isEgg) {
      setCrates(0)
      setLooseEggs(0)
    }
  }

  const handleCurrencyChange = (value: string) => {
    setCurrencyCode(value)
    setSelectedCurrency(value)
  }

  const clearFilters = () => {
    setSearchCustomer("")
    setDateFrom("")
    setDateTo("")
  }

  const validateSaleForm = () => {
    const product = (formData.product ?? "").toString().trim()
    const quantity = Number(formData.quantity ?? 0)
    const unitPrice = Number(formData.unitPrice ?? 0)
    const paymentMethod = (formData.paymentMethod ?? "").toString().trim()
    const customerName = (formData.customerName ?? "").toString().trim()

    let message = ""

    if (!formData.saleDate) message = "Sale date is required."
    else if (!product) message = "Product is required."
    else if (!customerName) message = "Customer name is required."
    else if (!Number.isFinite(quantity) || quantity <= 0) message = "Quantity is required and must be greater than zero."
    else if (!Number.isFinite(unitPrice) || unitPrice <= 0) message = "Unit price is required and must be greater than zero."
    else if (!paymentMethod) message = "Payment method is required."

    if (message) {
      toast({
        title: "Required field missing",
        description: message,
        variant: "destructive",
      })
      return false
    }

    return true
  }

  const getFlockLabel = (flockId?: number | null) => {
    if (flockId === 0 || flockId === null || typeof flockId === "undefined") return "All flocks"
    const match = flocks.find((flock) => flock.flockId === flockId)
    return match ? `${match.name}` : `#${flockId}`
  }

  const openEditDialog = (sale: Sale) => {
    setEditingSale(sale)
    setFormData({
      saleDate: sale.saleDate.split('T')[0],
      product: sale.product,
      quantity: sale.quantity,
      unitPrice: sale.unitPrice,
      totalAmount: sale.totalAmount,
      paymentMethod: sale.paymentMethod,
      customerName: sale.customerName,
      flockId: sale.flockId,
      saleDescription: sale.saleDescription,
    })
    const selection = productOptions.includes(sale.product) ? sale.product : "Other"
    setProductSelection(selection)
    setProductOther(selection === "Other" ? sale.product : "")
    setShowNewCustomerInput(false)
    // Reverse-calculate crates and loose eggs from quantity for egg products
    const isEgg = (sale.product ?? "").toLowerCase().includes("egg")
    if (isEgg && sale.quantity > 0) {
      setCrates(Math.floor(sale.quantity / 30))
      setLooseEggs(sale.quantity % 30)
    } else {
      setCrates(0)
      setLooseEggs(0)
    }
    setIsEditDialogOpen(true)
  }

  const calculateTotal = () => {
    const unitPrice = Number(formData.unitPrice) || 0
    const total = isEggsProduct ? crates * unitPrice : (Number(formData.quantity) || 0) * unitPrice
    setFormData(prev => ({ ...prev, totalAmount: total }))
  }

  useEffect(() => {
    calculateTotal()
  }, [formData.quantity, formData.unitPrice, crates, isEggsProduct])

  const openInvoiceDialog = (sale: Sale) => {
    setSelectedSale(sale)
    setIsInvoiceDialogOpen(true)
  }

  const closeInvoiceDialog = (open: boolean) => {
    setIsInvoiceDialogOpen(open)
    if (!open) {
      setSelectedSale(null)
    }
  }

  const generateInvoiceNumber = (saleId: number) => {
    return `INV-${saleId.toString().padStart(6, "0")}`
  }

  const formatInvoiceDate = (date: string) => {
    return new Date(date).toLocaleDateString(undefined, {
      year: "numeric",
      month: "short",
      day: "numeric",
    })
  }

  const handlePrintInvoice = () => {
    if (!selectedSale || typeof window === "undefined") return
    const invoiceContent = invoicePrintRef.current?.innerHTML

    if (!invoiceContent) {
      toast({
        title: "Print error",
        description: "Unable to prepare invoice for printing.",
        variant: "destructive",
      })
      return
    }

    const printWindow = window.open("", "_blank", "width=900,height=650")
    if (!printWindow) {
      toast({
        title: "Popup blocked",
        description: "Please allow pop-ups to print the invoice.",
        variant: "destructive",
      })
      return
    }

    printWindow.document.write(`
      <html>
        <head>
          <title>Invoice ${generateInvoiceNumber(selectedSale.saleId)}</title>
          <style>
            body { font-family: Arial, sans-serif; padding: 32px; color: #0f172a; }
            h1, h2, h3, h4 { margin: 0; }
            .invoice-header { display: flex; justify-content: space-between; margin-bottom: 24px; }
            .invoice-section { margin-bottom: 24px; }
            .invoice-box { border: 1px solid #e2e8f0; border-radius: 12px; padding: 24px; }
            .invoice-grid { display: grid; grid-template-columns: repeat(auto-fit, minmax(220px, 1fr)); gap: 16px; }
            .muted { color: #64748b; }
            table { width: 100%; border-collapse: collapse; margin-top: 16px; }
            th, td { padding: 12px 16px; border-bottom: 1px solid #e2e8f0; text-align: left; }
            .total-row td { font-weight: bold; }
            .badge { display: inline-block; padding: 4px 12px; border-radius: 9999px; border: 1px solid #cbd5f5; background: #eef2ff; color: #3730a3; font-size: 12px; }
          </style>
        </head>
        <body>
          ${invoiceContent}
        </body>
      </html>
    `)
    printWindow.document.close()
    printWindow.focus()
    printWindow.print()
    printWindow.close()
  }

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    localStorage.removeItem("username")
    localStorage.removeItem("userId")
    localStorage.removeItem("farmId")
    localStorage.removeItem("farmName")
    localStorage.removeItem("isStaff")
    localStorage.removeItem("isSubscriber")
    router.push("/login")
  }

  const filteredSales = useMemo(() => {
    const query = searchCustomer.trim().toLowerCase()
    return sales.filter((sale) => {
      if (query) {
        const matchesCustomer = sale.customerName?.toLowerCase().includes(query)
        const matchesProduct = sale.product?.toLowerCase().includes(query)
        if (!matchesCustomer && !matchesProduct) return false
      }
      if (dateFrom) {
        if (new Date(sale.saleDate) < new Date(dateFrom)) return false
      }
      if (dateTo) {
        const saleDate = new Date(sale.saleDate)
        const to = new Date(dateTo)
        to.setHours(23, 59, 59, 999)
        if (saleDate > to) return false
      }
      return true
    })
  }, [sales, searchCustomer, dateFrom, dateTo])

  const sortedSales = useMemo(() => sortData(filteredSales, sortKey, sortDir, (item: any, key: string) => {
    switch (key) {
      case "saleDate": return new Date(item.saleDate)
      case "quantity": return Number(item.quantity) || 0
      case "unitPrice": return Number(item.unitPrice) || 0
      case "totalAmount": return Number(item.totalAmount) || 0
      default: return (item as any)[key]
    }
  }), [filteredSales, sortKey, sortDir])
  const totalPages = Math.max(1, Math.ceil(sortedSales.length / pageSize))
  const safePage = Math.min(currentPage, totalPages)
  const paginatedSales = useMemo(
    () => sortedSales.slice((safePage - 1) * pageSize, safePage * pageSize),
    [sortedSales, safePage]
  )
  const totalSales = useMemo(() => filteredSales.reduce((sum, sale) => sum + (sale.totalAmount || 0), 0), [filteredSales])
  const totalQuantity = useMemo(() => filteredSales.reduce((sum, sale) => sum + (sale.quantity || 0), 0), [filteredSales])
  const selectedFlockId = formData.flockId ?? null
  const selectedFlockIdString = selectedFlockId !== null ? selectedFlockId.toString() : ""
  const productSelectValue = productSelection ?? (
    typeof formData.product === "string" && formData.product
      ? (productOptions.includes(formData.product) ? formData.product : "Other")
      : undefined
  )

  useEffect(() => {
    setCurrentPage(1)
  }, [searchCustomer, dateFrom, dateTo])

  return (
    <div className="flex min-h-screen bg-slate-50">
      {/* Sidebar */}
      <DashboardSidebar onLogout={handleLogout} />
      
      {/* Main Content */}
      <div className="flex-1 flex flex-col">
        {/* Header */}
        <DashboardHeader />
        
        {/* Main Content Area */}
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-4">
              <div className="flex items-start gap-3 min-w-0">
                <div className="w-10 h-10 shrink-0 bg-green-100 rounded-lg flex items-center justify-center">
                  <ShoppingCart className="w-5 h-5 text-green-600" />
                </div>
                <div className="min-w-0">
                  <h1 className="text-xl sm:text-2xl font-bold text-slate-900 truncate">Sales</h1>
                  <p className="text-sm text-slate-600">Manage your farm sales and transactions</p>
                </div>
              </div>
              <Dialog
                open={isCreateDialogOpen}
                onOpenChange={(open) => {
                  setIsCreateDialogOpen(open)
                  if (open) {
                    resetForm()
                  } else {
                    resetForm()
                  }
                }}
              >
                <DialogTrigger asChild>
                  <Button className="gap-2 w-full sm:w-auto h-11 sm:h-10 bg-blue-600 hover:bg-blue-700 shrink-0">
                    <Plus className="w-4 h-4" />
                    Add Sale
                  </Button>
                </DialogTrigger>
          <DialogContent className="max-w-4xl w-[95vw] sm:max-w-[900px] max-h-[90vh] flex flex-col">
            <DialogHeader>
              <DialogTitle>Create New Sale</DialogTitle>
              <DialogDescription>
                Add a new sale record to track your farm&apos;s revenue
              </DialogDescription>
            </DialogHeader>
            <div className="space-y-5 py-4 overflow-y-auto pr-1">
              {/* Section: Sale Details */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Sale Details</div>
                <div className="grid grid-cols-2 gap-4 p-4">
                  <div className="space-y-2">
                    <Label htmlFor="saleDate">Sale Date *</Label>
                    <Input
                      id="saleDate"
                      type="date"
                      value={formData.saleDate}
                      onChange={(e) => setFormData(prev => ({ ...prev, saleDate: e.target.value }))}
                    />
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="product">Product *</Label>
                    <Select
                      value={productSelectValue}
                      onValueChange={handleProductSelect}
                    >
                      <SelectTrigger id="product">
                        <SelectValue placeholder="Select product" />
                      </SelectTrigger>
                      <SelectContent>
                        {productOptions.map(option => (
                          <SelectItem key={option} value={option}>
                            {option}
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    {productSelectValue === "Other" && (
                      <Input
                        value={productOther}
                        onChange={(e) => {
                          const value = e.target.value
                          setProductOther(value)
                          setFormData(prev => ({ ...prev, product: value }))
                        }}
                        placeholder="Enter product name"
                      />
                    )}
                  </div>
                </div>
              </div>

              {/* Section: Egg Quantity (conditional) */}
              {isEggsProduct && (
                <div className="rounded-xl border border-amber-200 overflow-hidden">
                  <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                  <div className="grid grid-cols-3 gap-4 p-4 bg-amber-50">
                    <div className="space-y-2">
                      <Label htmlFor="crates" className="text-sm">Crates (30 eggs)</Label>
                      <Input
                        id="crates"
                        type="number"
                        min="0"
                        value={crates}
                        onChange={(e) => {
                          const c = parseInt(e.target.value) || 0
                          setCrates(c)
                          const total = (c * 30) + looseEggs
                          setFormData(prev => ({ ...prev, quantity: total }))
                        }}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="looseEggs" className="text-sm">Loose Eggs</Label>
                      <Input
                        id="looseEggs"
                        type="number"
                        min="0"
                        max="29"
                        value={looseEggs}
                        onChange={(e) => {
                          const l = parseInt(e.target.value) || 0
                          setLooseEggs(l)
                          const total = (crates * 30) + l
                          setFormData(prev => ({ ...prev, quantity: total }))
                        }}
                      />
                    </div>
                    <div className="space-y-2">
                      <Label className="text-sm">Total Eggs</Label>
                      <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-amber-700">
                        {((crates * 30) + looseEggs).toLocaleString()}
                      </div>
                    </div>
                  </div>
                  <div className="px-4 pb-3 bg-amber-50">
                    <p className="text-xs text-amber-600">
                      Calculation: {crates} crates × 30 + {looseEggs} loose = {((crates * 30) + looseEggs).toLocaleString()} eggs
                    </p>
                  </div>
                </div>
              )}

              {/* Section: Pricing */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Pricing</div>
                <div className="p-4 space-y-4">
                  <div className="grid grid-cols-2 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="quantity">Quantity *</Label>
                      <Input
                        id="quantity"
                        type="number"
                        value={formData.quantity}
                        onChange={(e) => setFormData(prev => ({ ...prev, quantity: Number(e.target.value) }))}
                        placeholder="0"
                        disabled={isEggsProduct}
                        className={isEggsProduct ? "bg-slate-100" : ""}
                      />
                      {isEggsProduct && <p className="text-xs text-slate-500">Auto-calculated from crates + eggs above</p>}
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="unitPrice">{isEggsProduct ? "Unit Price Per Crate *" : "Unit Price *"}</Label>
                      <Input
                        id="unitPrice"
                        type="number"
                        step="0.01"
                        value={formData.unitPrice}
                        onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: Number(e.target.value) }))}
                        placeholder="0.00"
                      />
                    </div>
                  </div>
                  <div className="grid grid-cols-3 gap-4">
                    <div className="space-y-2">
                      <Label htmlFor="totalAmount">Calculated Amount</Label>
                      <Input
                        id="totalAmount"
                        type="number"
                        step="0.01"
                        value={formData.totalAmount}
                        readOnly
                        className="bg-slate-100"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="overrideAmount">Override Amount</Label>
                      <Input
                        id="overrideAmount"
                        type="number"
                        step="0.01"
                        value={overrideAmount ?? ""}
                        onChange={(e) => setOverrideAmount(e.target.value ? Number(e.target.value) : undefined)}
                        placeholder="Leave empty to use calculated"
                      />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="paymentMethod">Payment Method *</Label>
                      <Select value={formData.paymentMethod} onValueChange={(value) => setFormData(prev => ({ ...prev, paymentMethod: value }))}>
                        <SelectTrigger>
                          <SelectValue placeholder="Select payment method" />
                        </SelectTrigger>
                        <SelectContent>
                          {paymentMethodOptions.map(method => (
                            <SelectItem key={method} value={method}>
                              {method}
                            </SelectItem>
                          ))}
                        </SelectContent>
                      </Select>
                    </div>
                  </div>
                </div>
              </div>

              {/* Section: Customer & Flock */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Customer &amp; Flock</div>
                <div className="grid grid-cols-3 gap-4 p-4">
                  <div className="col-span-2 space-y-2">
                    <div className="flex items-center gap-2">
                      <Label htmlFor="customerName">Customer Name *</Label>
                      <Tooltip>
                        <TooltipTrigger asChild>
                          <Info className="h-4 w-4 text-slate-400 cursor-help" />
                        </TooltipTrigger>
                        <TooltipContent side="top" className="max-w-[260px]">
                          <p>If you cannot find the customer, please go to the customer page and create the Customer first</p>
                        </TooltipContent>
                      </Tooltip>
                    </div>
                    <Select
                      value={showNewCustomerInput ? "__OTHER__" : formData.customerName || undefined}
                      onValueChange={(value) => {
                        if (value === "__OTHER__") {
                          setShowNewCustomerInput(true)
                          setOtherCustomerName("")
                          setFormData(prev => ({ ...prev, customerName: "" }))
                        } else {
                          setShowNewCustomerInput(false)
                          setOtherCustomerName("")
                          setFormData(prev => ({ ...prev, customerName: value }))
                        }
                      }}
                    >
                      <SelectTrigger className="w-full">
                        <SelectValue placeholder="Select a customer" />
                      </SelectTrigger>
                      <SelectContent>
                        {customers.map((customer) => (
                          <SelectItem key={customer.customerId || customer.name} value={customer.name}>
                            {customer.name}
                          </SelectItem>
                        ))}
                        <SelectItem value="__OTHER__">Other Customer</SelectItem>
                      </SelectContent>
                    </Select>
                    {showNewCustomerInput && (
                      <Input
                        placeholder="Enter other customer name"
                        value={otherCustomerName}
                        onChange={(e) => {
                          setOtherCustomerName(e.target.value)
                          setFormData(prev => ({ ...prev, customerName: e.target.value }))
                        }}
                      />
                    )}
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="flockId">Flock</Label>
                    <Select
                      value={selectedFlockIdString}
                      onValueChange={(value) =>
                        setFormData(prev => ({
                          ...prev,
                          flockId: value ? Number(value) : undefined,
                        }))
                      }
                    >
                      <SelectTrigger>
                        <SelectValue placeholder="Select a flock" />
                      </SelectTrigger>
                      <SelectContent>
                        <SelectItem value="0">All flocks</SelectItem>
                        {flocks.map((flock) => (
                          <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                            {flock.name} ({flock.quantity} birds)
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                </div>
              </div>

              {/* Description */}
              <div className="space-y-2">
                <Label htmlFor="saleDescription">Description</Label>
                <Textarea
                  id="saleDescription"
                  value={formData.saleDescription}
                  onChange={(e) => setFormData(prev => ({ ...prev, saleDescription: e.target.value }))}
                  placeholder="Additional notes about this sale"
                />
              </div>
            </div>
            <div className="flex justify-end space-x-2 pt-2 border-t">
              <Button onClick={() => setIsCreateDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                Cancel
              </Button>
              <Button onClick={handleCreateSale} className="bg-blue-600 hover:bg-blue-700">Create Sale</Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search customer or product" value={searchCustomer} onChange={(e) => setSearchCustomer(e.target.value)} className="pl-10 h-11" />
                </div>
                <Sheet open={filtersOpen} onOpenChange={setFiltersOpen}>
                  <SheetTrigger asChild>
                    <Button variant="outline" className="w-full h-11 gap-2 justify-start">
                      <Filter className="h-4 w-4" />
                      Filters
                      {(!!searchCustomer || !!dateFrom || !!dateTo) && (
                        <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-amber-500 text-white text-xs flex items-center justify-center">
                          {[searchCustomer, dateFrom, dateTo].filter(Boolean).length}
                        </span>
                      )}
                    </Button>
                  </SheetTrigger>
                  <SheetContent side="bottom" className="h-[75vh] rounded-t-2xl">
                    <SheetHeader>
                      <SheetTitle>Filters</SheetTitle>
                    </SheetHeader>
                    <div className="space-y-4 overflow-y-auto pb-8">
                      <div>
                        <label className="text-sm font-medium text-slate-700 mb-1 block">Date range</label>
                        <div className="grid grid-cols-2 gap-2">
                          <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} />
                          <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} />
                        </div>
                      </div>
                      <div>
                        <label className="text-sm font-medium text-slate-700 mb-1 block">Currency</label>
                        <Select value={currencyCode} onValueChange={handleCurrencyChange}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            {currencyOptions.map((code) => (
                              <SelectItem key={code} value={code}>{code}</SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                      <div className="flex gap-2 pt-4">
                        <Button variant="outline" className="flex-1" onClick={clearFilters}>Clear all</Button>
                        <Button className="flex-1" onClick={() => setFiltersOpen(false)}>Apply</Button>
                      </div>
                    </div>
                  </SheetContent>
                </Sheet>
              </div>
            ) : (
            <div className="p-3 bg-white rounded border flex flex-wrap gap-3 items-end">
              <div className="w-full sm:w-[220px]">
                <Label className="text-xs text-slate-500">Customer / Product</Label>
                <Input placeholder="Search customer or product" value={searchCustomer} onChange={(e) => setSearchCustomer(e.target.value)} />
              </div>
              <div>
                <Label className="text-xs text-slate-500">From</Label>
                <Input type="date" value={dateFrom} onChange={(e) => setDateFrom(e.target.value)} className="w-[160px]" />
              </div>
              <div>
                <Label className="text-xs text-slate-500">To</Label>
                <Input type="date" value={dateTo} onChange={(e) => setDateTo(e.target.value)} className="w-[160px]" />
              </div>
              <div>
                <Label className="text-xs text-slate-500">Currency</Label>
                <Select value={currencyCode} onValueChange={handleCurrencyChange}>
                  <SelectTrigger className="w-[140px]"><SelectValue /></SelectTrigger>
                  <SelectContent>
                    {currencyOptions.map((code) => (
                      <SelectItem key={code} value={code}>{code}</SelectItem>
                    ))}
                  </SelectContent>
                </Select>
              </div>
              <div className="ml-auto">
                <Button variant="outline" onClick={clearFilters}>Reset filters</Button>
              </div>
            </div>
            )}

            {/* Summary Cards */}
            <div className={cn("grid gap-4", isMobile ? "grid-cols-2" : "md:grid-cols-3")}>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Total Sales</CardTitle>
                  <DollarSign className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div
                    className={cn(
                      "font-bold leading-tight",
                      isMobile ? "text-xl break-words whitespace-normal" : "text-2xl"
                    )}
                  >
                    {formatCurrency(totalSales, currencyCode)}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {filteredSales.length} transactions
                  </p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Total Quantity</CardTitle>
                  <Package className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div className={cn("font-bold leading-tight", isMobile ? "text-xl" : "text-2xl")}>
                    {totalQuantity.toLocaleString()}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    {Math.floor(totalQuantity / 30)} crates + {totalQuantity % 30} pieces
                  </p>
                </CardContent>
              </Card>
              <Card className="bg-white">
                <CardHeader className="flex flex-row items-center justify-between space-y-0 pb-2">
                  <CardTitle className="text-sm font-medium">Average Sale</CardTitle>
                  <TrendingUp className="h-4 w-4 text-muted-foreground" />
                </CardHeader>
                <CardContent>
                  <div
                    className={cn(
                      "font-bold leading-tight",
                      isMobile ? "text-xl break-words whitespace-normal" : "text-2xl"
                    )}
                  >
                    {formatCurrency(filteredSales.length > 0 ? (totalSales / filteredSales.length) : 0, currencyCode)}
                  </div>
                  <p className="text-xs text-muted-foreground">
                    per transaction
                  </p>
                </CardContent>
              </Card>
            </div>

            {/* Sales Table */}
            {loading ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <p className="text-slate-600">Loading sales...</p>
                </CardContent>
              </Card>
            ) : sales.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center">
                  <div className="w-16 h-16 bg-slate-50 rounded-full flex items-center justify-center mx-auto mb-4">
                    <ShoppingCart className="w-8 h-8 text-slate-400" />
                  </div>
                  <h3 className="text-lg font-semibold text-slate-900 mb-2">No sales found</h3>
                  <p className="text-slate-600 mb-6">Get started by adding your first sale</p>
                  <Dialog open={isCreateDialogOpen} onOpenChange={setIsCreateDialogOpen}>
                    <DialogTrigger asChild>
                      <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                        <Plus className="w-4 h-4" />
                        Add Your First Sale
                      </Button>
                    </DialogTrigger>
                  </Dialog>
                </CardContent>
              </Card>
            ) : filteredSales.length === 0 ? (
              <Card className="bg-white">
                <CardContent className="py-12 text-center space-y-3">
                  <p className="text-slate-600">No sales match the current filters.</p>
                  <Button variant="outline" onClick={clearFilters}>Reset filters</Button>
                </CardContent>
              </Card>
            ) : (
              <Card className="bg-white overflow-hidden">
                <CardHeader>
                  <CardTitle>Recent Sales</CardTitle>
                  <CardDescription>
                    View and manage your sales transactions
                  </CardDescription>
                </CardHeader>
                <CardContent className="p-0">
                  {isMobile && !showAllColumnsMobile ? (
                    <div className="space-y-3">
                      {paginatedSales.map((sale, idx) => (
                        <Collapsible key={sale.saleId} className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2">
                                    <span className="font-semibold text-slate-900">{formatDateShort(sale.saleDate)}</span>
                                    <span className="text-slate-500">•</span>
                                    <span className="text-slate-600 truncate">{sale.customerName}</span>
                                  </div>
                                  <div className="mt-1 flex items-baseline gap-3">
                                    <span className="text-lg font-bold text-emerald-600">{formatCurrency(sale.totalAmount, currencyCode)}</span>
                                    <span className="text-xs text-slate-500">{sale.product}</span>
                                  </div>
                                </div>
                                <ChevronDown className="h-5 w-5 text-slate-400 shrink-0 transition-transform group-data-[state=open]:rotate-180" />
                              </div>
                            </CollapsibleTrigger>
                            <CollapsibleContent>
                              <div className="mt-4 pt-4 border-t border-slate-100 space-y-2 text-sm">
                                <div className="grid grid-cols-2 gap-2">
                                  <div><span className="text-slate-500">Quantity</span> <span className="font-medium">{sale.quantity}</span></div>
                                  <div><span className="text-slate-500">Payment</span> <span className="font-medium">{sale.paymentMethod}</span></div>
                                  <div><span className="text-slate-500">Flock</span> <span className="font-medium">{getFlockLabel(sale.flockId)}</span></div>
                                </div>
                                <div className="flex gap-2 pt-2">
                                  <Button variant="outline" size="sm" className="flex-1 h-10" onClick={() => openEditDialog(sale)}>
                                    <Edit className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="h-10 text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteSaleDialog(sale.saleId)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
                                  </Button>
                                  <Button variant="outline" size="sm" className="h-10" onClick={() => openInvoiceDialog(sale)}>
                                    <FileText className="h-4 w-4 mr-2" /> Invoice
                                  </Button>
                                </div>
                              </div>
                            </CollapsibleContent>
                          </div>
                        </Collapsible>
                      ))}
                      {paginatedSales.length > 0 && (
                        <div className="px-4 py-3 bg-slate-50/50 border-t">
                          <Button variant="ghost" size="sm" className="w-full text-slate-600" onClick={() => setShowAllColumnsMobile(true)}>
                            View table format <ChevronDown className="h-4 w-4 ml-1" />
                          </Button>
                        </div>
                      )}
                    </div>
                  ) : (
                  <div className={cn("overflow-x-auto table-scroll-wrapper", isMobile && "pb-2")} style={{ WebkitOverflowScrolling: "touch" }}>
                    {isMobile && (
                      <div className="px-4 py-2 border-b bg-slate-50 flex items-center justify-between gap-2 sticky top-0 z-10">
                        <span className="text-xs text-slate-600">Table • Scroll → for more</span>
                        <Button variant="ghost" size="sm" onClick={() => setShowAllColumnsMobile(false)}>
                          <ChevronUp className="h-4 w-4 mr-1" /> Cards
                        </Button>
                      </div>
                    )}
                  <Table className={cn("w-full", !isMobile && "min-w-[900px]")}>
                    <TableHeader>
                      <TableRow>
                        <SortableHeader label="Date" sortKey="saleDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn(isMobile && "sticky-col-date bg-slate-50")} />
                        <SortableHeader label="Product" sortKey="product" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Customer" sortKey="customerName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Quantity" sortKey="quantity" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Unit Price" sortKey="unitPrice" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Total" sortKey="totalAmount" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Payment" sortKey="paymentMethod" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <TableHead className={cn("min-w-[140px] whitespace-nowrap", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {paginatedSales.map((sale) => (
                        <TableRow key={sale.saleId}>
                          <TableCell className={cn("bg-white", isMobile && "sticky-col-date")}>{isMobile ? formatDateShort(sale.saleDate) : new Date(sale.saleDate).toLocaleDateString()}</TableCell>
                          <TableCell>{sale.product}</TableCell>
                          <TableCell>{sale.customerName}</TableCell>
                          <TableCell>{getFlockLabel(sale.flockId)}</TableCell>
                          <TableCell>
                            {sale.quantity}
                            {sale.product && sale.product.toLowerCase().includes("egg") && sale.quantity > 0 && (
                              <span className="block text-xs text-slate-500">
                                {Math.floor(sale.quantity / 30)}cr + {sale.quantity % 30}pcs
                              </span>
                            )}
                          </TableCell>
                          <TableCell>{formatCurrency(sale.unitPrice, currencyCode)}</TableCell>
                          <TableCell className="font-medium">{formatCurrency(sale.totalAmount, currencyCode)}</TableCell>
                          <TableCell>
                            <Badge variant="outline">{sale.paymentMethod}</Badge>
                          </TableCell>
                          <TableCell className={cn("whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                            <div className="flex items-center gap-1 min-w-[100px]">
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => openEditDialog(sale)}
                              >
                                <Edit className="h-4 w-4" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => openDeleteSaleDialog(sale.saleId)}
                              >
                                <Trash2 className="h-4 w-4" />
                              </Button>
                              <Button
                                variant="ghost"
                                size="sm"
                                onClick={() => openInvoiceDialog(sale)}
                                aria-label="View Invoice"
                              >
                                <FileText className="h-4 w-4" />
                              </Button>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                  )}
                {!loading && filteredSales.length > 0 && (
                  <div className="flex items-center justify-between gap-2 px-4 py-3 border-t bg-slate-50">
                    <p className="text-xs text-slate-600">
                      Showing {(safePage - 1) * pageSize + 1}-{Math.min(safePage * pageSize, sortedSales.length)} of {sortedSales.length}
                    </p>
                    <div className="flex items-center gap-2">
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={safePage <= 1}
                        onClick={() => setCurrentPage((p) => Math.max(1, p - 1))}
                      >
                        Previous
                      </Button>
                      <span className="text-xs text-slate-600">
                        Page {safePage} of {totalPages}
                      </span>
                      <Button
                        variant="outline"
                        size="sm"
                        disabled={safePage >= totalPages}
                        onClick={() => setCurrentPage((p) => Math.min(totalPages, p + 1))}
                      >
                        Next
                      </Button>
                    </div>
                  </div>
                )}
                </CardContent>
              </Card>
            )}

            {/* Edit Dialog */}
            <Dialog
              open={isEditDialogOpen}
              onOpenChange={(open) => {
                setIsEditDialogOpen(open)
                if (!open) {
                  setEditingSale(null)
                  resetForm()
                }
              }}
            >
              <DialogContent className="max-w-4xl w-[95vw] sm:max-w-[900px] max-h-[90vh] flex flex-col">
                <DialogHeader>
                  <DialogTitle>Edit Sale</DialogTitle>
                  <DialogDescription>
                    Update the sale record details
                  </DialogDescription>
                </DialogHeader>
                <div className="space-y-5 py-4 overflow-y-auto pr-1">
                  {/* Section: Sale Details */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Sale Details</div>
                    <div className="grid grid-cols-2 gap-4 p-4">
                      <div className="space-y-2">
                        <Label htmlFor="edit-saleDate">Sale Date *</Label>
                        <Input
                          id="edit-saleDate"
                          type="date"
                          value={formData.saleDate}
                          onChange={(e) => setFormData(prev => ({ ...prev, saleDate: e.target.value }))}
                        />
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-product">Product *</Label>
                        <Select
                          value={productSelectValue}
                          onValueChange={handleProductSelect}
                        >
                          <SelectTrigger id="edit-product">
                            <SelectValue placeholder="Select product" />
                          </SelectTrigger>
                          <SelectContent>
                            {productOptions.map(option => (
                              <SelectItem key={`edit-${option}`} value={option}>
                                {option}
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        {productSelectValue === "Other" && (
                          <Input
                            value={productOther}
                            onChange={(e) => {
                              const value = e.target.value
                              setProductOther(value)
                              setFormData(prev => ({ ...prev, product: value }))
                            }}
                            placeholder="Enter product name"
                          />
                        )}
                      </div>
                    </div>
                  </div>

                  {/* Section: Egg Quantity (conditional) */}
                  {isEggsProduct && (
                    <div className="rounded-xl border border-amber-200 overflow-hidden">
                      <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                      <div className="grid grid-cols-3 gap-4 p-4 bg-amber-50">
                        <div className="space-y-2">
                          <Label htmlFor="edit-crates" className="text-sm">Crates (30 eggs)</Label>
                          <Input
                            id="edit-crates"
                            type="number"
                            min="0"
                            value={crates}
                            onChange={(e) => {
                              const c = parseInt(e.target.value) || 0
                              setCrates(c)
                              const total = (c * 30) + looseEggs
                              setFormData(prev => ({ ...prev, quantity: total }))
                            }}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-looseEggs" className="text-sm">Loose Eggs</Label>
                          <Input
                            id="edit-looseEggs"
                            type="number"
                            min="0"
                            max="29"
                            value={looseEggs}
                            onChange={(e) => {
                              const l = parseInt(e.target.value) || 0
                              setLooseEggs(l)
                              const total = (crates * 30) + l
                              setFormData(prev => ({ ...prev, quantity: total }))
                            }}
                          />
                        </div>
                        <div className="space-y-2">
                          <Label className="text-sm">Total Eggs</Label>
                          <div className="h-10 px-3 py-2 bg-white border rounded-md flex items-center font-bold text-amber-700">
                            {((crates * 30) + looseEggs).toLocaleString()}
                          </div>
                        </div>
                      </div>
                      <div className="px-4 pb-3 bg-amber-50">
                        <p className="text-xs text-amber-600">
                          Calculation: {crates} crates × 30 + {looseEggs} loose = {((crates * 30) + looseEggs).toLocaleString()} eggs
                        </p>
                      </div>
                    </div>
                  )}

                  {/* Section: Pricing */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-green-600 px-4 py-2 text-sm font-semibold text-white">Pricing</div>
                    <div className="p-4 space-y-4">
                      <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-quantity">Quantity *</Label>
                          <Input
                            id="edit-quantity"
                            type="number"
                            value={formData.quantity}
                            onChange={(e) => setFormData(prev => ({ ...prev, quantity: Number(e.target.value) }))}
                            placeholder="0"
                            disabled={isEggsProduct}
                            className={isEggsProduct ? "bg-slate-100" : ""}
                          />
                          {isEggsProduct && <p className="text-xs text-slate-500">Auto-calculated from crates + eggs above</p>}
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-unitPrice">{isEggsProduct ? "Unit Price Per Crate *" : "Unit Price *"}</Label>
                          <Input
                            id="edit-unitPrice"
                            type="number"
                            step="0.01"
                            value={formData.unitPrice}
                            onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: Number(e.target.value) }))}
                            placeholder="0.00"
                          />
                        </div>
                      </div>
                      <div className="grid grid-cols-3 gap-4">
                        <div className="space-y-2">
                          <Label htmlFor="edit-totalAmount">Calculated Amount</Label>
                          <Input
                            id="edit-totalAmount"
                            type="number"
                            step="0.01"
                            value={formData.totalAmount}
                            readOnly
                            className="bg-slate-100"
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-overrideAmount">Override Amount</Label>
                          <Input
                            id="edit-overrideAmount"
                            type="number"
                            step="0.01"
                            value={overrideAmount ?? ""}
                            onChange={(e) => setOverrideAmount(e.target.value ? Number(e.target.value) : undefined)}
                            placeholder="Leave empty to use calculated"
                          />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-paymentMethod">Payment Method *</Label>
                          <Select value={formData.paymentMethod} onValueChange={(value) => setFormData(prev => ({ ...prev, paymentMethod: value }))}>
                            <SelectTrigger>
                              <SelectValue placeholder="Select payment method" />
                            </SelectTrigger>
                            <SelectContent>
                              {paymentMethodOptions.map(method => (
                                <SelectItem key={`edit-${method}`} value={method}>
                                  {method}
                                </SelectItem>
                              ))}
                            </SelectContent>
                          </Select>
                        </div>
                      </div>
                    </div>
                  </div>

                  {/* Section: Customer & Flock */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Customer &amp; Flock</div>
                    <div className="grid grid-cols-3 gap-4 p-4">
                      <div className="col-span-2 space-y-2">
                        <div className="flex items-center gap-2">
                          <Label htmlFor="edit-customerName">Customer Name *</Label>
                          <Tooltip>
                            <TooltipTrigger asChild>
                              <Info className="h-4 w-4 text-slate-400 cursor-help" />
                            </TooltipTrigger>
                            <TooltipContent side="top" className="max-w-[260px]">
                              <p>If you cannot find the customer, please go to the customer page and create the Customer first</p>
                            </TooltipContent>
                          </Tooltip>
                        </div>
                        <Select
                          value={showNewCustomerInput ? "__OTHER__" : formData.customerName || undefined}
                          onValueChange={(value) => {
                            if (value === "__OTHER__") {
                              setShowNewCustomerInput(true)
                              setOtherCustomerName("")
                              setFormData(prev => ({ ...prev, customerName: "" }))
                            } else {
                              setShowNewCustomerInput(false)
                              setOtherCustomerName("")
                              setFormData(prev => ({ ...prev, customerName: value }))
                            }
                          }}
                        >
                          <SelectTrigger className="w-full">
                            <SelectValue placeholder="Select a customer" />
                          </SelectTrigger>
                          <SelectContent>
                            {customers.map((customer) => (
                              <SelectItem key={customer.customerId || customer.name} value={customer.name}>
                                {customer.name}
                              </SelectItem>
                            ))}
                            <SelectItem value="__OTHER__">Other Customer</SelectItem>
                          </SelectContent>
                        </Select>
                        {showNewCustomerInput && (
                          <Input
                            placeholder="Enter other customer name"
                            value={otherCustomerName}
                            onChange={(e) => {
                              setOtherCustomerName(e.target.value)
                              setFormData(prev => ({ ...prev, customerName: e.target.value }))
                            }}
                          />
                        )}
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-flockId">Flock</Label>
                        <Select
                          value={selectedFlockIdString}
                          onValueChange={(value) =>
                            setFormData(prev => ({
                              ...prev,
                              flockId: value ? Number(value) : undefined,
                            }))
                          }
                        >
                          <SelectTrigger>
                            <SelectValue placeholder="Select a flock" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="0">All flocks</SelectItem>
                            {flocks.map((flock) => (
                              <SelectItem key={flock.flockId} value={flock.flockId.toString()}>
                                {flock.name} ({flock.quantity} birds)
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                      </div>
                    </div>
                  </div>

                  {/* Description */}
                  <div className="space-y-2">
                    <Label htmlFor="edit-saleDescription">Description</Label>
                    <Textarea
                      id="edit-saleDescription"
                      value={formData.saleDescription}
                      onChange={(e) => setFormData(prev => ({ ...prev, saleDescription: e.target.value }))}
                      placeholder="Additional notes about this sale"
                    />
                  </div>
                </div>
                <div className="flex justify-end space-x-2 pt-2 border-t">
                  <Button onClick={() => setIsEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                    Cancel
                  </Button>
                  <Button onClick={handleUpdateSale} className="bg-blue-600 hover:bg-blue-700">Update Sale</Button>
                </div>
              </DialogContent>
            </Dialog>

            {/* Invoice Dialog */}
            <Dialog open={isInvoiceDialogOpen} onOpenChange={closeInvoiceDialog}>
              <DialogContent className={cn("w-[95vw] max-h-[90vh] overflow-y-auto", isMobile ? "p-4" : "max-w-3xl")}>
                <DialogHeader>
                  <DialogTitle>Sale Invoice</DialogTitle>
                  <DialogDescription>
                    Review the invoice details and print a copy for the customer.
                  </DialogDescription>
                </DialogHeader>

                {selectedSale ? (
                  <div className="space-y-6">
                    <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                      <div>
                        <p className="text-sm text-muted-foreground">Invoice Number</p>
                        <p className="text-xl font-semibold">
                          {generateInvoiceNumber(selectedSale.saleId)}
                        </p>
                      </div>
                      <Button onClick={handlePrintInvoice} className="gap-2 self-start md:self-auto">
                        <Printer className="h-4 w-4" />
                        Print Invoice
                      </Button>
                    </div>

                    <div
                      ref={invoicePrintRef}
                      id="invoice-print-area"
                      className="rounded-xl border border-slate-200 bg-white p-4 sm:p-6 text-slate-900"
                    >
                      <div className="flex flex-col gap-6">
                        <div className="flex flex-col gap-6 md:flex-row md:items-start md:justify-between">
                          <div>
                            <h2 className="text-xl sm:text-2xl font-bold break-words">{farmInfo.name}</h2>
                            {farmInfo.address && (
                              <p className="mt-1 text-sm text-slate-500">{farmInfo.address}</p>
                            )}
                            <div className="mt-2 space-y-1 text-sm text-slate-500">
                              {farmInfo.phone && <p>Phone: {farmInfo.phone}</p>}
                              {farmInfo.email && <p>Email: {farmInfo.email}</p>}
                            </div>
                          </div>
                          <div className="space-y-1 text-left md:text-right text-sm text-slate-500">
                            <p>
                              <span className="font-semibold text-slate-700">Invoice Date:</span>{" "}
                              {formatInvoiceDate(selectedSale.saleDate)}
                            </p>
                            <p>
                              <span className="font-semibold text-slate-700">Created:</span>{" "}
                              {formatInvoiceDate(selectedSale.createdDate)}
                            </p>
                            <p>
                              <span className="font-semibold text-slate-700">Payment Method:</span>{" "}
                              {selectedSale.paymentMethod}
                            </p>
                          </div>
                        </div>

                        <div className="grid gap-4 md:grid-cols-2">
                          <div className="rounded-lg border border-slate-200 p-4">
                            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-700">
                              Bill To
                            </h3>
                            <p className="mt-2 text-lg font-medium">{selectedSale.customerName}</p>
                            <p className="text-sm text-slate-500">
                              {selectedSale.saleDescription || "Customer invoice"}
                            </p>
                          </div>
                          <div className="rounded-lg border border-slate-200 p-4">
                            <h3 className="text-sm font-semibold uppercase tracking-wide text-slate-700">
                              Sale Reference
                            </h3>
                            <div className="mt-2 space-y-1 text-sm text-slate-500">
                              <p>
                                <span className="font-semibold text-slate-700">Product:</span>{" "}
                                {selectedSale.product}
                              </p>
                              <p>
                                <span className="font-semibold text-slate-700">Flock:</span>{" "}
                                {getFlockLabel(selectedSale.flockId)}
                              </p>
                              <p>
                                <span className="font-semibold text-slate-700">Recorded By:</span>{" "}
                                {selectedSale.userId}
                              </p>
                            </div>
                          </div>
                        </div>

                        {isMobile ? (
                          <div className="rounded-lg border border-slate-200 p-4 space-y-3">
                            <p className="text-xs uppercase tracking-wide text-slate-500 font-semibold">Invoice Item</p>
                            <div className="space-y-2 text-sm">
                              <div className="flex items-start justify-between gap-3">
                                <span className="text-slate-500">Description</span>
                                <span className="font-medium text-slate-800 text-right break-words">{selectedSale.product}</span>
                              </div>
                              <div className="flex items-start justify-between gap-3">
                                <span className="text-slate-500">Quantity</span>
                                <span className="text-right">
                                  {selectedSale.quantity}
                                  {selectedSale.product && selectedSale.product.toLowerCase().includes("egg") && (
                                    <span className="block text-xs text-slate-500 mt-0.5">
                                      {Math.floor(selectedSale.quantity / 30)} crates + {selectedSale.quantity % 30} loose
                                    </span>
                                  )}
                                </span>
                              </div>
                              <div className="flex items-start justify-between gap-3">
                                <span className="text-slate-500">Unit Price</span>
                                <span className="font-medium whitespace-nowrap">{formatCurrency(selectedSale.unitPrice, currencyCode)}</span>
                              </div>
                              <div className="flex items-start justify-between gap-3 border-t border-slate-200 pt-2">
                                <span className="text-slate-700 font-semibold">Amount</span>
                                <span className="font-semibold whitespace-nowrap">{formatCurrency(selectedSale.totalAmount, currencyCode)}</span>
                              </div>
                            </div>
                          </div>
                        ) : (
                          <div className="overflow-x-auto rounded-lg border border-slate-200">
                            <table className="w-full min-w-[640px]">
                              <thead className="bg-slate-50 text-left text-sm uppercase tracking-wide text-slate-500">
                                <tr>
                                  <th className="px-3 py-3 sm:px-6 whitespace-nowrap">Description</th>
                                  <th className="px-3 py-3 sm:px-6 whitespace-nowrap">Quantity</th>
                                  <th className="px-3 py-3 sm:px-6 whitespace-nowrap">Unit Price</th>
                                  <th className="px-3 py-3 sm:px-6 whitespace-nowrap">Amount</th>
                                </tr>
                              </thead>
                              <tbody className="text-sm">
                                <tr className="border-t border-slate-200">
                                  <td className="px-3 py-4 sm:px-6">
                                    <p className="font-medium text-slate-800">{selectedSale.product}</p>
                                    {selectedSale.saleDescription && (
                                      <p className="mt-1 text-slate-500">
                                        {selectedSale.saleDescription}
                                      </p>
                                    )}
                                  </td>
                                  <td className="px-3 py-4 sm:px-6">
                                    {selectedSale.quantity}
                                    {selectedSale.product && selectedSale.product.toLowerCase().includes("egg") && (
                                      <span className="block text-xs text-slate-500 mt-0.5">
                                        {Math.floor(selectedSale.quantity / 30)} crates + {selectedSale.quantity % 30} loose
                                      </span>
                                    )}
                                  </td>
                                  <td className="px-3 py-4 sm:px-6 whitespace-nowrap">
                                    {formatCurrency(selectedSale.unitPrice, currencyCode)}
                                  </td>
                                  <td className="px-3 py-4 sm:px-6 font-semibold whitespace-nowrap">
                                    {formatCurrency(selectedSale.totalAmount, currencyCode)}
                                  </td>
                                </tr>
                              </tbody>
                            </table>
                          </div>
                        )}

                        <div className="flex flex-col gap-4 md:flex-row md:items-center md:justify-between">
                          <p className="text-sm text-slate-500">
                            Thank you for your business! Please contact us if you have any questions about this invoice.
                          </p>
                          <div className="self-start md:self-auto rounded-lg border border-slate-200 px-4 sm:px-6 py-4 text-left md:text-right">
                            <p className="text-sm text-slate-500">Total Due</p>
                            <p className="text-2xl font-bold text-slate-900">
                              {formatCurrency(selectedSale.totalAmount, currencyCode)}
                            </p>
                          </div>
                        </div>
                      </div>
                    </div>
                  </div>
                ) : (
                  <p className="text-sm text-muted-foreground">
                    Select a sale to view invoice details.
                  </p>
                )}
              </DialogContent>
            </Dialog>
          </div>
        </main>
      </div>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete Sale</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete this sale? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleDeleteSale} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

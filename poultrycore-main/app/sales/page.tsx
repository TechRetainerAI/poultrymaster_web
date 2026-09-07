"use client"

import { useState, useEffect, useRef, useMemo } from "react"
import { useRouter } from "next/navigation"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Badge } from "@/components/ui/badge"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Pagination, PaginationContent, PaginationItem, PaginationLink, PaginationNext, PaginationPrevious, PaginationEllipsis } from "@/components/ui/pagination"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { NumberInput } from "@/components/ui/number-input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip"
import { Plus, Edit, Trash2, ShoppingCart, DollarSign, TrendingUp, Package, FileText, Printer, Loader2, Info, Search, Filter, ChevronDown, ChevronUp, Mail, Wallet, History } from "lucide-react"
import { getSales, createSale, updateSale, deleteSale, getFlocks, getCustomers, createCustomer, type Sale, type SaleInput } from "@/lib/api"
import { listPoultryCashAccounts, recordPoultryPayment, type PoultryCashAccount } from "@/lib/api/poultry-finance"
import { useToast } from "@/hooks/use-toast"
import { getUserContext } from "@/lib/utils/user-context"
import Link from "next/link"
import { formatCurrency, getSelectedCurrency } from "@/lib/utils/currency"
import { useCurrency } from "@/lib/currency"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useIsMobile } from "@/hooks/use-mobile"
import { Sheet, SheetContent, SheetTrigger } from "@/components/ui/sheet"
import {
  MOBILE_FILTER_SHEET_CONTENT_CLASS,
  MOBILE_FILTER_SELECT_CONTENT_CLASS,
  MOBILE_FILTERS_TOOLBAR_ROW_CLASS,
  MOBILE_FILTERS_TRIGGER_BUTTON_CLASS,
  MobileFilterSheetBody,
  MobileFilterSheetFooter,
  MobileFilterSheetHeader,
} from "@/components/dashboard/mobile-filters"
import { toLocalDateKey } from "@/lib/utils/date-key"
import { Collapsible, CollapsibleContent, CollapsibleTrigger } from "@/components/ui/collapsible"
import { formatDateShort, cn } from "@/lib/utils"
import { toastFormGuide } from "@/lib/utils/validation-toast"
import {
  SaleInvoiceDocument,
  saleInvoiceNumber,
  SALE_INVOICE_PRINT_STYLES,
} from "@/components/sales/sale-invoice-document"
import { exportTableToPdf, emailTableAsPdf, type PdfExportOptions } from "@/lib/utils/pdf-export"
import { PaymentHistoryDialog } from "@/components/balances/payment-history-dialog"
import { usePermissions } from "@/hooks/use-permissions"
import { Download } from "lucide-react"

/**
 * Egg quantity as crates and loose pieces, e.g. "2cr + 15pcs".
 *
 * A zero part is dropped rather than printed: "2cr + 0pcs" and "0cr + 15pcs"
 * both spend space saying nothing. An exact 60 reads "2cr", a loose 15 reads
 * "15pcs". Returns null when there is nothing to break down, so the caller can
 * omit the whole label instead of rendering an empty one.
 */
function eggCrateBreakdown(
  quantity: number,
  { long = false, eggsPerCrate = 30 }: { long?: boolean; eggsPerCrate?: number } = {},
): string | null {
  if (!Number.isFinite(quantity) || quantity <= 0 || eggsPerCrate <= 0) return null
  const crates = Math.floor(quantity / eggsPerCrate)
  const pieces = quantity % eggsPerCrate
  const parts: string[] = []
  // `long` is for the summary card, which has room for real words; the table
  // cell sits next to the number it describes and uses the short form.
  if (crates > 0) parts.push(long ? `${crates.toLocaleString()} crate${crates === 1 ? "" : "s"}` : `${crates}c`)
  if (pieces > 0) parts.push(long ? `${pieces} piece${pieces === 1 ? "" : "s"}` : `${pieces}p`)
  return parts.length ? parts.join(" + ") : null
}

/**
 * What a sale line comes to.
 *
 * Egg prices are quoted per crate, but a sale is rarely a whole number of
 * crates. Charging `crates x price` billed "2 crates + 15 loose" as two crates
 * and the 15 loose eggs left the farm free, so loose eggs are charged pro rata
 * at one-thirtieth of the crate price. Rounded to the minor unit, so an odd
 * price on a part crate cannot carry float noise into the ledger.
 */
function saleLineTotal(
  quantity: number,
  unitPrice: number,
  isEggs: boolean,
  eggsPerCrate = 30,
): number {
  const qty = Number(quantity) || 0
  const price = Number(unitPrice) || 0
  const amount = isEggs && eggsPerCrate > 0 ? (qty / eggsPerCrate) * price : qty * price
  return Math.round(amount * 100) / 100
}

/**
 * An egg count as crates, e.g. 75 -> "2.50".
 *
 * The Pricing box shows this rather than the raw egg count so that the line
 * reads as the arithmetic it is: crates x price per crate = amount. The sale
 * still stores `quantity` in eggs, which is what stock and the reports count.
 */
function eggCratesEquivalent(quantity: number | undefined, eggsPerCrate = 30): string {
  const qty = Number(quantity) || 0
  return eggsPerCrate > 0 ? (qty / eggsPerCrate).toFixed(2) : "0.00"
}

/**
 * "2 crates + 15 loose priced as 2.50 crates" under the calculated amount.
 *
 * The price field is per crate while the sale is counted in crates and loose
 * eggs, so without this the total looks wrong to anyone checking it by eye.
 */
function EggPriceNote({ show, crates, loose }: { show: boolean; crates: number; loose: number }) {
  if (!show || crates + loose <= 0) return null
  return (
    <p className="text-xs text-slate-500">
      {crates} crate{crates === 1 ? "" : "s"}{loose > 0 && ` + ${loose} loose`} priced as{" "}
      {((crates * 30 + loose) / 30).toFixed(2)} crates
      {loose > 0 && " — loose eggs charged pro rata"}.
    </p>
  )
}

export default function SalesPage() {
  const router = useRouter()
  const [sales, setSales] = useState<Sale[]>([])
  const [loading, setLoading] = useState(true)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const [currentPage, setCurrentPage] = useState(1)
  const [itemsPerPage, setItemsPerPage] = useState(10)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }
  const [isCreateDialogOpen, setIsCreateDialogOpen] = useState(false)
  const [isEditDialogOpen, setIsEditDialogOpen] = useState(false)
  const [isInvoiceDialogOpen, setIsInvoiceDialogOpen] = useState(false)
  const [editingSale, setEditingSale] = useState<Sale | null>(null)
  const [selectedSale, setSelectedSale] = useState<Sale | null>(null)
  // Record-payment dialog (partial payments against a credit sale).
  const [payDialog, setPayDialog] = useState<{ open: boolean; sale: Sale | null }>({ open: false, sale: null })
  // Which sale we are showing the payment ledger for. The dialog is the one
  // the Customer Balances page uses, scoped to a single sale, so a payment
  // reads the same wherever it is opened from.
  const [historySale, setHistorySale] = useState<Sale | null>(null)
  const { can } = usePermissions()
  const canReversePayments = can("poultry.customer-payments.reverse")
  const [payAmount, setPayAmount] = useState("")
  const [payMethod, setPayMethod] = useState("Cash")
  const [payNote, setPayNote] = useState("")
  const [paySaving, setPaySaving] = useState(false)
  const [flocks, setFlocks] = useState<any[]>([])
  const [customers, setCustomers] = useState<any[]>([])
  const [cashAccounts, setCashAccounts] = useState<PoultryCashAccount[]>([])
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
    paid: true,
    size: null,
    poultryCashAccountId: null,
  })

  const productOptions = ["Fresh Eggs", "Chicken", "Manure", "Other"]
  const paymentMethodOptions = ["Cash", "Credit Card", "Bank Transfer", "Check", "Mobile Money"]

  const [productSelection, setProductSelection] = useState<string | undefined>(undefined)
  const [productOther, setProductOther] = useState("")
  // Currency is a company-level setting (Setup > Company). Subscribing to the
  // store means this page re-renders when it changes there, and can never
  // disagree with the reports.
  const { code: farmCurrencyCode } = useCurrency()
  const currencyCode = farmCurrencyCode || getSelectedCurrency()
  const [searchCustomer, setSearchCustomer] = useState("")
  // ?saleId= from the Customer Balances page. Held in state rather than read
  // from the URL on every render so clearing it does not need a navigation.
  const [focusSaleId, setFocusSaleId] = useState<number | null>(null)
  const [dateFrom, setDateFrom] = useState("")
  const [dateTo, setDateTo] = useState("")
  const [filtersOpen, setFiltersOpen] = useState(false)
  const [draftDateFrom, setDraftDateFrom] = useState("")
  const [draftDateTo, setDraftDateTo] = useState("")
  const hasDraftChanges = draftDateFrom !== dateFrom || draftDateTo !== dateTo
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
    // Cash accounts so a sale can be received into one (posts a cash-in when paid).
    listPoultryCashAccounts().then((a) => setCashAccounts(a.filter((x) => x.isActive))).catch(() => setCashAccounts([]))

    // Deep link from Customer Balances -> Open sale.
    if (typeof window !== 'undefined') {
      const sid = Number(new URLSearchParams(window.location.search).get('saleId'))
      if (Number.isFinite(sid) && sid > 0) setFocusSaleId(sid)
    }

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
          title: "Session issue",
          description: "We could not confirm your farm or user. Please sign in again.",
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
          title: "Session issue",
          description: "We could not confirm your farm or user. Please sign in again.",
          variant: "destructive",
        })
        return
      }
      
      if (!validateSaleForm()) return

      if (!formData.poultryCashAccountId) {
        toast({
          title: "Cash account required",
          description: "Choose which cash account this sale is received into.",
          variant: "destructive",
        })
        return
      }

      const quantity = Number(formData.quantity ?? 0)
      const unitPrice = Number(formData.unitPrice ?? 0)
      const calculatedAmount = saleLineTotal(quantity, unitPrice, isEggsProduct)
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
        paid: formData.paid ?? true,
        size: formData.size?.trim() ? formData.size.trim() : null,
        poultryCashAccountId: formData.poultryCashAccountId ?? null,
      }

      const response = await createSale(saleData)
      if (response.success) {
        // "Paid now" → actually settle the sale, matching the Water flow.
        // The create already posted the cash-in, but the backend leaves
        // AmountPaid at 0, so without this the sale would still read as owed and
        // demand a manual "Record payment". Recording the full payment makes
        // AmountPaid catch up; spPoultrySaleCash_Sync reverses+reposts, so the
        // cash is never double-counted.
        const newSaleId = response.data?.saleId
        if (saleData.paid && totalAmount > 0 && newSaleId) {
          try {
            await recordPoultryPayment({
              saleId: newSaleId,
              amount: totalAmount,
              paymentMethod: saleData.paymentMethod || "Cash",
            })
          } catch (e: any) {
            toast({
              title: "Sale created — payment not recorded",
              description: e?.message ?? "Use the sale's Pay action to record it manually.",
              variant: "destructive",
            })
          }
        }
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
          title: "Session issue",
          description: "We could not confirm your farm or user. Please sign in again.",
          variant: "destructive",
        })
        return
      }
      
      if (!validateSaleForm()) return

      const quantity = Number(formData.quantity ?? 0)
      const unitPrice = Number(formData.unitPrice ?? 0)
      const calculatedAmount = saleLineTotal(quantity, unitPrice, isEggsProduct)
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
        paid: formData.paid ?? true,
        size: formData.size?.trim() ? formData.size.trim() : null,
        poultryCashAccountId: formData.poultryCashAccountId ?? null,
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

  // Default new sales to the "Main Cash Account" (falls back to the first active
  // account) so every sale posts cash automatically.
  const defaultCashAccountId = useMemo(() => {
    const main = cashAccounts.find((a) => a.accountName.trim().toLowerCase() === "main cash account")
    return (main ?? cashAccounts[0])?.poultryCashAccountId ?? null
  }, [cashAccounts])

  // When the add dialog is open (or accounts finish loading while it's open),
  // preselect the default cash account if none is chosen yet.
  useEffect(() => {
    if (isCreateDialogOpen && defaultCashAccountId != null) {
      setFormData((prev) => (prev.poultryCashAccountId ? prev : { ...prev, poultryCashAccountId: defaultCashAccountId }))
    }
  }, [isCreateDialogOpen, defaultCashAccountId])

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
      paid: true,
      size: null,
      poultryCashAccountId: defaultCashAccountId,
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

  const clearFilters = () => {
    setSearchCustomer("")
    setDateFrom("")
    setDateTo("")
    setDraftDateFrom("")
    setDraftDateTo("")
  }

  const syncDraftFromCommitted = () => {
    setDraftDateFrom(dateFrom)
    setDraftDateTo(dateTo)
  }

  const applyMobileFilters = () => {
    setDateFrom(draftDateFrom)
    setDateTo(draftDateTo)
    setCurrentPage(1)
    setFiltersOpen(false)
    toast({ title: "Filters applied", description: "Sales list updated." })
  }

  const validateSaleForm = () => {
    const product = (formData.product ?? "").toString().trim()
    const quantity = Number(formData.quantity ?? 0)
    const unitPrice = Number(formData.unitPrice ?? 0)
    const paymentMethod = (formData.paymentMethod ?? "").toString().trim()
    const customerName = (formData.customerName ?? "").toString().trim()

    let message = ""

    if (!formData.saleDate) message = "Pick the date this sale happened."
    else if (!product) message = "Choose what was sold (eggs, chicken, manure, or other)."
    else if (!customerName) message = "Enter or select who bought from you."
    else if (!Number.isFinite(quantity) || quantity <= 0) message = "Enter how many units were sold — use a number greater than zero."
    else if (!Number.isFinite(unitPrice) || unitPrice <= 0) message = "Enter the price per unit — it must be greater than zero."
    else if (!paymentMethod) message = "Select how the customer paid (cash, mobile money, bank, etc.)."

    if (message) {
      toastFormGuide(toast, message)
      return false
    }

    return true
  }

  const getFlockLabel = (flockId?: number | null) => {
    if (flockId === 0 || flockId === null || typeof flockId === "undefined") return "All flocks"
    const match = flocks.find((flock) => flock.flockId === flockId)
    return match ? `${match.name}` : `#${flockId}`
  }

  // Amount still owed on a sale (falls back to paid/unpaid when amountPaid is
  // absent, e.g. an older backend).
  const salePaid = (s: Sale) => {
    const total = Number(s.totalAmount) || 0
    return s.amountPaid != null ? Number(s.amountPaid) : (s.paid === false ? 0 : total)
  }

  const saleOwed = (s: Sale) => Math.max(0, (Number(s.totalAmount) || 0) - salePaid(s))

  const openPaymentDialog = (sale: Sale) => {
    const owed = saleOwed(sale)
    setPayDialog({ open: true, sale })
    setPayAmount(owed > 0 ? owed.toFixed(2) : "")
    setPayMethod("Cash")
    setPayNote("")
  }

  const recordPayment = async () => {
    const sale = payDialog.sale
    if (!sale) return
    const amount = parseFloat(payAmount)
    if (!amount || amount <= 0) { toast({ title: "Enter a valid amount", variant: "destructive" }); return }
    setPaySaving(true)
    try {
      await recordPoultryPayment({ saleId: sale.saleId, amount, paymentMethod: payMethod || null, note: payNote || null })
      toast({ title: "Payment recorded", description: `${amount.toFixed(2)} received for sale #${sale.saleId}.` })
      setPayDialog({ open: false, sale: null })
      loadSales()
    } catch (e: any) {
      toast({ title: "Payment failed", description: e?.message ?? String(e), variant: "destructive" })
    } finally { setPaySaving(false) }
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
      // Null from the API for a sale with no description; the form is
      // controlled, so it has to be a string all the way down.
      saleDescription: sale.saleDescription ?? "",
      paid: sale.paid ?? true,
      size: sale.size ?? null,
      poultryCashAccountId: sale.poultryCashAccountId ?? null,
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
    const total = saleLineTotal(Number(formData.quantity) || 0, unitPrice, isEggsProduct)
    setFormData(prev => ({ ...prev, totalAmount: total }))
  }

  useEffect(() => {
    calculateTotal()
  }, [formData.quantity, formData.unitPrice, isEggsProduct])

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

  const buildSalesPdfOpts = (): PdfExportOptions => {
    const periodLabel = dateFrom || dateTo
      ? `Period: ${dateFrom || "—"} to ${dateTo || "—"}`
      : "Period: All time"
    return {
      title: "Sales Report",
      filename: "sales",
      farmName: farmInfo.name,
      columns: [
        { header: "Sale ID" },
        { header: "Date" },
        { header: "Customer" },
        { header: "Product" },
        { header: "Qty", align: "right" },
        { header: "Unit price", align: "right" },
        { header: "Total", align: "right" },
        { header: "Paid", align: "right" },
        { header: "Balance", align: "right" },
        { header: "Method" },
        { header: "Status" },
        { header: "Flock" },
      ],
      rows: filteredSales.map((s) => [
        `#${s.saleId}`,
        formatDateShort(s.saleDate),
        s.customerName ?? "",
        s.product ?? "",
        s.quantity ?? 0,
        formatCurrency(s.unitPrice ?? 0, currencyCode),
        formatCurrency(s.totalAmount ?? 0, currencyCode),
        formatCurrency(salePaid(s), currencyCode),
        formatCurrency(saleOwed(s), currencyCode),
        s.paymentMethod ?? "",
        paymentStatusOf(s),
        getFlockLabel(s.flockId),
      ]),
      totalsRow: [
        "",
        "",
        "",
        "TOTALS",
        totalQuantity.toLocaleString(),
        "",
        formatCurrency(totalSales, currencyCode),
        formatCurrency(filteredSales.reduce((sum, s) => sum + salePaid(s), 0), currencyCode),
        formatCurrency(filteredSales.reduce((sum, s) => sum + saleOwed(s), 0), currencyCode),
        "",
        "",
        "",
      ],
      summaryLines: [
        periodLabel,
        `Total sales: ${formatCurrency(totalSales, currencyCode)}  |  Total quantity: ${totalQuantity.toLocaleString()}  |  Transactions: ${filteredSales.length}`,
      ],
      headFillColor: [22, 163, 74],
    }
  }

  const handleExportSalesPdf = async () => {
    if (filteredSales.length === 0) {
      toast({ title: "Nothing to export", description: "No sales match the current filters.", variant: "destructive" })
      return
    }
    try {
      await exportTableToPdf(buildSalesPdfOpts())
    } catch (err) {
      toast({ title: "PDF export failed", description: "Could not generate PDF. Please try again.", variant: "destructive" })
    }
  }

  const [emailingReport, setEmailingReport] = useState(false)
  const handleEmailSalesReport = async () => {
    if (filteredSales.length === 0) {
      toast({ title: "Nothing to email", description: "No sales match the current filters.", variant: "destructive" })
      return
    }
    setEmailingReport(true)
    try {
      const res = await emailTableAsPdf(buildSalesPdfOpts())
      if (res.success) toast({ title: "Report emailed", description: `Sent to ${res.recipient}.` })
      else toast({ title: "Email failed", description: res.message || "Could not send report.", variant: "destructive" })
    } finally {
      setEmailingReport(false)
    }
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
          <title>Invoice ${saleInvoiceNumber(selectedSale.saleId)}</title>
          <style>${SALE_INVOICE_PRINT_STYLES}</style>
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
      // Deep link from Customer Balances -> Open sale. Narrowing to the single
      // sale is the point of the link, so it wins over the other filters (the
      // banner below offers the way back out).
      if (focusSaleId !== null) return sale.saleId === focusSaleId
      if (query) {
        const matchesCustomer = sale.customerName?.toLowerCase().includes(query)
        const matchesProduct = sale.product?.toLowerCase().includes(query)
        if (!matchesCustomer && !matchesProduct) return false
      }
      if (dateFrom && toLocalDateKey(sale.saleDate) < dateFrom) return false
      if (dateTo && toLocalDateKey(sale.saleDate) > dateTo) return false
      return true
    })
  }, [sales, searchCustomer, dateFrom, dateTo, focusSaleId])

  const sortedSales = useMemo(() => sortData(filteredSales, sortKey, sortDir, (item: any, key: string) => {
    switch (key) {
      case "saleDate": return new Date(item.saleDate)
      case "quantity": return Number(item.quantity) || 0
      case "unitPrice": return Number(item.unitPrice) || 0
      case "totalAmount": return Number(item.totalAmount) || 0
      case "amountPaid": return salePaid(item as Sale)
      case "balance": return saleOwed(item as Sale)
      case "paymentStatus": return paymentStatusOf(item as Sale)
      default: return (item as any)[key]
    }
  }), [filteredSales, sortKey, sortDir])
  // Pagination logic
  const totalPages = Math.max(1, Math.ceil(sortedSales.length / itemsPerPage))
  const safePage = Math.min(currentPage, totalPages)
  const startIndex = (safePage - 1) * itemsPerPage
  const endIndex = startIndex + itemsPerPage
  const paginatedSales = useMemo(
    () => sortedSales.slice(startIndex, endIndex),
    [sortedSales, startIndex, endIndex]
  )

  // Reset to page 1 when filters change
  useEffect(() => {
    setCurrentPage(1)
  }, [searchCustomer, dateFrom, dateTo])

  const handlePageChange = (page: number) => setCurrentPage(page)
  const handlePreviousPage = () => { if (safePage > 1) setCurrentPage(safePage - 1) }
  const handleNextPage = () => { if (safePage < totalPages) setCurrentPage(safePage + 1) }

  const getPageNumbers = () => {
    const pages: (number | string)[] = []
    if (totalPages <= 7) {
      for (let i = 1; i <= totalPages; i++) pages.push(i)
    } else {
      if (safePage <= 3) {
        for (let i = 1; i <= 4; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      } else if (safePage >= totalPages - 2) {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = totalPages - 3; i <= totalPages; i++) pages.push(i)
      } else {
        pages.push(1)
        pages.push("ellipsis")
        for (let i = safePage - 1; i <= safePage + 1; i++) pages.push(i)
        pages.push("ellipsis")
        pages.push(totalPages)
      }
    }
    return pages
  }
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
      <div className="flex-1 flex flex-col min-w-0">
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
          <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col gap-4 overflow-hidden p-4 sm:p-6">
            <DialogHeader className="shrink-0">
              <DialogTitle>Create New Sale</DialogTitle>
              <DialogDescription>
                Add a new sale record to track your farm&apos;s revenue
              </DialogDescription>
            </DialogHeader>
            <div className="min-h-0 flex-1 overflow-y-auto space-y-5 py-1 pr-2">
              {/* Section: Sale Details */}
              <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Sale Details</div>
                <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2">
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
                  <div className="space-y-2">
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

              {/* Section: Egg Quantity (conditional) */}
              {isEggsProduct && (
                <div className="rounded-xl border border-amber-200 overflow-hidden">
                  <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                  <div className="grid grid-cols-1 gap-4 p-4 bg-amber-50 sm:grid-cols-2 lg:grid-cols-3">
                    <div className="space-y-2">
                      <Label htmlFor="crates" className="text-sm">Crates (30 eggs)</Label>
                      <NumberInput
                        id="crates"
                        
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
                      <NumberInput
                        id="looseEggs"
                        
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
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                    <div className="space-y-2">
                      <Label htmlFor="quantity">{isEggsProduct ? "Quantity (In crates) *" : "Quantity *"}</Label>
                      {/* Eggs are priced per crate, so the box shows the crate
                          equivalent of the count above (75 eggs -> 2.50). It is
                          read-only for eggs; `formData.quantity` stays in eggs. */}
                      <NumberInput
                        id="quantity"
                        step={isEggsProduct ? "0.01" : undefined}
                        value={isEggsProduct ? eggCratesEquivalent(formData.quantity) : formData.quantity}
                        onChange={(e) => setFormData(prev => ({ ...prev, quantity: Number(e.target.value) }))}
                        placeholder="0"
                        disabled={isEggsProduct}
                        className={isEggsProduct ? "bg-slate-100" : ""}
                      />
                      {isEggsProduct && (
                        <p className="text-xs text-slate-500">
                          {(Number(formData.quantity) || 0).toLocaleString()} eggs total, from the crates and loose eggs above
                        </p>
                      )}
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="unitPrice">{isEggsProduct ? "Unit Price Per Crate *" : "Unit Price *"}</Label>
                      <NumberInput
                        id="unitPrice"
                        
                        step="0.01"
                        value={formData.unitPrice}
                        onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: Number(e.target.value) }))}
                        placeholder="0.00"
                      />
                    </div>
                  </div>
                  <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                    <div className="space-y-2">
                      <Label htmlFor="totalAmount">Calculated Amount</Label>
                      <NumberInput
                        id="totalAmount"
                        
                        step="0.01"
                        value={formData.totalAmount}
                        readOnly
                        className="bg-slate-100"
                      />
                      <EggPriceNote show={isEggsProduct} crates={crates} loose={looseEggs} />
                    </div>
                    <div className="space-y-2">
                      <Label htmlFor="overrideAmount">Override Amount</Label>
                      <NumberInput
                        id="overrideAmount"
                        
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
                  <div className="grid gap-2 md:grid-cols-2">
                    <div className="rounded-md border bg-white px-3 py-2">
                      <Label className="mb-2 block text-sm">Payment status</Label>
                      <div className="flex flex-wrap items-center gap-4">
                        <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
                          <input
                            type="radio"
                            name="create-payment-status"
                            className="h-4 w-4"
                            checked={formData.paid !== false}
                            onChange={() => setFormData(prev => ({ ...prev, paid: true }))}
                          />
                          Paid now
                        </label>
                        <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
                          <input
                            type="radio"
                            name="create-payment-status"
                            className="h-4 w-4"
                            checked={formData.paid === false}
                            onChange={() => setFormData(prev => ({ ...prev, paid: false }))}
                          />
                          Pay later (pending)
                        </label>
                      </div>
                      <p className="text-xs text-slate-500 mt-1.5">
                        {formData.paid === false
                          ? "Records the full amount as owed — record payments later."
                          : "Records the sale as fully paid and posts a cash-in."}
                      </p>
                    </div>
                    <div className="rounded-md border bg-white px-3 py-2 space-y-1">
                      <Label htmlFor="saleSize">Egg Size (optional)</Label>
                      <Input
                        id="saleSize"
                        list="egg-size-suggestions"
                        value={formData.size ?? ""}
                        onChange={(e) => setFormData(prev => ({ ...prev, size: e.target.value }))}
                        placeholder="e.g. Inside, Tee, Serum"
                      />
                      <datalist id="egg-size-suggestions">
                        <option value="Inside" />
                        <option value="Tee" />
                        <option value="Serum" />
                        <option value="Small" />
                        <option value="Medium" />
                        <option value="Large" />
                        <option value="XLarge" />
                        <option value="Jumbo" />
                      </datalist>
                      <p className="text-xs text-slate-500">Used by the weekly report&apos;s &ldquo;Egg Sales by Size&rdquo; card.</p>
                    </div>
                  </div>
                  <div className="space-y-2">
                    <Label htmlFor="cashAccount">Receive into cash account *</Label>
                    <Select
                      value={formData.poultryCashAccountId ? String(formData.poultryCashAccountId) : "none"}
                      onValueChange={(value) => setFormData(prev => ({ ...prev, poultryCashAccountId: value === "none" ? null : Number(value) }))}
                    >
                      <SelectTrigger id="cashAccount">
                        <SelectValue placeholder="Select a cash account" />
                      </SelectTrigger>
                      <SelectContent>
                        {cashAccounts.map((a) => (
                          <SelectItem key={a.poultryCashAccountId} value={String(a.poultryCashAccountId)}>
                            {a.accountName} ({a.currentBalance.toFixed(2)})
                          </SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                    <p className="text-xs text-slate-500">Posts a cash-in and increases the account balance when the sale is marked paid.</p>
                  </div>
                </div>
              </div>

              {/* Description */}
              <div className="space-y-2">
                <Label htmlFor="saleDescription">Description</Label>
                <Textarea
                  id="saleDescription"
                  value={formData.saleDescription ?? ""}
                  onChange={(e) => setFormData(prev => ({ ...prev, saleDescription: e.target.value }))}
                  placeholder="Additional notes about this sale"
                />
              </div>
            </div>
            <div className="shrink-0 flex flex-col gap-2 pt-3 border-t sm:flex-row sm:justify-end">
              <Button onClick={() => setIsCreateDialogOpen(false)} className="w-full bg-red-600 hover:bg-red-700 text-white sm:w-auto">
                Cancel
              </Button>
              <Button onClick={handleCreateSale} className="w-full bg-blue-600 hover:bg-blue-700 sm:w-auto">Create Sale</Button>
            </div>
          </DialogContent>
        </Dialog>
      </div>

            {/* Arrived here from Customer Balances -> Open sale. Say so, and
                give a one-click way back to the whole list. */}
            {focusSaleId !== null && (
              <div className="mb-3 flex flex-wrap items-center justify-between gap-2 rounded-md border border-sky-200 bg-sky-50 px-3 py-2 text-sm text-sky-900">
                <span>Showing sale <strong>S{focusSaleId}</strong> only.</span>
                <Button variant="ghost" size="sm" onClick={() => setFocusSaleId(null)}>Show all sales</Button>
              </div>
            )}

            {/* Filters */}
            {isMobile ? (
              <div className="space-y-3 w-full min-w-0">
                <div className="relative">
                  <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-slate-400" />
                  <Input placeholder="Search customer or product" value={searchCustomer} onChange={(e) => setSearchCustomer(e.target.value)} className="pl-10 h-11" />
                </div>
                <div className={MOBILE_FILTERS_TOOLBAR_ROW_CLASS}>
                  <Sheet
                    open={filtersOpen}
                    onOpenChange={(open) => {
                      setFiltersOpen(open)
                      syncDraftFromCommitted()
                    }}
                  >
                    <SheetTrigger asChild>
                      <Button variant="outline" className={MOBILE_FILTERS_TRIGGER_BUTTON_CLASS}>
                        <Filter className="h-4 w-4" />
                        <span className="truncate">Filters</span>
                        {(!!searchCustomer || !!dateFrom || !!dateTo) && (
                          <span className="ml-1 h-5 min-w-[20px] px-1.5 rounded-full bg-orange-500 text-white text-xs flex items-center justify-center">
                            {[searchCustomer, dateFrom, dateTo].filter(Boolean).length}
                          </span>
                        )}
                      </Button>
                    </SheetTrigger>
                    <SheetContent side="bottom" className={MOBILE_FILTER_SHEET_CONTENT_CLASS}>
                      <MobileFilterSheetHeader />
                      <MobileFilterSheetBody>
                        <div className="space-y-3">
                          <p className="text-sm font-medium text-slate-700">Date range</p>
                          <div className="flex flex-col gap-4">
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="sales-filter-from" className="text-xs font-medium text-slate-500">
                                Start date
                              </label>
                              <Input
                                id="sales-filter-from"
                                type="date"
                                value={draftDateFrom}
                                onChange={(e) => setDraftDateFrom(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                            <div className="min-w-0 space-y-2">
                              <label htmlFor="sales-filter-to" className="text-xs font-medium text-slate-500">
                                End date
                              </label>
                              <Input
                                id="sales-filter-to"
                                type="date"
                                value={draftDateTo}
                                onChange={(e) => setDraftDateTo(e.target.value)}
                                className="h-12 min-w-0 w-full text-base"
                              />
                            </div>
                          </div>
                        </div>
                        <div className="space-y-2">
                          <label className="text-sm font-medium text-slate-700">Currency</label>
                          {/* Read-only: currency is a company setting, so it is
                              chosen once in Setup > Company and every screen
                              follows it. It used to be editable here and wrote
                              to a separate localStorage key, which is why this
                              page could disagree with the reports. */}
                          <div className="flex h-12 items-center justify-between rounded-md border border-slate-200 bg-slate-50 px-3 text-base text-slate-700">
                            <span>{currencyCode}</span>
                            <Link href="/poultry-setup" className="text-sm font-medium text-amber-700 underline">Change</Link>
                          </div>
                        </div>
                      </MobileFilterSheetBody>
                      <MobileFilterSheetFooter>
                        <div className="flex gap-3">
                          <Button
                            type="button"
                            variant="outline"
                            className="h-12 flex-1"
                            onClick={() => {
                              clearFilters()
                              setFiltersOpen(false)
                              toast({ title: "Filters cleared" })
                            }}
                          >
                            Clear all
                          </Button>
                          <Button type="button" className="h-12 flex-1" onClick={applyMobileFilters} disabled={!hasDraftChanges}>
                            Apply
                          </Button>
                        </div>
                      </MobileFilterSheetFooter>
                    </SheetContent>
                  </Sheet>
                  <Button variant="outline" size="sm" onClick={handleExportSalesPdf} className="gap-2 h-11 px-4">
                    <Download className="h-4 w-4" />
                    PDF
                  </Button>
                  <Button variant="outline" size="sm" onClick={handleEmailSalesReport} disabled={emailingReport} className="gap-2 h-11 px-4">
                    {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />}
                    Email
                  </Button>
                </div>
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
                <div className="flex h-9 w-[140px] items-center justify-between rounded-md border border-slate-200 bg-slate-50 px-3 text-sm text-slate-700">
                  <span>{currencyCode}</span>
                  <Link href="/poultry-setup" className="text-xs font-medium text-amber-700 underline">Change</Link>
                </div>
              </div>
              <div className="ml-auto flex items-center gap-2">
                <Button variant="outline" size="sm" onClick={handleExportSalesPdf} className="gap-2">
                  <Download className="h-4 w-4" />
                  Export PDF
                </Button>
                <Button variant="outline" size="sm" onClick={handleEmailSalesReport} disabled={emailingReport} className="gap-2">
                  {emailingReport ? <Loader2 className="h-4 w-4 animate-spin" /> : <Mail className="h-4 w-4" />}
                  Email Report
                </Button>
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
                    {eggCrateBreakdown(totalQuantity, { long: true }) ?? "—"}
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
                        <Collapsible key={sale.saleId} defaultOpen className={cn("group rounded-xl border shadow-sm overflow-hidden", idx % 2 === 0 ? "bg-amber-100 border-amber-300" : "bg-white border-slate-200")}>
                          <div className={cn("p-4 active:bg-slate-50/80 transition-colors", idx % 2 === 1 && "bg-slate-50/20")}>
                            <CollapsibleTrigger asChild>
                              <div className="flex items-start justify-between gap-3 cursor-pointer">
                                <div className="min-w-0 flex-1">
                                  <div className="flex items-center gap-2">
                                    {/* Same order as the table: the id, then the date. */}
                                    <span className="text-xs tabular-nums text-slate-500">#{sale.saleId}</span>
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
                                  <div><span className="text-slate-500">Flock</span> <span className="font-medium">{getFlockLabel(sale.flockId)}</span></div>
                                  <div><span className="text-slate-500">Paid</span> <span className="font-medium tabular-nums text-emerald-700">{formatCurrency(salePaid(sale), currencyCode)}</span></div>
                                  <div><span className="text-slate-500">Balance</span> <span className={cn("font-medium tabular-nums", saleOwed(sale) > 0 ? "text-amber-700" : "text-slate-400")}>{formatCurrency(saleOwed(sale), currencyCode)}</span></div>
                                  <div><span className="text-slate-500">Method</span> <span className="font-medium">{sale.paymentMethod}</span></div>
                                  <div className="flex items-center gap-2"><span className="text-slate-500">Status</span> <PaymentStatusBadge sale={sale} /></div>
                                </div>
                                {/* Two per row, not one flex line: four labelled
                                    buttons overflow a 375px card and the card's
                                    overflow-hidden silently clipped Invoice. */}
                                <div className="grid grid-cols-2 gap-2 pt-2">
                                  {saleOwed(sale) > 0 && (
                                    <Button variant="outline" size="sm" className="h-10 w-full text-emerald-700 border-emerald-200 hover:bg-emerald-50" onClick={() => openPaymentDialog(sale)}>
                                      <Wallet className="h-4 w-4 mr-2" /> Pay
                                    </Button>
                                  )}
                                  <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => openEditDialog(sale)}>
                                    <Edit className="h-4 w-4 mr-2" /> Edit
                                  </Button>
                                  <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => openInvoiceDialog(sale)}>
                                    <FileText className="h-4 w-4 mr-2" /> Invoice
                                  </Button>
                                  <Button variant="outline" size="sm" className="h-10 w-full" onClick={() => setHistorySale(sale)}>
                                    <History className="h-4 w-4 mr-2" /> Payments
                                  </Button>
                                  <Button variant="outline" size="sm" className="h-10 w-full text-red-600 border-red-200 hover:bg-red-50" onClick={() => openDeleteSaleDialog(sale.saleId)}>
                                    <Trash2 className="h-4 w-4 mr-2" /> Delete
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
                  <Table className={cn("w-full", !isMobile && "min-w-[1240px]")}>
                    <TableHeader>
                      <TableRow>
                        <SortableHeader label="Sale ID" sortKey="saleId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Date" sortKey="saleDate" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} className={cn(isMobile && "sticky-col-date bg-slate-50")} />
                        <SortableHeader label="Product" sortKey="product" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Customer" sortKey="customerName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Flock" sortKey="flockId" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Quantity" sortKey="quantity" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Unit Price" sortKey="unitPrice" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Total" sortKey="totalAmount" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Paid" sortKey="amountPaid" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Balance" sortKey="balance" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Method" sortKey="paymentMethod" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <SortableHeader label="Status" sortKey="paymentStatus" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                        <TableHead className={cn("min-w-[140px] whitespace-nowrap", isMobile && "sticky-col-actions bg-slate-50")}>Actions</TableHead>
                      </TableRow>
                    </TableHeader>
                    <TableBody>
                      {paginatedSales.map((sale) => (
                        <TableRow key={sale.saleId}>
                          <TableCell className="whitespace-nowrap tabular-nums text-slate-500">#{sale.saleId}</TableCell>
                          <TableCell className={cn("bg-white", isMobile && "sticky-col-date")}>{isMobile ? formatDateShort(sale.saleDate) : new Date(sale.saleDate).toLocaleDateString()}</TableCell>
                          <TableCell>{sale.product}</TableCell>
                          <TableCell>{sale.customerName}</TableCell>
                          <TableCell>{getFlockLabel(sale.flockId)}</TableCell>
                          <TableCell className="whitespace-nowrap">
                            {sale.quantity}
                            {sale.product?.toLowerCase().includes("egg") && eggCrateBreakdown(sale.quantity) && (
                              // Inline, not `block`: the crate breakdown reads as a
                              // unit of the number it follows, so stacking it made
                              // the row two lines tall for one value.
                              <span className="ml-1.5 text-xs text-slate-500">
                                ({eggCrateBreakdown(sale.quantity)})
                              </span>
                            )}
                          </TableCell>
                          <TableCell>{formatCurrency(sale.unitPrice, currencyCode)}</TableCell>
                          <TableCell className="font-medium">{formatCurrency(sale.totalAmount, currencyCode)}</TableCell>
                          <TableCell className="tabular-nums text-emerald-700">{formatCurrency(salePaid(sale), currencyCode)}</TableCell>
                          <TableCell className={cn("tabular-nums", saleOwed(sale) > 0 ? "font-semibold text-amber-700" : "text-slate-400")}>
                            {formatCurrency(saleOwed(sale), currencyCode)}
                          </TableCell>
                          <TableCell>
                            <Badge variant="outline" className="w-fit">{sale.paymentMethod}</Badge>
                          </TableCell>
                          <TableCell><PaymentStatusBadge sale={sale} /></TableCell>
                          <TableCell className={cn("whitespace-nowrap bg-white", isMobile && "sticky-col-actions")}>
                            {/* Icon-only actions, so each one says what it does on
                                hover. The mobile card view below uses labelled
                                buttons instead — tooltips don't open on touch. */}
                            <div className="flex items-center gap-1 min-w-[100px]">
                              {saleOwed(sale) > 0 && (
                                <Tooltip>
                                  <TooltipTrigger asChild>
                                    <Button
                                      variant="ghost"
                                      size="sm"
                                      className="text-emerald-700 hover:text-emerald-800 hover:bg-emerald-50"
                                      onClick={() => openPaymentDialog(sale)}
                                      aria-label="Record payment"
                                    >
                                      <Wallet className="h-4 w-4" />
                                    </Button>
                                  </TooltipTrigger>
                                  <TooltipContent side="top">
                                    Record payment · {formatCurrency(saleOwed(sale), currencyCode)} owed
                                  </TooltipContent>
                                </Tooltip>
                              )}
                              {/* Always offered, including on a settled sale:
                                  a paid-off sale is exactly when someone asks
                                  what was paid and when. */}
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => setHistorySale(sale)}
                                    aria-label="Payment history"
                                  >
                                    <History className="h-4 w-4" />
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent side="top">Payment history</TooltipContent>
                              </Tooltip>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => openEditDialog(sale)}
                                    aria-label="Edit sale"
                                  >
                                    <Edit className="h-4 w-4" />
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent side="top">Edit sale</TooltipContent>
                              </Tooltip>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => openDeleteSaleDialog(sale.saleId)}
                                    aria-label="Delete sale"
                                  >
                                    <Trash2 className="h-4 w-4" />
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent side="top">Delete sale</TooltipContent>
                              </Tooltip>
                              <Tooltip>
                                <TooltipTrigger asChild>
                                  <Button
                                    variant="ghost"
                                    size="sm"
                                    onClick={() => openInvoiceDialog(sale)}
                                    aria-label="View invoice"
                                  >
                                    <FileText className="h-4 w-4" />
                                  </Button>
                                </TooltipTrigger>
                                <TooltipContent side="top">View invoice</TooltipContent>
                              </Tooltip>
                            </div>
                          </TableCell>
                        </TableRow>
                      ))}
                    </TableBody>
                  </Table>
                  </div>
                  )}
                {/* Pagination */}
                {!loading && filteredSales.length > 0 && (
                  <div className="flex flex-col sm:flex-row items-center justify-between gap-4 px-4 py-3 border-t bg-slate-50">
                    <div className="flex items-center gap-4">
                      <span className="text-sm text-slate-600">
                        Showing {startIndex + 1} to {Math.min(endIndex, sortedSales.length)} of {sortedSales.length} records
                      </span>
                      <Select value={String(itemsPerPage)} onValueChange={(v) => { setItemsPerPage(Number(v)); setCurrentPage(1) }}>
                        <SelectTrigger className="w-[100px] h-8"><SelectValue /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="5">5 / page</SelectItem>
                          <SelectItem value="10">10 / page</SelectItem>
                          <SelectItem value="15">15 / page</SelectItem>
                          <SelectItem value="25">25 / page</SelectItem>
                          <SelectItem value="50">50 / page</SelectItem>
                          <SelectItem value="100">100 / page</SelectItem>
                        </SelectContent>
                      </Select>
                    </div>
                    <Pagination>
                      <PaginationContent>
                        <PaginationItem>
                          <PaginationPrevious onClick={handlePreviousPage} className={safePage === 1 ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                        </PaginationItem>
                        {getPageNumbers().map((page, index) => (
                          <PaginationItem key={index}>
                            {page === "ellipsis" ? (
                              <PaginationEllipsis />
                            ) : (
                              <PaginationLink onClick={() => handlePageChange(page as number)} isActive={safePage === page} className="cursor-pointer">{page}</PaginationLink>
                            )}
                          </PaginationItem>
                        ))}
                        <PaginationItem>
                          <PaginationNext onClick={handleNextPage} className={safePage === totalPages ? "pointer-events-none opacity-50" : "cursor-pointer"} />
                        </PaginationItem>
                      </PaginationContent>
                    </Pagination>
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
              <DialogContent className="w-[95vw] max-w-[1600px] max-h-[90vh] flex flex-col gap-4 overflow-hidden p-4 sm:p-6">
                <DialogHeader className="shrink-0">
                  <DialogTitle>Edit Sale</DialogTitle>
                  <DialogDescription>
                    Update the sale record details
                  </DialogDescription>
                </DialogHeader>
                <div className="min-h-0 flex-1 overflow-y-auto space-y-5 py-1 pr-2">
                  {/* Section: Sale Details */}
                  <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
                    <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">Sale Details</div>
                    <div className="grid grid-cols-1 gap-4 p-4 sm:grid-cols-2">
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
                      <div className="space-y-2">
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

                  {/* Section: Egg Quantity (conditional) */}
                  {isEggsProduct && (
                    <div className="rounded-xl border border-amber-200 overflow-hidden">
                      <div className="bg-amber-500 px-4 py-2 text-sm font-semibold text-white">Egg Quantity (Crates × 30 + Loose Eggs)</div>
                      <div className="grid grid-cols-1 gap-4 p-4 bg-amber-50 sm:grid-cols-2 lg:grid-cols-3">
                        <div className="space-y-2">
                          <Label htmlFor="edit-crates" className="text-sm">Crates (30 eggs)</Label>
                          <NumberInput
                            id="edit-crates"
                            
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
                          <NumberInput
                            id="edit-looseEggs"
                            
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
                      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2">
                        <div className="space-y-2">
                          <Label htmlFor="edit-quantity">{isEggsProduct ? "Quantity (In crates) *" : "Quantity *"}</Label>
                          {/* Eggs are priced per crate, so the box shows the crate
                              equivalent of the count above (75 eggs -> 2.50). It is
                              read-only for eggs; `formData.quantity` stays in eggs. */}
                          <NumberInput
                            id="edit-quantity"
                            step={isEggsProduct ? "0.01" : undefined}
                            value={isEggsProduct ? eggCratesEquivalent(formData.quantity) : formData.quantity}
                            onChange={(e) => setFormData(prev => ({ ...prev, quantity: Number(e.target.value) }))}
                            placeholder="0"
                            disabled={isEggsProduct}
                            className={isEggsProduct ? "bg-slate-100" : ""}
                          />
                          {isEggsProduct && (
                            <p className="text-xs text-slate-500">
                              {(Number(formData.quantity) || 0).toLocaleString()} eggs total, from the crates and loose eggs above
                            </p>
                          )}
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-unitPrice">{isEggsProduct ? "Unit Price Per Crate *" : "Unit Price *"}</Label>
                          <NumberInput
                            id="edit-unitPrice"
                            
                            step="0.01"
                            value={formData.unitPrice}
                            onChange={(e) => setFormData(prev => ({ ...prev, unitPrice: Number(e.target.value) }))}
                            placeholder="0.00"
                          />
                        </div>
                      </div>
                      <div className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
                        <div className="space-y-2">
                          <Label htmlFor="edit-totalAmount">Calculated Amount</Label>
                          <NumberInput
                            id="edit-totalAmount"
                            
                            step="0.01"
                            value={formData.totalAmount}
                            readOnly
                            className="bg-slate-100"
                          />
                          <EggPriceNote show={isEggsProduct} crates={crates} loose={looseEggs} />
                        </div>
                        <div className="space-y-2">
                          <Label htmlFor="edit-overrideAmount">Override Amount</Label>
                          <NumberInput
                            id="edit-overrideAmount"
                            
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
                      <div className="rounded-md border bg-white px-3 py-2">
                        <Label className="mb-2 block text-sm">Payment status</Label>
                        <div className="flex flex-wrap items-center gap-4">
                          <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
                            <input
                              type="radio"
                              name="edit-payment-status"
                              className="h-4 w-4"
                              checked={formData.paid !== false}
                              onChange={() => setFormData(prev => ({ ...prev, paid: true }))}
                            />
                            Paid
                          </label>
                          <label className="inline-flex items-center gap-2 text-sm cursor-pointer">
                            <input
                              type="radio"
                              name="edit-payment-status"
                              className="h-4 w-4"
                              checked={formData.paid === false}
                              onChange={() => setFormData(prev => ({ ...prev, paid: false }))}
                            />
                            Pending (owed)
                          </label>
                        </div>
                        <p className="text-xs text-slate-500 mt-1.5">Choose &ldquo;Pending&rdquo; if this sale is still owed by the customer.</p>
                      </div>
                      <div className="space-y-2">
                        <Label htmlFor="edit-cashAccount">Receive into cash account</Label>
                        <Select
                          value={formData.poultryCashAccountId ? String(formData.poultryCashAccountId) : "none"}
                          onValueChange={(value) => setFormData(prev => ({ ...prev, poultryCashAccountId: value === "none" ? null : Number(value) }))}
                        >
                          <SelectTrigger id="edit-cashAccount">
                            <SelectValue placeholder="None (no cash movement)" />
                          </SelectTrigger>
                          <SelectContent>
                            <SelectItem value="none">None (no cash movement)</SelectItem>
                            {cashAccounts.map((a) => (
                              <SelectItem key={`edit-${a.poultryCashAccountId}`} value={String(a.poultryCashAccountId)}>
                                {a.accountName} ({a.currentBalance.toFixed(2)})
                              </SelectItem>
                            ))}
                          </SelectContent>
                        </Select>
                        <p className="text-xs text-slate-500">Posts a cash-in and increases the account balance when the sale is marked paid.</p>
                      </div>
                    </div>
                  </div>

                  {/* Description */}
                  <div className="space-y-2">
                    <Label htmlFor="edit-saleDescription">Description</Label>
                    <Textarea
                      id="edit-saleDescription"
                      value={formData.saleDescription ?? ""}
                      onChange={(e) => setFormData(prev => ({ ...prev, saleDescription: e.target.value }))}
                      placeholder="Additional notes about this sale"
                    />
                  </div>
                </div>
                <div className="shrink-0 flex flex-col gap-2 pt-3 border-t sm:flex-row sm:justify-end">
                  <Button onClick={() => setIsEditDialogOpen(false)} className="w-full bg-red-600 hover:bg-red-700 text-white sm:w-auto">
                    Cancel
                  </Button>
                  <Button onClick={handleUpdateSale} className="w-full bg-blue-600 hover:bg-blue-700 sm:w-auto">Update Sale</Button>
                </div>
              </DialogContent>
            </Dialog>

            {/* Invoice Dialog */}
            <Dialog open={isInvoiceDialogOpen} onOpenChange={closeInvoiceDialog}>
              {/* Sized to the document (820px) rather than the old 1600px, which
                  left the invoice floating in a wide empty band. */}
              <DialogContent className={cn("w-[95vw] max-w-[920px] max-h-[90vh] overflow-y-auto", isMobile ? "p-3" : "")}>
                <DialogHeader className={cn(isMobile && "text-left")}>
                  <DialogTitle>Sale invoice</DialogTitle>
                  <DialogDescription className={cn(isMobile && "sr-only")}>
                    Review the tax invoice and print or save a PDF for your customer.
                  </DialogDescription>
                </DialogHeader>

                {selectedSale ? (
                  <div className="space-y-4">
                    {/* Just the action — invoice number, date, customer, payment
                        and status all appear in the document itself below, so
                        repeating them here was noise. */}
                    <div className="flex justify-end">
                      <Button onClick={handlePrintInvoice} className={cn("gap-2", isMobile && "w-full justify-center h-11")}>
                        <Printer className="h-4 w-4" />
                        Print invoice
                      </Button>
                    </div>

                    {/* The grey "desk" the sheet sits on is a desktop nicety —
                        on a phone it's just padding stacked on the dialog's own,
                        so the sheet goes edge to edge there instead. */}
                    <div ref={invoicePrintRef} id="invoice-print-area" className="rounded-lg bg-transparent p-0 sm:bg-slate-100 sm:p-6">
                      <SaleInvoiceDocument
                        sale={selectedSale}
                        farm={{
                          name: farmInfo.name,
                          address: farmInfo.address || undefined,
                          phone: farmInfo.phone || undefined,
                          email: farmInfo.email || undefined,
                        }}
                        currencyCode={currencyCode}
                        formatMoney={formatCurrency}
                        flockLabel={getFlockLabel(selectedSale.flockId)}
                      />
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

      {/* Record payment dialog */}
      {/* The ledger for one sale: every payment that touched it, with the
          balance it moved from and to. Reversing from here re-reads the list,
          because the sale's Paid and Balance change with it. */}
      <PaymentHistoryDialog
        open={!!historySale}
        onOpenChange={(o) => { if (!o) setHistorySale(null) }}
        module="poultry"
        side="customer"
        partyName={historySale?.customerName ?? null}
        documentType="Sale"
        documentId={historySale?.saleId ?? null}
        canReverse={canReversePayments}
        onReversed={() => { loadSales() }}
      />

      <Dialog open={payDialog.open} onOpenChange={(o) => setPayDialog((p) => ({ ...p, open: o }))}>
        <DialogContent className="max-w-md">
          <DialogHeader>
            <DialogTitle>Record payment</DialogTitle>
          </DialogHeader>
          {payDialog.sale && (
            <div className="space-y-4">
              <div className="rounded-lg bg-slate-50 border border-slate-200 p-3 text-sm space-y-1">
                <div className="flex justify-between"><span className="text-slate-500">Sale</span><span className="font-medium">#{payDialog.sale.saleId} · {payDialog.sale.customerName || "Walk-in"}</span></div>
                <div className="flex justify-between"><span className="text-slate-500">Total</span><span className="tabular-nums">{Number(payDialog.sale.totalAmount).toFixed(2)}</span></div>
                <div className="flex justify-between"><span className="text-slate-500">Owed</span><span className="tabular-nums font-semibold text-amber-700">{saleOwed(payDialog.sale).toFixed(2)}</span></div>
              </div>
              <div className="grid grid-cols-1 sm:grid-cols-2 gap-4">
                <div className="space-y-2">
                  <Label htmlFor="pay-amount">Amount *</Label>
                  <Input id="pay-amount" type="number" step="0.01" min="0" value={payAmount} onChange={(e) => setPayAmount(e.target.value)} />
                </div>
                <div className="space-y-2">
                  <Label>Method</Label>
                  <Select value={payMethod} onValueChange={setPayMethod}>
                    <SelectTrigger className="w-full"><SelectValue placeholder="Select method" /></SelectTrigger>
                    <SelectContent>
                      {["Cash", "Mobile Money", "Bank Transfer", "Cheque", "Other"].map((m) => <SelectItem key={m} value={m}>{m}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <div className="space-y-2">
                <Label htmlFor="pay-note">Note</Label>
                <Input id="pay-note" value={payNote} onChange={(e) => setPayNote(e.target.value)} placeholder="Optional" />
              </div>
            </div>
          )}
          <div className="flex justify-end gap-2 pt-2">
            <Button variant="outline" onClick={() => setPayDialog({ open: false, sale: null })} disabled={paySaving}>Cancel</Button>
            <Button onClick={recordPayment} disabled={paySaving} className="bg-emerald-600 hover:bg-emerald-700">{paySaving ? "Saving…" : "Record payment"}</Button>
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

// Derived payment status for a poultry sale — mirrors the Water module's
// Pending/PartiallyPaid/Paid model. Falls back to the binary `paid` flag when an
// older backend hasn't populated `amountPaid`.
function paymentStatusOf(s: Sale): "Paid" | "Partial" | "Pending" {
  const total = Number(s.totalAmount) || 0
  const paidAmt = s.amountPaid != null ? Number(s.amountPaid) : (s.paid === false ? 0 : total)
  if (paidAmt <= 0) return "Pending"
  if (paidAmt + 0.001 < total) return "Partial"
  return "Paid"
}

function PaymentStatusBadge({ sale }: { sale: Sale }) {
  const status = paymentStatusOf(sale)
  const cls: Record<string, string> = {
    Paid: "bg-emerald-100 text-emerald-700",
    Partial: "bg-amber-100 text-amber-700",
    Pending: "bg-slate-100 text-slate-700",
  }
  return (
    <span className={cn("inline-flex w-fit rounded-full px-2 py-0.5 text-xs font-medium", cls[status])}>
      {status}
    </span>
  )
}

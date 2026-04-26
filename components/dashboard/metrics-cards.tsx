"use client"

import { useEffect, useState } from "react"
import { Card, CardContent } from "@/components/ui/card"
import { TrendingUp, TrendingDown, Users, DollarSign, CheckSquare, Package, Egg, Bird, Activity, TrendingUp as ProfitIcon } from "lucide-react"
import { getDashboardSummary, type DashboardSummary } from "@/lib/api/dashboard"
import { getSales } from "@/lib/api"
import { getUserContext } from "@/lib/utils/user-context"
import { formatCurrency } from "@/lib/utils/currency"

interface MetricCardProps {
  title: string
  value: string
  change: string
  changeType: "increase" | "decrease" | "neutral"
  icon: React.ComponentType<{ className?: string }>
  iconColor: string
}

function MetricCard({ title, value, change, changeType, icon: Icon, iconColor }: MetricCardProps) {
  return (
    <Card className="bg-white rounded-xl border border-slate-200 shadow-sm">
      <CardContent className="p-4">
        <div className="flex items-start justify-between gap-3">
          <div className="min-w-0 flex-1">
            <p className="text-xs font-medium text-slate-500 uppercase tracking-wider">{title}</p>
            <p className="text-lg sm:text-xl font-bold text-slate-900 mt-1 leading-tight truncate">{value}</p>
            <div className="flex items-center mt-1">
              {changeType === "increase" && <TrendingUp className="h-4 w-4 text-green-500 mr-1" />}
              {changeType === "decrease" && <TrendingDown className="h-4 w-4 text-red-500 mr-1" />}
              <span className={`text-xs ${
                changeType === "increase" ? "text-green-600" : 
                changeType === "decrease" ? "text-red-600" : 
                "text-slate-600"
              }`}>
                {change}
              </span>
            </div>
          </div>
          <div className={`w-10 h-10 rounded-lg ${iconColor} flex items-center justify-center shrink-0`}>
            <Icon className="w-5 h-5 text-white" />
          </div>
        </div>
      </CardContent>
    </Card>
  )
}

export function MetricsCards() {
  const [summary, setSummary] = useState<DashboardSummary | null>(null)
  const [salesData, setSalesData] = useState<any>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")

  useEffect(() => {
    loadDashboardData()
  }, [])

  const loadDashboardData = async () => {
    const { farmId, userId } = getUserContext()
    
    if (!farmId) {
      setError("Farm ID not found")
      setLoading(false)
      return
    }

    if (!userId) {
      setError("User ID not found")
      setLoading(false)
      return
    }

    try {
      // Load dashboard summary and sales data in parallel
      const [summaryResult, salesResult] = await Promise.all([
        getDashboardSummary(farmId, userId),
        getSales(userId, farmId)
      ])
      
      if (summaryResult.success && summaryResult.data) {
        setSummary(summaryResult.data)
      } else {
        setError(summaryResult.message)
      }

      if (salesResult.success && salesResult.data) {
        setSalesData(salesResult.data)
      }
    } catch (error) {
      setError("Failed to load dashboard data")
    }
    
    setLoading(false)
  }

  if (loading) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        {[...Array(8)].map((_, index) => (
          <Card key={index} className="bg-white">
            <CardContent className="p-4">
              <div className="animate-pulse">
                <div className="h-4 bg-slate-200 rounded mb-2"></div>
                <div className="h-6 bg-slate-200 rounded mb-2"></div>
                <div className="h-4 bg-slate-200 rounded w-3/4"></div>
              </div>
            </CardContent>
          </Card>
        ))}
      </div>
    )
  }

  if (error) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Card className="bg-white col-span-full">
          <CardContent className="p-6 text-center">
            <p className="text-red-600">Error loading dashboard data: {error}</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  if (!summary) {
    return (
      <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
        <Card className="bg-white col-span-full">
          <CardContent className="p-6 text-center">
            <p className="text-slate-600">No dashboard data available</p>
          </CardContent>
        </Card>
      </div>
    )
  }

  // Safe value extraction with fallbacks
  const safeValue = (value: any, fallback: number = 0) => {
    if (typeof value === 'number' && !isNaN(value)) {
      return value
    }
    return fallback
  }

  // Calculate sales metrics
  const calculateSalesMetrics = () => {
    if (!salesData || !Array.isArray(salesData)) {
      return {
        totalSales: 0,
        totalTransactions: 0,
        averageSale: 0,
        thisMonthSales: 0
      }
    }

    const now = new Date()
    const thisMonth = now.getMonth()
    const thisYear = now.getFullYear()

    const totalSales = salesData.reduce((sum: number, sale: any) => sum + (sale.totalAmount || 0), 0)
    const totalTransactions = salesData.length
    const averageSale = totalTransactions > 0 ? totalSales / totalTransactions : 0

    const thisMonthSales = salesData
      .filter((sale: any) => {
        const saleDate = new Date(sale.saleDate)
        return saleDate.getMonth() === thisMonth && saleDate.getFullYear() === thisYear
      })
      .reduce((sum: number, sale: any) => sum + (sale.totalAmount || 0), 0)

    return {
      totalSales,
      totalTransactions,
      averageSale,
      thisMonthSales
    }
  }

  const salesMetrics = calculateSalesMetrics()

  // Calculate metrics without percentage changes
  const metrics = [
    {
      title: "TOTAL CUSTOMERS",
      value: safeValue(summary.totalCustomers).toLocaleString(),
      change: "Total registered customers",
      changeType: "neutral" as const,
      icon: Users,
      iconColor: "bg-blue-500"
    },
    {
      title: "TOTAL PRODUCTION",
      value: safeValue(summary.totalProduction).toLocaleString(),
      change: "Overall production count",
      changeType: "neutral" as const,
      icon: Activity,
      iconColor: "bg-green-500"
    },
    {
      title: "TOTAL EGGS",
      value: safeValue(summary.totalEggs).toLocaleString(),
      change: "Total eggs produced",
      changeType: "neutral" as const,
      icon: Egg,
      iconColor: "bg-orange-500"
    },
    {
      title: "ACTIVE FLOCKS",
      value: safeValue(summary.activeFlocks).toString(),
      change: "Currently active flocks",
      changeType: "neutral" as const,
      icon: Bird,
      iconColor: "bg-purple-500"
    }
  ]

  const allMetrics: MetricCardProps[] = [
    ...metrics,
    {
      title: "TOTAL SALES",
      value: formatCurrency(salesMetrics.totalSales),
      change: `${salesMetrics.totalTransactions} transactions`,
      changeType: "neutral",
      icon: DollarSign,
      iconColor: "bg-green-600",
    },
    {
      title: "THIS MONTH SALES",
      value: formatCurrency(salesMetrics.thisMonthSales),
      change: "Sales for current month",
      changeType: "neutral",
      icon: TrendingUp,
      iconColor: "bg-blue-600",
    },
    {
      title: "AVERAGE SALE",
      value: formatCurrency(salesMetrics.averageSale),
      change: "Average transaction value",
      changeType: "neutral",
      icon: Package,
      iconColor: "bg-purple-500",
    },
    {
      title: "PRODUCTION EFFICIENCY",
      value: `${safeValue(summary.productionEfficiency).toFixed(1)}%`,
      change: "Overall efficiency rating",
      changeType: "neutral",
      icon: CheckSquare,
      iconColor: "bg-indigo-500",
    },
  ]

  return (
    <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
      {allMetrics.map((metric, index) => (
        <MetricCard key={index} {...metric} />
      ))}
    </div>
  )
}
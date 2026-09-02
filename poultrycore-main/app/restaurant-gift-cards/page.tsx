"use client"
import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { Loader2, Plus, Gift, CreditCard, DollarSign, Search, RefreshCw, ArrowRightLeft, History } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { StatCard } from "@/components/restaurant/stat-card"
import { EmptyState } from "@/components/restaurant/empty-state"
import { PageHeader } from "@/components/restaurant/page-header"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listGiftCards, createGiftCard, checkGiftCardBalance, getGiftCardStats,
  redeemGiftCard, reloadGiftCard, getGiftCardTransactions,
  type GiftCard, type GiftCardTx, type GiftCardStats, type GiftCardRedeemResult, type GiftCardCreateInput,
} from "@/lib/api/restaurant"

const STATUS_COLORS: Record<string, string> = {
  Active: "bg-green-100 text-green-700",
  Redeemed: "bg-purple-100 text-purple-700",
  Expired: "bg-red-100 text-red-700",
  Disabled: "bg-gray-100 text-gray-700",
}

export default function RestaurantGiftCardsPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [cards, setCards] = useState<GiftCard[]>([])
  const [stats, setStats] = useState<GiftCardStats | null>(null)
  const [search, setSearch] = useState("")
  const [saving, setSaving] = useState(false)

  // Dialogs
  const [issueOpen, setIssueOpen] = useState(false)
  const [checkOpen, setCheckOpen] = useState(false)
  const [redeemOpen, setRedeemOpen] = useState(false)
  const [reloadOpen, setReloadOpen] = useState(false)
  const [txOpen, setTxOpen] = useState(false)

  // Issue form
  const [issueForm, setIssueForm] = useState<GiftCardCreateInput>({
    cardType: "Digital", amount: 0, purchaserName: "", purchaserPhone: "",
    recipientName: "", recipientEmail: "", message: "", expiryDate: "",
  })

  // Check balance
  const [checkNumber, setCheckNumber] = useState("")
  const [checkResult, setCheckResult] = useState<GiftCard | null>(null)
  const [checking, setChecking] = useState(false)

  // Redeem
  const [redeemCard, setRedeemCard] = useState<GiftCard | null>(null)
  const [redeemAmount, setRedeemAmount] = useState("")
  const [redeemOrderId, setRedeemOrderId] = useState("")

  // Reload
  const [reloadCard, setReloadCard] = useState<GiftCard | null>(null)
  const [reloadAmount, setReloadAmount] = useState("")

  // Transactions
  const [txCard, setTxCard] = useState<GiftCard | null>(null)
  const [transactions, setTransactions] = useState<GiftCardTx[]>([])
  const [txLoading, setTxLoading] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
  }, [activeFarmType, router])

  const fetchData = async () => {
    try {
      setLoading(true)
      const [c, s] = await Promise.all([listGiftCards(), getGiftCardStats()])
      setCards(c)
      setStats(s)
    } catch {
      toast({ title: "Error", description: "Failed to load gift cards", variant: "destructive" })
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => {
    if (activeFarmType === "Restaurant") fetchData()
  }, [activeFarmType])

  const filtered = cards.filter((c) =>
    c.cardNumber.toLowerCase().includes(search.toLowerCase())
  )

  // --- Issue Card ---
  const handleIssue = async () => {
    if (!issueForm.amount || issueForm.amount <= 0) {
      toast({ title: "Validation", description: "Amount is required", variant: "destructive" }); return
    }
    try {
      setSaving(true)
      const result = await createGiftCard(issueForm)
      toast({ title: "Card Issued", description: `Card ${result.cardNumber} created successfully` })
      setIssueOpen(false)
      setIssueForm({ cardType: "Digital", amount: 0, purchaserName: "", purchaserPhone: "", recipientName: "", recipientEmail: "", message: "", expiryDate: "" })
      fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e.message || "Failed to issue card", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // --- Check Balance ---
  const handleCheck = async () => {
    if (!checkNumber.trim()) return
    try {
      setChecking(true)
      const res = await checkGiftCardBalance(checkNumber.trim())
      setCheckResult(res)
      if (!res) toast({ title: "Not Found", description: "No card found with that number", variant: "destructive" })
    } catch {
      toast({ title: "Error", description: "Failed to check balance", variant: "destructive" })
    } finally {
      setChecking(false)
    }
  }

  // --- Redeem ---
  const handleRedeem = async () => {
    if (!redeemCard || !redeemAmount || Number(redeemAmount) <= 0) return
    try {
      setSaving(true)
      const res = await redeemGiftCard(redeemCard.cardNumber, Number(redeemAmount), redeemOrderId ? Number(redeemOrderId) : undefined)
      if (res.success) {
        toast({ title: "Redeemed", description: `${res.message} - New balance: $${res.newBalance.toFixed(2)}` })
        setRedeemOpen(false)
        setRedeemCard(null); setRedeemAmount(""); setRedeemOrderId("")
        fetchData()
      } else {
        toast({ title: "Failed", description: res.message, variant: "destructive" })
      }
    } catch (e: any) {
      toast({ title: "Error", description: e.message || "Redemption failed", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // --- Reload ---
  const handleReload = async () => {
    if (!reloadCard || !reloadAmount || Number(reloadAmount) <= 0) return
    try {
      setSaving(true)
      await reloadGiftCard(reloadCard.cardNumber, Number(reloadAmount))
      toast({ title: "Reloaded", description: `$${Number(reloadAmount).toFixed(2)} added to ${reloadCard.cardNumber}` })
      setReloadOpen(false)
      setReloadCard(null); setReloadAmount("")
      fetchData()
    } catch (e: any) {
      toast({ title: "Error", description: e.message || "Reload failed", variant: "destructive" })
    } finally {
      setSaving(false)
    }
  }

  // --- Transactions ---
  const openTransactions = async (card: GiftCard) => {
    setTxCard(card)
    setTxOpen(true)
    setTxLoading(true)
    try {
      const txs = await getGiftCardTransactions(card.giftCardId)
      setTransactions(txs)
    } catch {
      toast({ title: "Error", description: "Failed to load transactions", variant: "destructive" })
    } finally {
      setTxLoading(false)
    }
  }

  if (loading) return <PageSkeleton statCards={4} listRows={5} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Header */}
            <PageHeader icon={Gift} title="Gift Cards" subtitle="Issue, manage, and redeem gift cards">
              <Button variant="outline" onClick={() => { setCheckOpen(true); setCheckNumber(""); setCheckResult(null) }}>
                <Search className="h-4 w-4 mr-2" /> Check Balance
              </Button>
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => setIssueOpen(true)}>
                <Plus className="h-4 w-4 mr-2" /> Issue Card
              </Button>
            </PageHeader>

            {/* Stats Row */}
            <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
              <StatCard label="Total Cards" value={stats?.totalCards ?? 0} icon={CreditCard} color="rose" />
              <StatCard label="Active Cards" value={stats?.activeCards ?? 0} icon={Gift} color="green" />
              <StatCard label="Total Issued" value={`$${(stats?.totalIssued ?? 0).toFixed(2)}`} icon={DollarSign} color="blue" />
              <StatCard label="Total Redeemed" value={`$${(stats?.totalRedeemed ?? 0).toFixed(2)}`} icon={ArrowRightLeft} color="purple" />
            </div>

            {/* Search */}
            {cards.length > 0 && (
              <div className="relative max-w-sm">
                <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-gray-400" />
                <Input
                  placeholder="Search by card number..."
                  value={search}
                  onChange={(e) => setSearch(e.target.value)}
                  className="pl-9 h-10"
                />
              </div>
            )}

            {/* Card List or Empty */}
            {cards.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState
                    icon={Gift}
                    title="No gift cards issued yet"
                    description="Issue digital or physical gift cards for your customers"
                    actionLabel="Issue First Card"
                    onAction={() => setIssueOpen(true)}
                  />
                </CardContent>
              </Card>
            ) : filtered.length === 0 ? (
              <Card>
                <CardContent className="pt-6">
                  <EmptyState icon={Search} title="No cards match your search" description="Try a different card number" />
                </CardContent>
              </Card>
            ) : (
              <Card>
                <CardContent className="pt-4 divide-y">
                  {filtered.map((card) => (
                    <div
                      key={card.giftCardId}
                      className="flex items-center gap-4 py-3 cursor-pointer hover:bg-gray-50 rounded-lg px-2 -mx-2 transition-colors"
                      onClick={() => openTransactions(card)}
                    >
                      <div className="h-10 w-10 rounded-lg bg-rose-50 flex items-center justify-center shrink-0">
                        <Gift className="h-5 w-5 text-rose-500" />
                      </div>
                      <div className="flex-1 min-w-0">
                        <div className="flex items-center gap-2">
                          <span className="font-mono font-semibold text-sm">{card.cardNumber}</span>
                          <Badge variant="outline" className="text-xs">
                            {card.cardType}
                          </Badge>
                          <Badge className={`text-xs ${STATUS_COLORS[card.status] ?? STATUS_COLORS.Disabled}`}>
                            {card.status}
                          </Badge>
                        </div>
                        <div className="flex items-center gap-3 text-xs text-muted-foreground mt-0.5">
                          <span>${card.initialBalance.toFixed(2)} &rarr; ${card.currentBalance.toFixed(2)}</span>
                          {card.purchaserName && <span>From: {card.purchaserName}</span>}
                          {card.recipientName && <span>To: {card.recipientName}</span>}
                          {card.expiryDate && <span>Exp: {new Date(card.expiryDate).toLocaleDateString()}</span>}
                        </div>
                      </div>
                      <div className="flex items-center gap-1 shrink-0">
                        {card.status === "Active" && (
                          <>
                            <Button
                              variant="ghost" size="sm"
                              onClick={(e) => { e.stopPropagation(); setReloadCard(card); setReloadAmount(""); setReloadOpen(true) }}
                              title="Reload"
                            >
                              <RefreshCw className="h-4 w-4" />
                            </Button>
                            <Button
                              variant="ghost" size="sm"
                              onClick={(e) => { e.stopPropagation(); setRedeemCard(card); setRedeemAmount(""); setRedeemOrderId(""); setRedeemOpen(true) }}
                              title="Redeem"
                            >
                              <ArrowRightLeft className="h-4 w-4" />
                            </Button>
                          </>
                        )}
                        <Button variant="ghost" size="sm" onClick={(e) => { e.stopPropagation(); openTransactions(card) }} title="History">
                          <History className="h-4 w-4" />
                        </Button>
                      </div>
                    </div>
                  ))}
                </CardContent>
              </Card>
            )}
          </div>
        </main>
      </div>

      {/* ===== Issue Card Dialog ===== */}
      <Dialog open={issueOpen} onOpenChange={(v) => { setIssueOpen(v); if (!v) setIssueForm({ cardType: "Digital", amount: 0, purchaserName: "", purchaserPhone: "", recipientName: "", recipientEmail: "", message: "", expiryDate: "" }) }}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Issue Gift Card</DialogTitle>
            <DialogDescription>Create a new digital or physical gift card</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Card Type</Label>
              <Select value={issueForm.cardType ?? "Digital"} onValueChange={(v) => setIssueForm({ ...issueForm, cardType: v })}>
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="Digital">Digital</SelectItem>
                  <SelectItem value="Physical">Physical</SelectItem>
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Amount <span className="text-rose-500">*</span></Label>
              <Input type="number" step="0.01" min="0" placeholder="50.00" className="h-10"
                value={issueForm.amount || ""} onChange={(e) => setIssueForm({ ...issueForm, amount: Number(e.target.value) })} />
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5">
                <Label>Purchaser Name</Label>
                <Input className="h-10" value={issueForm.purchaserName ?? ""} onChange={(e) => setIssueForm({ ...issueForm, purchaserName: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Purchaser Phone</Label>
                <Input className="h-10" value={issueForm.purchaserPhone ?? ""} onChange={(e) => setIssueForm({ ...issueForm, purchaserPhone: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Recipient Name</Label>
                <Input className="h-10" value={issueForm.recipientName ?? ""} onChange={(e) => setIssueForm({ ...issueForm, recipientName: e.target.value })} />
              </div>
              <div className="space-y-1.5">
                <Label>Recipient Email</Label>
                <Input className="h-10" value={issueForm.recipientEmail ?? ""} onChange={(e) => setIssueForm({ ...issueForm, recipientEmail: e.target.value })} />
              </div>
            </div>
            <div className="space-y-1.5">
              <Label>Personal Message</Label>
              <Textarea placeholder="Happy Birthday! Enjoy your meal..." className="min-h-[60px]"
                value={issueForm.message ?? ""} onChange={(e) => setIssueForm({ ...issueForm, message: e.target.value })} />
            </div>
            <div className="space-y-1.5">
              <Label>Expiry Date</Label>
              <Input type="date" className="h-10" value={issueForm.expiryDate ?? ""} onChange={(e) => setIssueForm({ ...issueForm, expiryDate: e.target.value })} />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setIssueOpen(false)} disabled={saving}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleIssue} disabled={saving}>
              {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />} Issue Card
            </Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ===== Check Balance Dialog ===== */}
      <Dialog open={checkOpen} onOpenChange={(v) => { setCheckOpen(v); if (!v) { setCheckNumber(""); setCheckResult(null) } }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Check Gift Card Balance</DialogTitle>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Card Number</Label>
              <Input value={checkNumber} onChange={(e) => setCheckNumber(e.target.value)} placeholder="GC-XXXXXXXX" className="h-10" />
            </div>
            <Button className="bg-rose-600 hover:bg-rose-700 w-full" onClick={handleCheck} disabled={checking || !checkNumber.trim()}>
              {checking && <Loader2 className="h-4 w-4 mr-2 animate-spin" />} Check Balance
            </Button>
            {checkResult && (
              <Card className="border-green-200 bg-green-50">
                <CardContent className="py-3 px-4 space-y-1">
                  <div className="flex justify-between items-center">
                    <span className="font-mono font-semibold text-sm">{checkResult.cardNumber}</span>
                    <Badge className={STATUS_COLORS[checkResult.status] ?? STATUS_COLORS.Disabled}>{checkResult.status}</Badge>
                  </div>
                  <div className="text-2xl font-bold text-green-700">${checkResult.currentBalance.toFixed(2)}</div>
                  <p className="text-xs text-muted-foreground">Initial: ${checkResult.initialBalance.toFixed(2)}</p>
                </CardContent>
              </Card>
            )}
          </div>
        </DialogContent>
      </Dialog>

      {/* ===== Redeem Dialog ===== */}
      <Dialog open={redeemOpen} onOpenChange={(v) => { setRedeemOpen(v); if (!v) { setRedeemCard(null); setRedeemAmount(""); setRedeemOrderId("") } }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Redeem Gift Card</DialogTitle>
            <DialogDescription>Deduct balance from this gift card</DialogDescription>
          </DialogHeader>
          {redeemCard && (
            <div className="space-y-4">
              <div className="flex items-center justify-between p-3 rounded-lg bg-gray-50 border">
                <span className="font-mono font-semibold text-sm">{redeemCard.cardNumber}</span>
                <span className="font-bold text-green-700">${redeemCard.currentBalance.toFixed(2)}</span>
              </div>
              <div className="space-y-1.5">
                <Label>Amount <span className="text-rose-500">*</span></Label>
                <Input type="number" step="0.01" min="0" max={redeemCard.currentBalance} placeholder="0.00" className="h-10"
                  value={redeemAmount} onChange={(e) => setRedeemAmount(e.target.value)} />
              </div>
              <div className="space-y-1.5">
                <Label>Order ID <span className="text-xs text-muted-foreground">(optional)</span></Label>
                <Input type="number" placeholder="e.g. 1234" className="h-10"
                  value={redeemOrderId} onChange={(e) => setRedeemOrderId(e.target.value)} />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setRedeemOpen(false)} disabled={saving}>Cancel</Button>
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleRedeem} disabled={saving || !redeemAmount || Number(redeemAmount) <= 0}>
                  {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />} Redeem
                </Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* ===== Reload Dialog ===== */}
      <Dialog open={reloadOpen} onOpenChange={(v) => { setReloadOpen(v); if (!v) { setReloadCard(null); setReloadAmount("") } }}>
        <DialogContent className="sm:max-w-sm">
          <DialogHeader>
            <DialogTitle>Reload Gift Card</DialogTitle>
            <DialogDescription>Add funds to this gift card</DialogDescription>
          </DialogHeader>
          {reloadCard && (
            <div className="space-y-4">
              <div className="flex items-center justify-between p-3 rounded-lg bg-gray-50 border">
                <span className="font-mono font-semibold text-sm">{reloadCard.cardNumber}</span>
                <span className="font-bold text-green-700">${reloadCard.currentBalance.toFixed(2)}</span>
              </div>
              <div className="space-y-1.5">
                <Label>Amount <span className="text-rose-500">*</span></Label>
                <Input type="number" step="0.01" min="0" placeholder="25.00" className="h-10"
                  value={reloadAmount} onChange={(e) => setReloadAmount(e.target.value)} />
              </div>
              <DialogFooter>
                <Button variant="outline" onClick={() => setReloadOpen(false)} disabled={saving}>Cancel</Button>
                <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleReload} disabled={saving || !reloadAmount || Number(reloadAmount) <= 0}>
                  {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />} Reload
                </Button>
              </DialogFooter>
            </div>
          )}
        </DialogContent>
      </Dialog>

      {/* ===== Transaction History Dialog ===== */}
      <Dialog open={txOpen} onOpenChange={(v) => { setTxOpen(v); if (!v) { setTxCard(null); setTransactions([]) } }}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader>
            <DialogTitle>Transaction History</DialogTitle>
            {txCard && <DialogDescription>Card: {txCard.cardNumber}</DialogDescription>}
          </DialogHeader>
          {txLoading ? (
            <div className="flex justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-rose-500" /></div>
          ) : transactions.length === 0 ? (
            <div className="text-center py-8">
              <History className="h-10 w-10 mx-auto text-gray-300 mb-2" />
              <p className="text-sm text-muted-foreground">No transactions yet</p>
            </div>
          ) : (
            <div className="max-h-80 overflow-y-auto divide-y">
              {transactions.map((tx) => (
                <div key={tx.giftCardTxId} className="py-3 flex items-start justify-between gap-3">
                  <div className="min-w-0">
                    <div className="flex items-center gap-2">
                      <Badge variant="outline" className="text-xs">{tx.transactionType}</Badge>
                      {tx.orderId && <span className="text-xs text-muted-foreground">Order #{tx.orderId}</span>}
                    </div>
                    {tx.notes && <p className="text-xs text-muted-foreground mt-0.5">{tx.notes}</p>}
                    <p className="text-xs text-muted-foreground mt-0.5">{new Date(tx.createdAt).toLocaleString()}</p>
                  </div>
                  <div className="text-right shrink-0">
                    <div className={`font-semibold text-sm ${tx.amount >= 0 ? "text-green-700" : "text-red-600"}`}>
                      {tx.amount >= 0 ? "+" : ""}${tx.amount.toFixed(2)}
                    </div>
                    <div className="text-xs text-muted-foreground">Bal: ${tx.balanceAfter.toFixed(2)}</div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </DialogContent>
      </Dialog>
    </div>
  )
}

"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle, CardDescription } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter, DialogDescription } from "@/components/ui/dialog"
import { Switch } from "@/components/ui/switch"
import { Loader2, Crown, Settings, Users, Trophy, Plus, History, ArrowUpCircle, ArrowDownCircle } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { PageHeader } from "@/components/restaurant/page-header"
import { EmptyState } from "@/components/restaurant/empty-state"
import { StatCard } from "@/components/restaurant/stat-card"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  getLoyaltySettings, upsertLoyaltySettings, listLoyaltyAccounts, createLoyaltyAccount,
  getLoyaltyStats, earnPoints, redeemPoints, getLoyaltyTransactions,
  type LoyaltySettings, type LoyaltyAccount, type PointTransaction, type LoyaltyStats,
} from "@/lib/api/restaurant"

const TIER_META: Record<string, { icon: string; bg: string }> = {
  Bronze:   { icon: "\u{1F949}", bg: "bg-amber-100 text-amber-700 border-amber-200" },
  Silver:   { icon: "\u{1F948}", bg: "bg-gray-100 text-gray-700 border-gray-200" },
  Gold:     { icon: "\u{1F947}", bg: "bg-yellow-100 text-yellow-700 border-yellow-200" },
  Platinum: { icon: "\u{1F48E}", bg: "bg-purple-100 text-purple-700 border-purple-200" },
}

const DEFAULT_SETTINGS: Omit<LoyaltySettings, "loyaltySettingId" | "farmId" | "createdAt" | "updatedAt"> = {
  isEnabled: false, pointsPerCurrencyUnit: 1, pointsRedemptionRate: 0.01,
  minimumRedeemPoints: 100, pointsExpiryDays: 365, tiersEnabled: true,
  bronzeThreshold: 0, silverThreshold: 500, goldThreshold: 1000, platinumThreshold: 2500,
  bronzeMultiplier: 1, silverMultiplier: 1.5, goldMultiplier: 2, platinumMultiplier: 3,
  referralBonus: 50,
}

export default function RestaurantLoyaltyPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [saving, setSaving] = useState(false)
  const [stats, setStats] = useState<LoyaltyStats | null>(null)
  const [members, setMembers] = useState<LoyaltyAccount[]>([])
  const [settings, setSettings] = useState<typeof DEFAULT_SETTINGS>({ ...DEFAULT_SETTINGS })

  // dialogs
  const [enrollOpen, setEnrollOpen] = useState(false)
  const [enrollName, setEnrollName] = useState("")
  const [enrollPhone, setEnrollPhone] = useState("")
  const [enrollCustomerId, setEnrollCustomerId] = useState("")

  const [selectedMember, setSelectedMember] = useState<LoyaltyAccount | null>(null)
  const [earnOpen, setEarnOpen] = useState(false)
  const [earnPts, setEarnPts] = useState("")
  const [earnDesc, setEarnDesc] = useState("")
  const [earnOrderId, setEarnOrderId] = useState("")

  const [redeemOpen, setRedeemOpen] = useState(false)
  const [redeemPts, setRedeemPts] = useState("")
  const [redeemDesc, setRedeemDesc] = useState("")

  const [historyOpen, setHistoryOpen] = useState(false)
  const [transactions, setTransactions] = useState<PointTransaction[]>([])
  const [loadingTxns, setLoadingTxns] = useState(false)

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [s, m, st] = await Promise.all([
        getLoyaltySettings().catch(() => null),
        listLoyaltyAccounts().catch(() => [] as LoyaltyAccount[]),
        getLoyaltyStats().catch(() => null),
      ])
      if (s) {
        setSettings({
          isEnabled: s.isEnabled, pointsPerCurrencyUnit: s.pointsPerCurrencyUnit,
          pointsRedemptionRate: s.pointsRedemptionRate, minimumRedeemPoints: s.minimumRedeemPoints,
          pointsExpiryDays: s.pointsExpiryDays, tiersEnabled: s.tiersEnabled,
          bronzeThreshold: s.bronzeThreshold, silverThreshold: s.silverThreshold,
          goldThreshold: s.goldThreshold, platinumThreshold: s.platinumThreshold,
          bronzeMultiplier: s.bronzeMultiplier, silverMultiplier: s.silverMultiplier,
          goldMultiplier: s.goldMultiplier, platinumMultiplier: s.platinumMultiplier,
          referralBonus: s.referralBonus,
        })
      }
      setMembers(m)
      setStats(st)
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function loadMembers() {
    try { setMembers(await listLoyaltyAccounts()); setStats(await getLoyaltyStats()) } catch {}
  }

  async function saveSettings() {
    setSaving(true)
    try {
      await upsertLoyaltySettings(settings)
      toast({ title: "Settings saved" })
    } catch (e: any) {
      toast({ title: "Failed to save", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function handleEnroll() {
    if (!enrollName.trim()) { toast({ title: "Name is required", variant: "destructive" }); return }
    try {
      await createLoyaltyAccount(enrollName.trim(), enrollPhone.trim() || undefined, enrollCustomerId ? Number(enrollCustomerId) : undefined)
      toast({ title: "Member enrolled" })
      setEnrollOpen(false); setEnrollName(""); setEnrollPhone(""); setEnrollCustomerId("")
      loadMembers()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function handleEarn() {
    if (!selectedMember || !earnPts || Number(earnPts) <= 0) { toast({ title: "Enter valid points", variant: "destructive" }); return }
    try {
      await earnPoints(selectedMember.loyaltyAccountId, Number(earnPts), earnDesc.trim() || "Manual earn", earnOrderId ? Number(earnOrderId) : undefined)
      toast({ title: `${earnPts} points added` })
      setEarnOpen(false); setEarnPts(""); setEarnDesc(""); setEarnOrderId("")
      loadMembers()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function handleRedeem() {
    if (!selectedMember || !redeemPts || Number(redeemPts) <= 0) { toast({ title: "Enter valid points", variant: "destructive" }); return }
    try {
      await redeemPoints(selectedMember.loyaltyAccountId, Number(redeemPts), redeemDesc.trim() || "Manual redeem")
      toast({ title: `${redeemPts} points redeemed` })
      setRedeemOpen(false); setRedeemPts(""); setRedeemDesc("")
      loadMembers()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function openHistory(m: LoyaltyAccount) {
    setSelectedMember(m); setHistoryOpen(true); setLoadingTxns(true)
    try { setTransactions(await getLoyaltyTransactions(m.loyaltyAccountId)) }
    catch { setTransactions([]) }
    finally { setLoadingTxns(false) }
  }

  function tierBadge(tier: string) {
    const meta = TIER_META[tier] || TIER_META.Bronze
    return <Badge className={`${meta.bg} border`}>{meta.icon} {tier}</Badge>
  }

  function tierCount(tier: string): number {
    if (!stats) return 0
    if (tier === "Bronze") return stats.bronzeCount
    if (tier === "Silver") return stats.silverCount
    if (tier === "Gold") return stats.goldCount
    return stats.platinumCount
  }

  if (loading) {
    return (
      <div className="flex h-screen bg-gray-50">
        <DashboardSidebar />
        <div className="flex-1 flex flex-col overflow-hidden">
          <DashboardHeader />
          <main className="flex-1 overflow-y-auto p-6">
            <PageSkeleton statCards={4} listRows={5} />
          </main>
        </div>
      </div>
    )
  }

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">

            <PageHeader icon={Crown} title="Loyalty & Rewards" subtitle="Points, tiers, and customer rewards program" />

            {/* Tier Cards Row */}
            <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-4">
              {(["Bronze", "Silver", "Gold", "Platinum"] as const).map((tier) => {
                const meta = TIER_META[tier]
                return (
                  <Card key={tier} className="text-center">
                    <CardContent className="pt-6 pb-4">
                      <div className="text-3xl mb-2">{meta.icon}</div>
                      <h3 className="font-bold text-lg">{tier}</h3>
                      <p className="text-sm text-muted-foreground mt-1">
                        {tier === "Bronze" ? settings.bronzeThreshold
                          : tier === "Silver" ? settings.silverThreshold
                          : tier === "Gold" ? settings.goldThreshold
                          : settings.platinumThreshold}+ points
                      </p>
                      <Badge className={`mt-2 ${meta.bg} border`}>{tierCount(tier)} member{tierCount(tier) !== 1 ? "s" : ""}</Badge>
                    </CardContent>
                  </Card>
                )
              })}
            </div>

            {/* Tabs */}
            <Tabs defaultValue="settings" className="space-y-4">
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger value="settings" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Settings className="h-4 w-4 mr-2" />Program Settings
                </TabsTrigger>
                <TabsTrigger value="members" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Users className="h-4 w-4 mr-2" />Members
                </TabsTrigger>
              </TabsList>

              {/* ===== Settings Tab ===== */}
              <TabsContent value="settings">
                <Card>
                  <CardHeader>
                    <CardTitle className="text-lg">Loyalty Program Configuration</CardTitle>
                    <CardDescription>Set up how customers earn and redeem points</CardDescription>
                  </CardHeader>
                  <CardContent className="space-y-6">
                    {/* Enable toggle */}
                    <div className="flex items-center gap-3">
                      <Switch checked={settings.isEnabled} onCheckedChange={(v) => setSettings({ ...settings, isEnabled: v })} />
                      <Label className="font-medium">Program Enabled</Label>
                    </div>

                    {/* Core fields */}
                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="space-y-1.5">
                        <Label>Points per currency unit</Label>
                        <Input type="number" value={settings.pointsPerCurrencyUnit} onChange={(e) => setSettings({ ...settings, pointsPerCurrencyUnit: Number(e.target.value) })} className="h-10" />
                        <p className="text-xs text-muted-foreground">e.g. 1 point per $1 spent</p>
                      </div>
                      <div className="space-y-1.5">
                        <Label>Redemption rate</Label>
                        <Input type="number" step="0.01" value={settings.pointsRedemptionRate} onChange={(e) => setSettings({ ...settings, pointsRedemptionRate: Number(e.target.value) })} className="h-10" />
                        <p className="text-xs text-muted-foreground">Value of 1 point in currency</p>
                      </div>
                      <div className="space-y-1.5">
                        <Label>Min. redeem points</Label>
                        <Input type="number" value={settings.minimumRedeemPoints} onChange={(e) => setSettings({ ...settings, minimumRedeemPoints: Number(e.target.value) })} className="h-10" />
                      </div>
                    </div>

                    <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                      <div className="space-y-1.5">
                        <Label>Points expiry (days)</Label>
                        <Input type="number" value={settings.pointsExpiryDays} onChange={(e) => setSettings({ ...settings, pointsExpiryDays: Number(e.target.value) })} className="h-10" />
                      </div>
                      <div className="space-y-1.5">
                        <Label>Referral bonus</Label>
                        <Input type="number" value={settings.referralBonus} onChange={(e) => setSettings({ ...settings, referralBonus: Number(e.target.value) })} className="h-10" />
                        <p className="text-xs text-muted-foreground">Points for referring a friend</p>
                      </div>
                    </div>

                    {/* Tier config section */}
                    <div className="border-t pt-4 space-y-4">
                      <div className="flex items-center gap-3">
                        <Switch checked={settings.tiersEnabled} onCheckedChange={(v) => setSettings({ ...settings, tiersEnabled: v })} />
                        <Label className="font-medium">Tiers Enabled</Label>
                      </div>

                      {settings.tiersEnabled && (
                        <>
                          <div>
                            <h4 className="font-medium mb-3 text-sm text-muted-foreground">Tier Thresholds (lifetime points)</h4>
                            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                              <div className="space-y-1.5"><Label>{TIER_META.Bronze.icon} Bronze</Label><Input type="number" value={settings.bronzeThreshold} onChange={(e) => setSettings({ ...settings, bronzeThreshold: Number(e.target.value) })} className="h-10" /></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Silver.icon} Silver</Label><Input type="number" value={settings.silverThreshold} onChange={(e) => setSettings({ ...settings, silverThreshold: Number(e.target.value) })} className="h-10" /></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Gold.icon} Gold</Label><Input type="number" value={settings.goldThreshold} onChange={(e) => setSettings({ ...settings, goldThreshold: Number(e.target.value) })} className="h-10" /></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Platinum.icon} Platinum</Label><Input type="number" value={settings.platinumThreshold} onChange={(e) => setSettings({ ...settings, platinumThreshold: Number(e.target.value) })} className="h-10" /></div>
                            </div>
                          </div>

                          <div>
                            <h4 className="font-medium mb-3 text-sm text-muted-foreground">Tier Multipliers (earn rate)</h4>
                            <div className="grid grid-cols-2 md:grid-cols-4 gap-3">
                              <div className="space-y-1.5"><Label>{TIER_META.Bronze.icon} Bronze</Label><Input type="number" step="0.1" value={settings.bronzeMultiplier} onChange={(e) => setSettings({ ...settings, bronzeMultiplier: Number(e.target.value) })} className="h-10" /><p className="text-xs text-muted-foreground">x earn multiplier</p></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Silver.icon} Silver</Label><Input type="number" step="0.1" value={settings.silverMultiplier} onChange={(e) => setSettings({ ...settings, silverMultiplier: Number(e.target.value) })} className="h-10" /><p className="text-xs text-muted-foreground">x earn multiplier</p></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Gold.icon} Gold</Label><Input type="number" step="0.1" value={settings.goldMultiplier} onChange={(e) => setSettings({ ...settings, goldMultiplier: Number(e.target.value) })} className="h-10" /><p className="text-xs text-muted-foreground">x earn multiplier</p></div>
                              <div className="space-y-1.5"><Label>{TIER_META.Platinum.icon} Platinum</Label><Input type="number" step="0.1" value={settings.platinumMultiplier} onChange={(e) => setSettings({ ...settings, platinumMultiplier: Number(e.target.value) })} className="h-10" /><p className="text-xs text-muted-foreground">x earn multiplier</p></div>
                            </div>
                          </div>
                        </>
                      )}
                    </div>

                    <Button className="bg-rose-600 hover:bg-rose-700" onClick={saveSettings} disabled={saving}>
                      {saving && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}Save Settings
                    </Button>
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ===== Members Tab ===== */}
              <TabsContent value="members">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <div>
                      <CardTitle className="text-lg">Loyalty Members</CardTitle>
                      <CardDescription>Customers enrolled in the loyalty program</CardDescription>
                    </div>
                    <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setEnrollName(""); setEnrollPhone(""); setEnrollCustomerId(""); setEnrollOpen(true) }}>
                      <Plus className="h-4 w-4 mr-2" />Enroll Member
                    </Button>
                  </CardHeader>
                  <CardContent>
                    {members.length === 0 ? (
                      <EmptyState
                        icon={Trophy}
                        title="No loyalty members yet"
                        description="Enroll customers to start tracking points and rewards"
                        actionLabel="Enroll Member"
                        onAction={() => setEnrollOpen(true)}
                      />
                    ) : (
                      <div className="border rounded-lg divide-y">
                        {members.map((m) => (
                          <div key={m.loyaltyAccountId} className="flex items-center justify-between p-4 hover:bg-gray-50 transition-colors">
                            <div className="flex items-center gap-4">
                              <div className="h-10 w-10 rounded-full bg-rose-100 flex items-center justify-center text-rose-600 font-bold text-sm">
                                {m.customerName.charAt(0).toUpperCase()}
                              </div>
                              <div>
                                <div className="font-medium text-gray-900">{m.customerName}</div>
                                {m.customerPhone && <div className="text-sm text-muted-foreground">{m.customerPhone}</div>}
                              </div>
                            </div>
                            <div className="flex items-center gap-4">
                              {tierBadge(m.currentTier)}
                              <div className="text-right min-w-[100px]">
                                <div className="font-semibold text-gray-900">{m.totalPoints.toLocaleString()} pts</div>
                                <div className="text-xs text-muted-foreground">Lifetime: {m.lifetimePoints.toLocaleString()}</div>
                              </div>
                              <div className="flex items-center gap-1">
                                <Button variant="ghost" size="sm" title="Earn Points" onClick={() => { setSelectedMember(m); setEarnPts(""); setEarnDesc(""); setEarnOrderId(""); setEarnOpen(true) }}>
                                  <ArrowUpCircle className="h-4 w-4 text-green-600" />
                                </Button>
                                <Button variant="ghost" size="sm" title="Redeem Points" onClick={() => { setSelectedMember(m); setRedeemPts(""); setRedeemDesc(""); setRedeemOpen(true) }}>
                                  <ArrowDownCircle className="h-4 w-4 text-red-500" />
                                </Button>
                                <Button variant="ghost" size="sm" title="History" onClick={() => openHistory(m)}>
                                  <History className="h-4 w-4 text-gray-500" />
                                </Button>
                              </div>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* ===== Enroll Dialog ===== */}
      <Dialog open={enrollOpen} onOpenChange={setEnrollOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Enroll New Member</DialogTitle>
            <DialogDescription>Add a customer to the loyalty program</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5"><Label>Customer Name *</Label><Input value={enrollName} onChange={(e) => setEnrollName(e.target.value)} placeholder="Full name" /></div>
            <div className="space-y-1.5"><Label>Phone</Label><Input value={enrollPhone} onChange={(e) => setEnrollPhone(e.target.value)} placeholder="Phone number" /></div>
            <div className="space-y-1.5"><Label>Customer ID (optional)</Label><Input type="number" value={enrollCustomerId} onChange={(e) => setEnrollCustomerId(e.target.value)} placeholder="Existing customer ID" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEnrollOpen(false)}>Cancel</Button>
            <Button className="bg-rose-600 hover:bg-rose-700" onClick={handleEnroll}>Enroll</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ===== Earn Points Dialog ===== */}
      <Dialog open={earnOpen} onOpenChange={setEarnOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Earn Points</DialogTitle>
            <DialogDescription>Add points for {selectedMember?.customerName}</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5"><Label>Points *</Label><Input type="number" value={earnPts} onChange={(e) => setEarnPts(e.target.value)} placeholder="Number of points" /></div>
            <div className="space-y-1.5"><Label>Description</Label><Input value={earnDesc} onChange={(e) => setEarnDesc(e.target.value)} placeholder="e.g. Purchase #1234" /></div>
            <div className="space-y-1.5"><Label>Order ID (optional)</Label><Input type="number" value={earnOrderId} onChange={(e) => setEarnOrderId(e.target.value)} placeholder="Link to an order" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setEarnOpen(false)}>Cancel</Button>
            <Button className="bg-green-600 hover:bg-green-700" onClick={handleEarn}>Add Points</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ===== Redeem Points Dialog ===== */}
      <Dialog open={redeemOpen} onOpenChange={setRedeemOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Redeem Points</DialogTitle>
            <DialogDescription>Redeem points for {selectedMember?.customerName} (Available: {selectedMember?.totalPoints.toLocaleString()})</DialogDescription>
          </DialogHeader>
          <div className="space-y-4 py-2">
            <div className="space-y-1.5"><Label>Points *</Label><Input type="number" value={redeemPts} onChange={(e) => setRedeemPts(e.target.value)} placeholder="Number of points" /></div>
            <div className="space-y-1.5"><Label>Description</Label><Input value={redeemDesc} onChange={(e) => setRedeemDesc(e.target.value)} placeholder="e.g. Discount on order" /></div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setRedeemOpen(false)}>Cancel</Button>
            <Button className="bg-red-600 hover:bg-red-700" onClick={handleRedeem}>Redeem</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* ===== Transaction History Dialog ===== */}
      <Dialog open={historyOpen} onOpenChange={setHistoryOpen}>
        <DialogContent className="max-w-lg">
          <DialogHeader>
            <DialogTitle>Point History</DialogTitle>
            <DialogDescription>{selectedMember?.customerName} - {tierBadge(selectedMember?.currentTier || "Bronze")}</DialogDescription>
          </DialogHeader>
          <div className="max-h-[400px] overflow-y-auto">
            {loadingTxns ? (
              <div className="flex items-center justify-center py-8"><Loader2 className="h-6 w-6 animate-spin text-rose-500" /></div>
            ) : transactions.length === 0 ? (
              <div className="text-center py-8 text-muted-foreground">No transactions yet</div>
            ) : (
              <div className="divide-y">
                {transactions.map((tx) => (
                  <div key={tx.pointTransactionId} className="flex items-center justify-between py-3 px-1">
                    <div className="flex items-center gap-3">
                      {tx.transactionType === "Earn" ? (
                        <ArrowUpCircle className="h-5 w-5 text-green-500" />
                      ) : (
                        <ArrowDownCircle className="h-5 w-5 text-red-500" />
                      )}
                      <div>
                        <div className="text-sm font-medium">{tx.description || tx.transactionType}</div>
                        <div className="text-xs text-muted-foreground">{new Date(tx.createdAt).toLocaleDateString()} {new Date(tx.createdAt).toLocaleTimeString([], { hour: "2-digit", minute: "2-digit" })}</div>
                      </div>
                    </div>
                    <div className={`font-semibold ${tx.transactionType === "Earn" ? "text-green-600" : "text-red-600"}`}>
                      {tx.transactionType === "Earn" ? "+" : "-"}{tx.points.toLocaleString()}
                    </div>
                  </div>
                ))}
              </div>
            )}
          </div>
        </DialogContent>
      </Dialog>
    </div>
  )
}

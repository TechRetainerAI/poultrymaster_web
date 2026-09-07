"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogFooter } from "@/components/ui/dialog"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Loader2, Plus, Trash2, Edit2, Globe, QrCode, Tag, Power, PowerOff, Copy, Printer, Download } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  getOnlineSettings, upsertOnlineSettings, toggleAcceptingOrders,
  listQrCodes, generateQrCode, deleteQrCode,
  listPromoCodes, createPromoCode, updatePromoCode, deletePromoCode,
  getRestaurantProfile,
  type OnlineOrderingSettings, type QrCode as QrCodeType, type PromoCode, type PromoCodeInput,
} from "@/lib/api/restaurant"
import { QrTableCard } from "@/components/restaurant/qr-table-card"
import { buildQrOrderUrl } from "@/lib/utils/qr-order-url"
import { QRCodeCanvas } from "qrcode.react"
import { createRoot } from "react-dom/client"

export default function RestaurantOnlineOrdersPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [settings, setSettings] = useState<Partial<OnlineOrderingSettings>>({
    isEnabled: false,
    allowDineInQr: true,
    allowTakeaway: true,
    allowDelivery: true,
    minOrderAmount: 0,
    maxOrdersPerSlot: 0,
    slotDurationMins: 30,
    estimatedPrepMinsDine: 15,
    estimatedPrepMinsTake: 20,
    estimatedPrepminsDeliv: 30,
    deliveryFeeType: "Fixed",
    deliveryFeeAmount: 0,
    maxDeliveryDistanceKm: 10,
    acceptingOrders: true,
  })
  const [qrCodes, setQrCodes] = useState<QrCodeType[]>([])
  const [promoCodes, setPromoCodes] = useState<PromoCode[]>([])
  const [profileName, setProfileName] = useState<string | null>(null)
  const [saving, setSaving] = useState(false)

  /**
   * Save one table's QR as a PNG.
   *
   * The card on screen is an SVG, which is what you want for print but not what
   * people expect from a "download" button — they paste these into WhatsApp and
   * word processors. So render a throwaway canvas off-screen at print resolution,
   * pull the data URL out of it, and drop it again.
   */
  async function downloadQrPng(q: QrCodeType) {
    const url = buildQrOrderUrl(q.qrToken, settings.publicBaseUrl)
    if (!url) { toast({ title: "Could not build the link", variant: "destructive" }); return }

    const host = document.createElement("div")
    host.style.cssText = "position:fixed;left:-10000px;top:0"
    document.body.appendChild(host)
    const root = createRoot(host)
    try {
      root.render(<QRCodeCanvas value={url} size={1024} level="M" marginSize={2} />)
      // Let React commit and the canvas paint before reading it back.
      await new Promise(r => requestAnimationFrame(() => requestAnimationFrame(() => r(null))))
      const canvas = host.querySelector("canvas")
      if (!canvas) throw new Error("Could not render the QR code.")
      const a = document.createElement("a")
      a.href = canvas.toDataURL("image/png")
      a.download = q.codeType === "Restaurant" ? "restaurant-qr.png" : `table-${q.tableNumber}-qr.png`
      a.click()
      toast({ title: `Saved table ${q.tableNumber} QR` })
    } catch (e: any) {
      toast({ title: "Download failed", description: e?.message, variant: "destructive" })
    } finally {
      root.unmount()
      host.remove()
    }
  }

  // Promo dialog
  const [promoDialogOpen, setPromoDialogOpen] = useState(false)
  const [promoEditing, setPromoEditing] = useState<PromoCode | null>(null)
  const [promoForm, setPromoForm] = useState<PromoCodeInput>({ code: "", discountValue: 0, discountType: "Percentage" })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [s, qr, pc, prof] = await Promise.all([
        getOnlineSettings().catch(() => null),
        listQrCodes().catch(() => []),
        listPromoCodes().catch(() => []),
        // Only used to title the printed card, so never let it fail the page.
        getRestaurantProfile().catch(() => null),
      ])
      if (s) setSettings(prev => ({ ...prev, ...s }))
      setQrCodes(qr)
      setPromoCodes(pc)
      setProfileName(prof?.restaurantName ?? null)
    } catch (e: any) {
      toast({ title: "Failed to load", description: e?.message, variant: "destructive" })
    } finally { setLoading(false) }
  }

  async function saveSettings() {
    setSaving(true)
    try {
      await upsertOnlineSettings(settings)
      toast({ title: "Settings saved" })
    } catch (e: any) {
      toast({ title: "Save failed", description: e?.message, variant: "destructive" })
    } finally { setSaving(false) }
  }

  async function toggleAccepting() {
    const newState = !settings.acceptingOrders
    try {
      await toggleAcceptingOrders(newState, newState ? undefined : "Paused by staff")
      setSettings({ ...settings, acceptingOrders: newState })
      toast({ title: newState ? "Now accepting orders" : "Orders paused" })
    } catch (e: any) {
      toast({ title: "Failed", description: e?.message, variant: "destructive" })
    }
  }

  /** The counter poster: one code for the venue, for guests skipping the queue. */
  async function genRestaurantQr() {
    try {
      await generateQrCode(null, null, "Restaurant")
      toast({ title: "Restaurant QR code ready", description: "Print it and put it where the queue forms." })
      setQrCodes(await listQrCodes())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function delQr(id: number) {
    try { await deleteQrCode(id); setQrCodes(await listQrCodes()); toast({ title: "QR deleted" }) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  function openPromoDialog(p?: PromoCode) {
    if (p) {
      setPromoEditing(p)
      setPromoForm({ code: p.code, description: p.description, discountType: p.discountType, discountValue: p.discountValue,
        minOrderAmount: p.minOrderAmount, maxDiscountAmount: p.maxDiscountAmount, maxUses: p.maxUses,
        validFrom: p.validFrom, validUntil: p.validUntil, isActive: p.isActive, channelRestriction: p.channelRestriction })
    } else {
      setPromoEditing(null)
      const autoCode = "PROMO-" + Math.random().toString(36).substring(2, 8).toUpperCase()
      setPromoForm({ code: autoCode, discountValue: 10, discountType: "Percentage", isActive: true })
    }
    setPromoDialogOpen(true)
  }

  async function savePromo() {
    if (!promoForm.code.trim()) { toast({ title: "Code required", variant: "destructive" }); return }
    try {
      if (promoEditing) await updatePromoCode(promoEditing.promoCodeId, promoForm)
      else await createPromoCode(promoForm)
      toast({ title: promoEditing ? "Promo updated" : "Promo created" })
      setPromoDialogOpen(false)
      setPromoCodes(await listPromoCodes())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function delPromo(id: number) {
    try { await deletePromoCode(id); setPromoCodes(await listPromoCodes()); toast({ title: "Deleted" }) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-5xl mx-auto space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center">
                  <Globe className="h-5 w-5 text-rose-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-gray-900">Online Ordering</h1>
                  <p className="text-sm text-muted-foreground">QR codes, promo codes and delivery settings</p>
                </div>
              </div>
              <Button onClick={toggleAccepting} variant={settings.acceptingOrders ? "default" : "destructive"} className="gap-2">
                {settings.acceptingOrders ? <><Power className="h-4 w-4" /> Accepting Orders</> : <><PowerOff className="h-4 w-4" /> Orders Paused</>}
              </Button>
            </div>

            <Tabs defaultValue="settings">
              <TabsList>
                <TabsTrigger value="settings">Settings</TabsTrigger>
                <TabsTrigger value="qr">QR Codes ({qrCodes.length})</TabsTrigger>
                <TabsTrigger value="promos">Promo Codes ({promoCodes.length})</TabsTrigger>
              </TabsList>

              {/* Settings */}
              <TabsContent value="settings">
                <Card>
                  <CardHeader><CardTitle>Online Ordering Settings</CardTitle></CardHeader>
                  <CardContent className="space-y-4">
                    <div className="flex flex-wrap gap-6">
                      {[["isEnabled", "Enable Online Ordering"], ["allowDineInQr", "Allow QR Table Ordering"], ["allowTakeaway", "Allow Takeaway"], ["allowDelivery", "Allow Delivery"]].map(([key, label]) => (
                        <label key={key} className="flex items-center gap-2"><input type="checkbox" checked={(settings as any)[key] || false} onChange={e => setSettings({ ...settings, [key]: e.target.checked })} />{label}</label>
                      ))}
                    </div>
                    <div className="grid grid-cols-3 gap-4">
                      <div><Label>Min Order Amount</Label><Input type="number" step="0.01" value={settings.minOrderAmount || 0} onChange={e => setSettings({ ...settings, minOrderAmount: parseFloat(e.target.value) || 0 })} /></div>
                      <div><Label>Max Orders/Slot (0=unlimited)</Label><Input type="number" value={settings.maxOrdersPerSlot || 0} onChange={e => setSettings({ ...settings, maxOrdersPerSlot: parseInt(e.target.value) || 0 })} /></div>
                      <div><Label>Slot Duration (mins)</Label><Input type="number" value={settings.slotDurationMins || 30} onChange={e => setSettings({ ...settings, slotDurationMins: parseInt(e.target.value) || 30 })} /></div>
                    </div>
                    <div className="grid grid-cols-3 gap-4">
                      <div><Label>Est. Prep Dine-In (mins)</Label><Input type="number" value={settings.estimatedPrepMinsDine || 15} onChange={e => setSettings({ ...settings, estimatedPrepMinsDine: parseInt(e.target.value) || 15 })} /></div>
                      <div><Label>Est. Prep Takeaway (mins)</Label><Input type="number" value={settings.estimatedPrepMinsTake || 20} onChange={e => setSettings({ ...settings, estimatedPrepMinsTake: parseInt(e.target.value) || 20 })} /></div>
                      <div><Label>Est. Prep Delivery (mins)</Label><Input type="number" value={settings.estimatedPrepminsDeliv || 30} onChange={e => setSettings({ ...settings, estimatedPrepminsDeliv: parseInt(e.target.value) || 30 })} /></div>
                    </div>
                    <div className="grid grid-cols-3 gap-4">
                      <div>
                        <Label>Delivery Fee Type</Label>
                        <Select value={settings.deliveryFeeType || "Fixed"} onValueChange={v => setSettings({ ...settings, deliveryFeeType: v })}>
                          <SelectTrigger><SelectValue /></SelectTrigger>
                          <SelectContent>
                            <SelectItem value="Fixed">Fixed</SelectItem>
                            <SelectItem value="DistanceBased">Distance Based</SelectItem>
                            <SelectItem value="Free">Free</SelectItem>
                          </SelectContent>
                        </Select>
                      </div>
                      <div><Label>Delivery Fee</Label><Input type="number" step="0.01" value={settings.deliveryFeeAmount || 0} onChange={e => setSettings({ ...settings, deliveryFeeAmount: parseFloat(e.target.value) || 0 })} /></div>
                      <div><Label>Free Delivery Above</Label><Input type="number" step="0.01" value={settings.freeDeliveryAbove || ""} onChange={e => setSettings({ ...settings, freeDeliveryAbove: parseFloat(e.target.value) || undefined })} /></div>
                    </div>
                    <div><Label>Welcome Message</Label><textarea className="w-full min-h-[60px] rounded-md border border-input px-3 py-2 text-sm" value={settings.welcomeMessage || ""} onChange={e => setSettings({ ...settings, welcomeMessage: e.target.value })} /></div>
                    <Button onClick={saveSettings} disabled={saving}>{saving && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}Save Settings</Button>
                  </CardContent>
                </Card>
              </TabsContent>

              {/* QR Codes */}
              <TabsContent value="qr">
                <Card>
                  <CardHeader className="flex flex-row items-start justify-between gap-3">
                    <CardTitle className="flex items-center gap-2"><QrCode className="h-5 w-5" /> Restaurant QR Code</CardTitle>
                    {qrCodes.length > 0 && (
                      <Button variant="outline" size="sm" onClick={() => window.open("/restaurant-qr-print", "_blank")}>
                        <Printer className="h-4 w-4 mr-1.5" /> Print
                      </Button>
                    )}
                  </CardHeader>
                  <CardContent>
                    <div className="mb-5 rounded-xl border border-rose-200 bg-rose-50/50 p-4">
                      <div className="flex flex-wrap items-start justify-between gap-3">
                        <div className="max-w-xl">
                          <div className="font-medium text-gray-900">Restaurant QR code</div>
                          <p className="mt-0.5 text-sm text-muted-foreground">
                            One code for the whole restaurant. Put it where the queue forms — a guest
                            scans it, sees your full menu, orders on their phone and skips the line.
                            This is the one most restaurants want.
                          </p>
                        </div>
                        {qrCodes.some(q => q.codeType === "Restaurant") ? (
                          <Badge variant="secondary" className="mt-1">Created</Badge>
                        ) : (
                          <Button size="sm" onClick={genRestaurantQr}>
                            <Plus className="h-4 w-4 mr-1.5" /> Create it
                          </Button>
                        )}
                      </div>
                    </div>

                    {qrCodes.length === 0 ? (
                      <p className="text-muted-foreground text-sm">No QR codes generated yet.</p>
                    ) : (
                      <div className="grid gap-4 sm:grid-cols-2 xl:grid-cols-3">
                        {qrCodes.map(q => (
                          <div key={q.qrCodeId} className="flex flex-col items-center gap-3 rounded-xl border p-4">
                            {/* The scannable card itself, shown exactly as it prints. */}
                            <QrTableCard
                              token={q.qrToken}
                              tableNumber={q.tableNumber}
                              codeType={q.codeType ?? "Table"}
                              restaurantName={profileName}
                              publicBaseUrl={settings.publicBaseUrl}
                              className={q.isActive ? "" : "opacity-40"}
                            />

                            <div className="flex items-center gap-2">
                              {q.codeType === "Restaurant" && <Badge className="bg-rose-600">Whole restaurant</Badge>}
                              <Badge variant={q.isActive ? "default" : "secondary"}>{q.isActive ? "Active" : "Inactive"}</Badge>
                              <span className="text-xs text-muted-foreground">
                                {q.scanCount} scan{q.scanCount === 1 ? "" : "s"}
                                {q.lastScannedAt && ` · last ${new Date(q.lastScannedAt).toLocaleDateString()}`}
                              </span>
                            </div>

                            <div className="flex flex-wrap justify-center gap-1.5">
                              {/* Copy the full URL, not the bare token: the token on its
                                  own is not something anyone can paste anywhere useful. */}
                              <Button variant="outline" size="sm" onClick={() => {
                                const url = buildQrOrderUrl(q.qrToken, settings.publicBaseUrl)
                                if (!url) { toast({ title: "Could not build the link", variant: "destructive" }); return }
                                navigator.clipboard.writeText(url)
                                toast({ title: "Ordering link copied" })
                              }}>
                                <Copy className="h-3.5 w-3.5 mr-1" /> Copy link
                              </Button>
                              <Button variant="outline" size="sm" onClick={() => downloadQrPng(q)}>
                                <Download className="h-3.5 w-3.5 mr-1" /> PNG
                              </Button>
                              <Button variant="outline" size="sm" onClick={() => window.open(`/restaurant-qr-print?table=${q.qrCodeId}`, "_blank")}>
                                <Printer className="h-3.5 w-3.5 mr-1" /> Print
                              </Button>
                              <Button variant="ghost" size="sm" onClick={() => delQr(q.qrCodeId)}>
                                <Trash2 className="h-3.5 w-3.5 text-red-500" />
                              </Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Promo Codes */}
              <TabsContent value="promos">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <CardTitle className="flex items-center gap-2"><Tag className="h-5 w-5" /> Promo Codes</CardTitle>
                    <Button size="sm" onClick={() => openPromoDialog()}><Plus className="h-4 w-4 mr-1" /> Add Promo</Button>
                  </CardHeader>
                  <CardContent>
                    {promoCodes.length === 0 ? (
                      <p className="text-muted-foreground text-sm">No promo codes. Create codes for discounts and promotions.</p>
                    ) : (
                      <div className="space-y-2">
                        {promoCodes.map(p => (
                          <div key={p.promoCodeId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <div className="flex items-center gap-2">
                                <span className="font-mono font-bold">{p.code}</span>
                                <Badge variant="outline" className="text-xs">{p.discountType === "Percentage" ? `${p.discountValue}%` : p.discountType === "FreeDelivery" ? "Free Delivery" : p.discountValue.toFixed(2)}</Badge>
                              </div>
                              <div className="text-xs text-muted-foreground">
                                {p.description} | Uses: {p.currentUses}/{p.maxUses || "∞"}
                                {p.channelRestriction && ` | ${p.channelRestriction} only`}
                                {p.validUntil && ` | Expires: ${new Date(p.validUntil).toLocaleDateString()}`}
                              </div>
                            </div>
                            <div className="flex gap-2 items-center">
                              <Badge variant={p.isActive ? "default" : "secondary"}>{p.isActive ? "Active" : "Inactive"}</Badge>
                              <Button variant="ghost" size="icon" onClick={() => openPromoDialog(p)}><Edit2 className="h-4 w-4" /></Button>
                              <Button variant="ghost" size="icon" onClick={() => delPromo(p.promoCodeId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
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

      {/* Promo Dialog */}
      <Dialog open={promoDialogOpen} onOpenChange={setPromoDialogOpen}>
        <DialogContent>
          <DialogHeader><DialogTitle>{promoEditing ? "Edit Promo Code" : "New Promo Code"}</DialogTitle></DialogHeader>
          <div className="space-y-3">
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Code *</Label><Input value={promoForm.code} onChange={e => setPromoForm({ ...promoForm, code: e.target.value.toUpperCase() })} placeholder="e.g. SAVE20" /></div>
              <div>
                <Label>Type</Label>
                <Select value={promoForm.discountType || "Percentage"} onValueChange={v => setPromoForm({ ...promoForm, discountType: v })}>
                  <SelectTrigger><SelectValue /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="Percentage">Percentage</SelectItem>
                    <SelectItem value="FixedAmount">Fixed Amount</SelectItem>
                    <SelectItem value="FreeDelivery">Free Delivery</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            </div>
            <div><Label>Description</Label><Input value={promoForm.description || ""} onChange={e => setPromoForm({ ...promoForm, description: e.target.value })} /></div>
            <div className="grid grid-cols-3 gap-3">
              <div><Label>Value</Label><Input type="number" step="0.01" value={promoForm.discountValue} onChange={e => setPromoForm({ ...promoForm, discountValue: parseFloat(e.target.value) || 0 })} /></div>
              <div><Label>Min Order</Label><Input type="number" step="0.01" value={promoForm.minOrderAmount || 0} onChange={e => setPromoForm({ ...promoForm, minOrderAmount: parseFloat(e.target.value) || 0 })} /></div>
              <div><Label>Max Uses (0=∞)</Label><Input type="number" value={promoForm.maxUses || 0} onChange={e => setPromoForm({ ...promoForm, maxUses: parseInt(e.target.value) || 0 })} /></div>
            </div>
            <div className="grid grid-cols-2 gap-3">
              <div><Label>Valid From</Label><Input type="datetime-local" value={promoForm.validFrom?.slice(0, 16) || ""} onChange={e => setPromoForm({ ...promoForm, validFrom: e.target.value || null })} /></div>
              <div><Label>Valid Until</Label><Input type="datetime-local" value={promoForm.validUntil?.slice(0, 16) || ""} onChange={e => setPromoForm({ ...promoForm, validUntil: e.target.value || null })} /></div>
            </div>
            <div>
              <Label>Channel Restriction</Label>
              <Select value={promoForm.channelRestriction || "all"} onValueChange={v => setPromoForm({ ...promoForm, channelRestriction: v === "all" ? null : v })}>
                <SelectTrigger><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="all">All Channels</SelectItem>
                  <SelectItem value="Online">Online Only</SelectItem>
                  <SelectItem value="QR">QR Only</SelectItem>
                  <SelectItem value="Delivery">Delivery Only</SelectItem>
                </SelectContent>
              </Select>
            </div>
          </div>
          <DialogFooter><Button onClick={savePromo}>{promoEditing ? "Update" : "Create"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

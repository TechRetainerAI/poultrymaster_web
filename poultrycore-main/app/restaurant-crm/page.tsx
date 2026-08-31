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
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Plus, Trash2, Edit2, Users, Star, MessageSquare, Megaphone, Search, Heart, Crown, UserPlus, DollarSign, Phone, Mail } from "lucide-react"
import { Badge } from "@/components/ui/badge"
import { Textarea } from "@/components/ui/textarea"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import {
  listCustomers, createCustomer, updateCustomer, deleteCustomer, getCustomerStats,
  listFeedback, createFeedback, respondToFeedback, getFeedbackStats,
  listCampaigns, createCampaign, deleteCampaign,
  type Customer, type CustomerInput, type CustomerStats,
  type Feedback, type FeedbackInput, type FeedbackStats,
  type Campaign, type CampaignInput,
} from "@/lib/api/restaurant"

const SEGMENTS = [{ v: "New", icon: "🆕", color: "bg-blue-100 text-blue-700" }, { v: "Regular", icon: "🔄", color: "bg-green-100 text-green-700" }, { v: "VIP", icon: "👑", color: "bg-purple-100 text-purple-700" }, { v: "Lapsed", icon: "😴", color: "bg-gray-100 text-gray-700" }]

export default function RestaurantCRMPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [customers, setCustomers] = useState<Customer[]>([])
  const [custStats, setCustStats] = useState<CustomerStats | null>(null)
  const [feedback, setFeedback] = useState<Feedback[]>([])
  const [fbStats, setFbStats] = useState<FeedbackStats | null>(null)
  const [campaigns, setCampaigns] = useState<Campaign[]>([])
  const [search, setSearch] = useState("")
  const [filterSeg, setFilterSeg] = useState("all")

  const [custDialogOpen, setCustDialogOpen] = useState(false)
  const [custEditing, setCustEditing] = useState<Customer | null>(null)
  const [custForm, setCustForm] = useState<CustomerInput>({ name: "" })

  const [fbDialogOpen, setFbDialogOpen] = useState(false)
  const [fbForm, setFbForm] = useState<FeedbackInput>({ rating: 5 })
  const [respondDialog, setRespondDialog] = useState<Feedback | null>(null)
  const [respondText, setRespondText] = useState("")

  const [campDialogOpen, setCampDialogOpen] = useState(false)
  const [campForm, setCampForm] = useState<CampaignInput>({ name: "", campaignType: "Promotion" })

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [c, cs, f, fs, ca] = await Promise.all([
        listCustomers().catch(() => []), getCustomerStats().catch(() => null),
        listFeedback().catch(() => []), getFeedbackStats().catch(() => null),
        listCampaigns().catch(() => []),
      ])
      setCustomers(c); setCustStats(cs); setFeedback(f); setFbStats(fs); setCampaigns(ca)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openCustDialog(c?: Customer) {
    if (c) { setCustEditing(c); setCustForm({ name: c.name, phone: c.phone, email: c.email, dateOfBirth: c.dateOfBirth?.split("T")[0], anniversary: c.anniversary?.split("T")[0], dietaryPreferences: c.dietaryPreferences, allergies: c.allergies, favouriteItems: c.favouriteItems, segment: c.segment, notes: c.notes, isActive: c.isActive }) }
    else { setCustEditing(null); setCustForm({ name: "", segment: "New" }) }
    setCustDialogOpen(true)
  }
  async function saveCust() {
    if (!custForm.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    try { if (custEditing) await updateCustomer(custEditing.customerId, custForm); else await createCustomer(custForm)
      toast({ title: custEditing ? "Updated" : "Customer added" }); setCustDialogOpen(false); loadAll()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delCust(id: number) { try { await deleteCustomer(id); loadAll() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  async function saveFb() {
    try { await createFeedback(fbForm); toast({ title: "Feedback recorded" }); setFbDialogOpen(false); loadAll() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function handleRespond() {
    if (!respondDialog || !respondText.trim()) return
    try { await respondToFeedback(respondDialog.feedbackId, respondText); toast({ title: "Response sent" }); setRespondDialog(null); setRespondText(""); loadAll() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function saveCamp() {
    if (!campForm.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    try { await createCampaign(campForm); toast({ title: "Campaign created" }); setCampDialogOpen(false); loadAll() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delCamp(id: number) { try { await deleteCampaign(id); loadAll() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  const filtered = customers.filter(c => {
    if (filterSeg !== "all" && c.segment !== filterSeg) return false
    if (search && !c.name.toLowerCase().includes(search.toLowerCase()) && !c.phone?.includes(search)) return false
    return true
  })

  if (loading) return <PageSkeleton statCards={5} listRows={6} />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center"><Heart className="h-5 w-5 text-rose-600" /></div>
                <div><h1 className="text-2xl font-bold text-gray-900">Customer Relationships</h1><p className="text-sm text-muted-foreground">Profiles, feedback, and campaigns</p></div>
              </div>
              <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openCustDialog()}><Plus className="h-4 w-4 mr-2" /> Add Customer</Button>
            </div>

            {/* Stats */}
            {custStats && (
              <div className="grid grid-cols-2 md:grid-cols-5 gap-3">
                {[
                  { l: "Total", v: custStats.totalCustomers, c: "text-gray-900", icon: Users },
                  { l: "New", v: custStats.newCount, c: "text-blue-700", icon: UserPlus },
                  { l: "Regular", v: custStats.regularCount, c: "text-green-700", icon: Users },
                  { l: "VIP", v: custStats.vipCount, c: "text-purple-700", icon: Crown },
                  { l: "Lifetime Value", v: custStats.totalLifetimeValue.toFixed(0), c: "text-rose-700", icon: DollarSign },
                ].map(s => (
                  <Card key={s.l}><CardContent className="py-3 px-4 flex items-center gap-2">
                    <s.icon className={`h-4 w-4 ${s.c}`} /><div><div className={`text-xl font-bold ${s.c}`}>{s.v}</div><div className="text-xs text-muted-foreground">{s.l}</div></div>
                  </CardContent></Card>
                ))}
              </div>
            )}

            <Tabs defaultValue="customers" className="space-y-4">
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger value="customers" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Users className="h-4 w-4 mr-2" />Customers <Badge variant="secondary" className="ml-2 h-5 px-1.5">{customers.length}</Badge></TabsTrigger>
                <TabsTrigger value="feedback" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Star className="h-4 w-4 mr-2" />Feedback {fbStats && fbStats.newCount > 0 && <Badge className="ml-2 h-5 px-1.5 bg-amber-500 text-white">{fbStats.newCount}</Badge>}</TabsTrigger>
                <TabsTrigger value="campaigns" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Megaphone className="h-4 w-4 mr-2" />Campaigns</TabsTrigger>
              </TabsList>

              {/* Customers */}
              <TabsContent value="customers">
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex gap-3">
                      <div className="relative flex-1"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" /><Input className="pl-9 h-10" placeholder="Search customers..." value={search} onChange={e => setSearch(e.target.value)} /></div>
                      <Select value={filterSeg} onValueChange={setFilterSeg}>
                        <SelectTrigger className="w-[140px] h-10"><SelectValue /></SelectTrigger>
                        <SelectContent><SelectItem value="all">All Segments</SelectItem>{SEGMENTS.map(s => <SelectItem key={s.v} value={s.v}>{s.icon} {s.v}</SelectItem>)}</SelectContent>
                      </Select>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {filtered.length === 0 ? (
                      <div className="text-center py-16 border-2 border-dashed rounded-xl">
                        <Users className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No customers yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Add your regular guests to track their visits and preferences</p>
                        <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openCustDialog()}><Plus className="h-4 w-4 mr-2" /> Add Customer</Button>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {filtered.map(c => {
                          const seg = SEGMENTS.find(s => s.v === c.segment)
                          return (
                            <div key={c.customerId} className="group flex items-center gap-4 p-4 border rounded-xl hover:border-rose-200 transition-all">
                              <div className={`h-10 w-10 rounded-xl flex items-center justify-center text-sm font-bold flex-shrink-0 ${seg?.color || "bg-gray-100"}`}>{c.name.split(" ").map(w => w[0]).join("").toUpperCase().slice(0, 2)}</div>
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2">
                                  <h4 className="font-semibold text-gray-900">{c.name}</h4>
                                  <Badge className={`text-[10px] h-5 ${seg?.color} hover:${seg?.color}`}>{c.segment}</Badge>
                                </div>
                                <div className="flex items-center gap-3 mt-1 text-xs text-muted-foreground">
                                  {c.phone && <span className="flex items-center gap-1"><Phone className="h-3 w-3" />{c.phone}</span>}
                                  {c.email && <span className="flex items-center gap-1"><Mail className="h-3 w-3" />{c.email}</span>}
                                  <span>{c.totalVisits} visits</span>
                                  {c.dietaryPreferences && <span>🥗 {c.dietaryPreferences}</span>}
                                  {c.allergies && <span>⚠️ {c.allergies}</span>}
                                </div>
                              </div>
                              <div className="text-right flex-shrink-0 min-w-[80px]">
                                <div className="font-bold text-gray-900">{c.totalSpent.toFixed(0)}</div>
                                <div className="text-xs text-muted-foreground">lifetime</div>
                              </div>
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openCustDialog(c)}><Edit2 className="h-3.5 w-3.5" /></Button>
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => delCust(c.customerId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Feedback */}
              <TabsContent value="feedback" className="space-y-4">
                {fbStats && (
                  <div className="grid grid-cols-5 gap-3">
                    {[["Overall", fbStats.avgRating, "⭐"], ["Food", fbStats.avgFood, "🍕"], ["Service", fbStats.avgService, "🙋"], ["Ambience", fbStats.avgAmbience, "🎵"], ["Total", fbStats.totalFeedback, "📝"]].map(([l, v, e]) => (
                      <Card key={String(l)}><CardContent className="py-3 text-center">
                        <div className="text-xl">{e}</div>
                        <div className="text-lg font-bold">{typeof v === "number" ? v.toFixed(1) : v ?? "—"}</div>
                        <div className="text-xs text-muted-foreground">{l}</div>
                      </CardContent></Card>
                    ))}
                  </div>
                )}
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <div className="flex items-center gap-2"><div className="h-9 w-9 rounded-lg bg-amber-100 flex items-center justify-center"><Star className="h-5 w-5 text-amber-600" /></div><div><CardTitle className="text-lg">Customer Feedback</CardTitle><CardDescription>Reviews and ratings</CardDescription></div></div>
                    <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setFbForm({ rating: 5 }); setFbDialogOpen(true) }}><Plus className="h-4 w-4 mr-2" /> Add Feedback</Button>
                  </CardHeader>
                  <CardContent>
                    {feedback.length === 0 ? <p className="text-center py-8 text-muted-foreground text-sm">No feedback yet</p> : (
                      <div className="space-y-2">
                        {feedback.slice(0, 20).map(f => (
                          <div key={f.feedbackId} className="p-4 border rounded-xl">
                            <div className="flex items-center justify-between">
                              <div className="flex items-center gap-2">
                                <span className="text-lg">{"⭐".repeat(f.rating)}</span>
                                {f.customerName && <span className="font-medium text-sm">{f.customerName}</span>}
                                <Badge variant="outline" className="text-[10px] h-5">{f.source}</Badge>
                                <Badge className={`text-[10px] h-5 ${f.status === "New" ? "bg-blue-100 text-blue-700" : f.status === "Responded" ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-700"} hover:bg-inherit`}>{f.status}</Badge>
                              </div>
                              <span className="text-xs text-muted-foreground">{new Date(f.createdAt).toLocaleDateString()}</span>
                            </div>
                            {f.comment && <p className="text-sm text-gray-700 mt-2">{f.comment}</p>}
                            {f.response && <div className="mt-2 p-2 bg-green-50 rounded-lg text-sm"><span className="font-medium text-green-700">Response:</span> {f.response}</div>}
                            {f.status === "New" && <Button variant="ghost" size="sm" className="mt-2 text-xs text-rose-600" onClick={() => { setRespondDialog(f); setRespondText("") }}><MessageSquare className="h-3 w-3 mr-1" /> Respond</Button>}
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Campaigns */}
              <TabsContent value="campaigns">
                <Card>
                  <CardHeader className="flex flex-row items-center justify-between">
                    <div className="flex items-center gap-2"><div className="h-9 w-9 rounded-lg bg-indigo-100 flex items-center justify-center"><Megaphone className="h-5 w-5 text-indigo-600" /></div><div><CardTitle className="text-lg">Marketing Campaigns</CardTitle><CardDescription>Reach your customers with targeted messages</CardDescription></div></div>
                    <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setCampForm({ name: "", campaignType: "Promotion" }); setCampDialogOpen(true) }}><Plus className="h-4 w-4 mr-2" /> Create Campaign</Button>
                  </CardHeader>
                  <CardContent>
                    {campaigns.length === 0 ? (
                      <div className="text-center py-12 border-2 border-dashed rounded-xl">
                        <Megaphone className="h-10 w-10 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No campaigns yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create birthday offers, win-back campaigns, or promotions</p>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {campaigns.map(ca => (
                          <div key={ca.campaignId} className="flex items-center justify-between p-4 border rounded-xl">
                            <div>
                              <div className="flex items-center gap-2"><h4 className="font-semibold">{ca.name}</h4><Badge variant="outline" className="text-[10px] h-5">{ca.campaignType}</Badge><Badge variant="outline" className="text-[10px] h-5">{ca.channel}</Badge><Badge className={`text-[10px] h-5 ${ca.status === "Sent" ? "bg-green-100 text-green-700" : "bg-gray-100 text-gray-700"} hover:bg-inherit`}>{ca.status}</Badge></div>
                              <div className="text-xs text-muted-foreground mt-1">Target: {ca.targetSegment || "All"} {ca.recipientCount > 0 && `| Sent to: ${ca.recipientCount}`}</div>
                            </div>
                            <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => delCamp(ca.campaignId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
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

      {/* Customer Dialog */}
      <Dialog open={custDialogOpen} onOpenChange={setCustDialogOpen}>
        <DialogContent className="sm:max-w-lg"><DialogHeader><DialogTitle>{custEditing ? "Edit Customer" : "Add Customer"}</DialogTitle><DialogDescription>Track guest preferences and visit history</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Name <span className="text-rose-500">*</span></Label><Input value={custForm.name} onChange={e => setCustForm({ ...custForm, name: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Phone</Label><Input value={custForm.phone || ""} onChange={e => setCustForm({ ...custForm, phone: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Email</Label><Input value={custForm.email || ""} onChange={e => setCustForm({ ...custForm, email: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Segment</Label><Select value={custForm.segment || "New"} onValueChange={v => setCustForm({ ...custForm, segment: v })}><SelectTrigger className="h-10"><SelectValue /></SelectTrigger><SelectContent>{SEGMENTS.map(s => <SelectItem key={s.v} value={s.v}>{s.icon} {s.v}</SelectItem>)}</SelectContent></Select></div>
              <div className="space-y-1.5"><Label>Birthday</Label><Input type="date" value={custForm.dateOfBirth || ""} onChange={e => setCustForm({ ...custForm, dateOfBirth: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Anniversary</Label><Input type="date" value={custForm.anniversary || ""} onChange={e => setCustForm({ ...custForm, anniversary: e.target.value })} className="h-10" /></div>
            </div>
            <div className="space-y-1.5"><Label>Dietary Preferences</Label><Input value={custForm.dietaryPreferences || ""} onChange={e => setCustForm({ ...custForm, dietaryPreferences: e.target.value })} placeholder="e.g. Vegetarian, No spicy" className="h-10" /></div>
            <div className="space-y-1.5"><Label>Allergies</Label><Input value={custForm.allergies || ""} onChange={e => setCustForm({ ...custForm, allergies: e.target.value })} placeholder="e.g. Nuts, Shellfish, Dairy" className="h-10" /></div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={custForm.notes || ""} onChange={e => setCustForm({ ...custForm, notes: e.target.value })} className="h-10" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setCustDialogOpen(false)}>Cancel</Button><Button onClick={saveCust} className="bg-rose-600 hover:bg-rose-700">{custEditing ? "Update" : "Add Customer"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Feedback Dialog */}
      <Dialog open={fbDialogOpen} onOpenChange={setFbDialogOpen}>
        <DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Add Feedback</DialogTitle></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5"><Label>Customer Name</Label><Input value={fbForm.customerName || ""} onChange={e => setFbForm({ ...fbForm, customerName: e.target.value })} className="h-10" /></div>
            <div className="space-y-1.5"><Label>Overall Rating</Label><div className="flex gap-1">{[1,2,3,4,5].map(r => <button key={r} type="button" onClick={() => setFbForm({ ...fbForm, rating: r })} className={`h-10 w-10 rounded-lg text-lg ${fbForm.rating >= r ? "bg-amber-100" : "bg-gray-100"}`}>⭐</button>)}</div></div>
            <div className="grid grid-cols-3 gap-3">
              <div className="space-y-1"><Label className="text-xs">Food</Label><Select value={String(fbForm.foodRating || "")} onValueChange={v => setFbForm({ ...fbForm, foodRating: parseInt(v) })}><SelectTrigger className="h-9"><SelectValue placeholder="—" /></SelectTrigger><SelectContent>{[1,2,3,4,5].map(r => <SelectItem key={r} value={String(r)}>{r}/5</SelectItem>)}</SelectContent></Select></div>
              <div className="space-y-1"><Label className="text-xs">Service</Label><Select value={String(fbForm.serviceRating || "")} onValueChange={v => setFbForm({ ...fbForm, serviceRating: parseInt(v) })}><SelectTrigger className="h-9"><SelectValue placeholder="—" /></SelectTrigger><SelectContent>{[1,2,3,4,5].map(r => <SelectItem key={r} value={String(r)}>{r}/5</SelectItem>)}</SelectContent></Select></div>
              <div className="space-y-1"><Label className="text-xs">Ambience</Label><Select value={String(fbForm.ambienceRating || "")} onValueChange={v => setFbForm({ ...fbForm, ambienceRating: parseInt(v) })}><SelectTrigger className="h-9"><SelectValue placeholder="—" /></SelectTrigger><SelectContent>{[1,2,3,4,5].map(r => <SelectItem key={r} value={String(r)}>{r}/5</SelectItem>)}</SelectContent></Select></div>
            </div>
            <div className="space-y-1.5"><Label>Comment</Label><Textarea className="min-h-[60px]" value={fbForm.comment || ""} onChange={e => setFbForm({ ...fbForm, comment: e.target.value })} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setFbDialogOpen(false)}>Cancel</Button><Button onClick={saveFb} className="bg-rose-600 hover:bg-rose-700">Submit</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Respond Dialog */}
      <Dialog open={respondDialog !== null} onOpenChange={() => setRespondDialog(null)}>
        <DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Respond to Feedback</DialogTitle><DialogDescription>{respondDialog?.comment}</DialogDescription></DialogHeader>
          <div className="space-y-1.5"><Label>Your Response</Label><Textarea className="min-h-[80px]" value={respondText} onChange={e => setRespondText(e.target.value)} placeholder="Thank you for your feedback..." /></div>
          <DialogFooter><Button variant="outline" onClick={() => setRespondDialog(null)}>Cancel</Button><Button onClick={handleRespond} className="bg-rose-600 hover:bg-rose-700">Send Response</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Campaign Dialog */}
      <Dialog open={campDialogOpen} onOpenChange={setCampDialogOpen}>
        <DialogContent className="sm:max-w-md"><DialogHeader><DialogTitle>Create Campaign</DialogTitle><DialogDescription>Send targeted messages to your customers</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5"><Label>Campaign Name <span className="text-rose-500">*</span></Label><Input value={campForm.name} onChange={e => setCampForm({ ...campForm, name: e.target.value })} className="h-10" /></div>
            <div className="grid grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Type</Label><Select value={campForm.campaignType} onValueChange={v => setCampForm({ ...campForm, campaignType: v })}><SelectTrigger className="h-10"><SelectValue /></SelectTrigger><SelectContent>{["Birthday", "WinBack", "Promotion", "Announcement"].map(t => <SelectItem key={t} value={t}>{t}</SelectItem>)}</SelectContent></Select></div>
              <div className="space-y-1.5"><Label>Target</Label><Select value={campForm.targetSegment || "All"} onValueChange={v => setCampForm({ ...campForm, targetSegment: v })}><SelectTrigger className="h-10"><SelectValue /></SelectTrigger><SelectContent>{["All", "New", "Regular", "VIP", "Lapsed"].map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent></Select></div>
            </div>
            <div className="space-y-1.5"><Label>Channel</Label><Select value={campForm.channel || "SMS"} onValueChange={v => setCampForm({ ...campForm, channel: v })}><SelectTrigger className="h-10"><SelectValue /></SelectTrigger><SelectContent>{["SMS", "Email", "Push"].map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent></Select></div>
            <div className="space-y-1.5"><Label>Message</Label><Textarea className="min-h-[80px]" value={campForm.message || ""} onChange={e => setCampForm({ ...campForm, message: e.target.value })} /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setCampDialogOpen(false)}>Cancel</Button><Button onClick={saveCamp} className="bg-rose-600 hover:bg-rose-700">Create</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

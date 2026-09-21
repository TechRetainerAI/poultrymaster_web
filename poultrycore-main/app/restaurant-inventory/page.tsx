"use client"

import { useEffect, useRef, useState } from "react"
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
import { Plus, Trash2, Edit2, Package, AlertTriangle, Search, DollarSign, TrendingDown, Warehouse, ClipboardCheck } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { OtherSelect, type OtherSelectHandle } from "@/components/restaurant/other-select"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listIngredients, createIngredient, updateIngredient, deleteIngredient,
  adjustIngredientStock, getLowStock, getInventoryValue,
  listWaste, logWaste, getWasteSummary,
  listRestaurantSuppliers,
  type Ingredient, type IngredientInput, type WasteLog, type WasteInput,
  type WasteSummary, type InventoryValue, type RestaurantSupplier,
} from "@/lib/api/restaurant"

// "Other" is NOT listed here — OtherSelect appends its own, which opens a text box.
const CATEGORIES = ["Proteins", "Dairy", "Produce", "Dry Goods", "Spices", "Beverages", "Frozen", "Oils & Fats", "Bakery", "Sauces"]
const UNITS = ["kg", "g", "L", "mL", "pcs", "dozen", "bag", "box", "bottle", "can", "bunch"]
const STORAGE_AREAS = ["Walk-in Cooler", "Freezer", "Dry Store", "Bar", "Kitchen Counter", "Pantry"]
const WASTE_REASONS = ["Spoilage", "PrepWaste", "Returned", "Expired", "Spillage", "Overproduction"]

export default function RestaurantInventoryPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  // Handles on the two "Other" dropdowns, so a typed value is remembered by
  // the same click that saves the record it was typed for.
  const ingCategoryOther = useRef<OtherSelectHandle>(null)
  const wasteReasonOther = useRef<OtherSelectHandle>(null)

  const [loading, setLoading] = useState(true)
  const [ingredients, setIngredients] = useState<Ingredient[]>([])
  const [lowStock, setLowStock] = useState<Ingredient[]>([])
  const [suppliers, setSuppliers] = useState<RestaurantSupplier[]>([])
  const [wasteLog, setWasteLog] = useState<WasteLog[]>([])
  const [wasteSummary, setWasteSummary] = useState<WasteSummary[]>([])
  const [invValue, setInvValue] = useState<InventoryValue[]>([])
  const [search, setSearch] = useState("")
  const [filterCat, setFilterCat] = useState("all")

  // Ingredient dialog
  const [ingDialogOpen, setIngDialogOpen] = useState(false)
  const [ingEditing, setIngEditing] = useState<Ingredient | null>(null)
  const [ingForm, setIngForm] = useState<IngredientInput>({ name: "", unit: "kg", costPerUnit: 0, currentStock: 0 })

  // Waste dialog
  const [wasteDialogOpen, setWasteDialogOpen] = useState(false)
  const [wasteForm, setWasteForm] = useState<WasteInput>({ ingredientName: "", quantity: 0, unit: "kg", reason: "Spoilage" })

  // Adjust stock dialog
  const [adjustDialogOpen, setAdjustDialogOpen] = useState(false)
  const [adjustId, setAdjustId] = useState(0)
  const [adjustQty, setAdjustQty] = useState(0)
  const [adjustType, setAdjustType] = useState("PurchaseIn")
  const [adjustReason, setAdjustReason] = useState("")

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [ing, low, wl, ws, iv, sup] = await Promise.all([
        listIngredients(), getLowStock().catch(() => []),
        listWaste().catch(() => []), getWasteSummary().catch(() => []),
        getInventoryValue().catch(() => []), listRestaurantSuppliers().catch(() => []),
      ])
      setIngredients(ing); setLowStock(low); setWasteLog(wl); setWasteSummary(ws); setInvValue(iv); setSuppliers(sup)
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  function openIngDialog(i?: Ingredient) {
    if (i) { setIngEditing(i); setIngForm({ name: i.name, category: i.category, unit: i.unit, costPerUnit: i.costPerUnit, parLevel: i.parLevel, reorderPoint: i.reorderPoint, supplierName: i.supplierName, expiryDays: i.expiryDays, storageArea: i.storageArea, isActive: i.isActive, notes: i.notes }) }
    else { setIngEditing(null); setIngForm({ name: "", unit: "kg", costPerUnit: 0, currentStock: 0, category: "Produce" }) }
    setIngDialogOpen(true)
  }
  async function saveIng() {
    if (!ingForm.name.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    try {
      if (ingEditing) await updateIngredient(ingEditing.ingredientId, ingForm)
      else await createIngredient(ingForm)
      // A category typed under "Other" joins the list only once the ingredient
      // it was typed for actually saved. Before the dialog closes: closing
      // unmounts the field and takes the ref with it.
      await ingCategoryOther.current?.remember()
      toast({ title: ingEditing ? "Updated" : "Ingredient added" }); setIngDialogOpen(false); loadAll()
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function delIng(id: number) { try { await deleteIngredient(id); loadAll() } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  async function handleAdjust() {
    if (adjustQty === 0) return
    try { await adjustIngredientStock(adjustId, adjustQty, adjustType, adjustReason); toast({ title: "Stock adjusted" }); setAdjustDialogOpen(false); loadAll() }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  async function handleLogWaste() {
    if (!wasteForm.ingredientName.trim()) { toast({ title: "Name required", variant: "destructive" }); return }
    if (wasteForm.quantity <= 0) { toast({ title: "Quantity must be greater than 0", variant: "destructive" }); return }
    // Recalculate cost from ingredient
    const ing = ingredients.find(i => i.ingredientId === wasteForm.ingredientId)
    const finalForm = { ...wasteForm, costAmount: ing ? ing.costPerUnit * wasteForm.quantity : (wasteForm.costAmount || 0) }
    try {
      await logWaste(finalForm)
      await wasteReasonOther.current?.remember()
      toast({ title: "Waste logged" }); setWasteDialogOpen(false); loadAll()
    }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const filtered = ingredients.filter(i => {
    if (filterCat !== "all" && i.category !== filterCat) return false
    if (search && !i.name.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })
  // The filter offers the built-in categories PLUS any category actually in use,
  // which is how a category typed into the "Other" box becomes filterable without
  // this component needing to fetch the remembered list itself.
  const filterCategories = Array.from(
    new Set([...CATEGORIES, ...ingredients.map(i => i.category).filter((c): c is string => !!c)])
  ).sort((a, b) => a.localeCompare(b))
  const totalValue = invValue.reduce((s, v) => s + v.totalValue, 0)
  const totalWasteCost = wasteSummary.reduce((s, w) => s + w.totalCost, 0)

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-4 md:p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            <div className="flex flex-col sm:flex-row sm:items-center sm:justify-between gap-3">
              <div className="flex items-center gap-3 min-w-0">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center flex-shrink-0"><Package className="h-5 w-5 text-rose-600" /></div>
                <div className="min-w-0"><h1 className="text-xl sm:text-2xl font-bold text-gray-900">Inventory & Recipes</h1><p className="text-sm text-muted-foreground">{ingredients.length} ingredients tracked</p></div>
              </div>
              <Button className="bg-rose-600 hover:bg-rose-700 w-full sm:w-auto flex-shrink-0" onClick={() => openIngDialog()}><Plus className="h-4 w-4 mr-2" /> Add Ingredient</Button>
            </div>

            {/* Stats */}
            <div className="grid grid-cols-2 lg:grid-cols-4 gap-3">
              {[
                { label: "Total Ingredients", value: ingredients.length, color: "text-gray-900", icon: Package, iconBg: "bg-gray-100" },
                { label: "Low Stock", value: lowStock.length, color: lowStock.length > 0 ? "text-red-700" : "text-green-700", icon: AlertTriangle, iconBg: lowStock.length > 0 ? "bg-red-100" : "bg-green-100" },
                { label: "Inventory Value", value: totalValue.toFixed(0), color: "text-blue-700", icon: DollarSign, iconBg: "bg-blue-100" },
                { label: "Waste Cost", value: totalWasteCost.toFixed(0), color: "text-amber-700", icon: TrendingDown, iconBg: "bg-amber-100" },
              ].map(s => (
                <Card key={s.label}><CardContent className="py-3 px-4 flex items-center gap-3">
                  <div className={`h-9 w-9 rounded-lg flex items-center justify-center ${s.iconBg}`}><s.icon className={`h-4 w-4 ${s.color}`} /></div>
                  <div><div className={`text-xl font-bold ${s.color}`}>{s.value}</div><div className="text-xs text-muted-foreground">{s.label}</div></div>
                </CardContent></Card>
              ))}
            </div>

            {/* Low stock alert */}
            {lowStock.length > 0 && (
              <Card className="border-red-200 bg-red-50">
                <CardContent className="py-3 flex items-center gap-3">
                  <AlertTriangle className="h-5 w-5 text-red-600 flex-shrink-0" />
                  <span className="text-sm text-red-800"><strong>{lowStock.length}</strong> ingredient{lowStock.length !== 1 ? "s" : ""} below reorder point: {lowStock.slice(0, 5).map(l => l.name).join(", ")}{lowStock.length > 5 ? "..." : ""}</span>
                </CardContent>
              </Card>
            )}

            <Tabs defaultValue="ingredients" className="space-y-4">
              <TabsList className="bg-white border shadow-sm flex-wrap h-auto">
                <TabsTrigger value="ingredients" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><Package className="h-4 w-4 mr-2" /> Ingredients <Badge variant="secondary" className="ml-2 h-5 px-1.5">{ingredients.length}</Badge></TabsTrigger>
                <TabsTrigger value="waste" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><TrendingDown className="h-4 w-4 mr-2" /> Waste Log <Badge variant="secondary" className="ml-2 h-5 px-1.5">{wasteLog.length}</Badge></TabsTrigger>
                <TabsTrigger value="value" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700"><DollarSign className="h-4 w-4 mr-2" /> Inventory Value</TabsTrigger>
              </TabsList>

              {/* Ingredients Tab */}
              <TabsContent value="ingredients">
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex flex-wrap gap-2 sm:gap-3">
                      <div className="relative basis-full sm:basis-auto sm:flex-1 sm:min-w-[200px]"><Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground pointer-events-none" /><Input className="pl-9 h-10 w-full" placeholder="Search ingredients..." value={search} onChange={e => setSearch(e.target.value)} /></div>
                      <Select value={filterCat} onValueChange={setFilterCat}>
                        <SelectTrigger className="flex-1 sm:flex-none sm:w-[160px] h-10"><SelectValue placeholder="All" /></SelectTrigger>
                        <SelectContent><SelectItem value="all">All Categories</SelectItem>{filterCategories.map(c => <SelectItem key={c} value={c}>{c}</SelectItem>)}</SelectContent>
                      </Select>
                      <Button variant="outline" className="h-10 flex-1 sm:flex-none" onClick={() => { setWasteForm({ ingredientName: "", quantity: 0, unit: "kg", reason: "Spoilage" }); setWasteDialogOpen(true) }}><TrendingDown className="h-4 w-4 mr-2" /> Log Waste</Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {filtered.length === 0 ? (
                      <div className="text-center py-16 border-2 border-dashed rounded-xl">
                        <Package className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No ingredients yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Add your kitchen ingredients to track stock and calculate food costs</p>
                        <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openIngDialog()}><Plus className="h-4 w-4 mr-2" /> Add First Ingredient</Button>
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {filtered.map(i => (
                          <div key={i.ingredientId} className={`group p-3 sm:p-4 border rounded-xl transition-all hover:shadow-sm ${i.isLow ? "border-red-200 bg-red-50/50" : "hover:border-rose-200"}`}>
                            <div className="flex items-start gap-3 sm:gap-4">
                              <div className={`h-10 w-10 rounded-lg flex items-center justify-center flex-shrink-0 ${i.isLow ? "bg-red-100" : "bg-gray-100"}`}>
                                <Package className={`h-5 w-5 ${i.isLow ? "text-red-600" : "text-gray-500"}`} />
                              </div>
                              <div className="flex-1 min-w-0">
                                <div className="flex flex-wrap items-center gap-x-2 gap-y-1">
                                  <h4 className="font-semibold text-gray-900 break-words">{i.name}</h4>
                                  {i.category && <Badge variant="outline" className="text-[10px] h-5">{i.category}</Badge>}
                                  {i.isLow && <Badge className="text-[10px] h-5 bg-red-100 text-red-700">Low Stock</Badge>}
                                  {i.storageArea && <Badge variant="outline" className="text-[10px] h-5 bg-blue-50">{i.storageArea}</Badge>}
                                </div>
                                <div className="flex flex-wrap items-center gap-x-3 gap-y-0.5 mt-1 text-xs text-muted-foreground">
                                  <span>Stock: <strong>{i.currentStock} {i.unit}</strong></span>
                                  <span>Cost: {i.costPerUnit.toFixed(2)}/{i.unit}</span>
                                  {i.reorderPoint > 0 && <span>Reorder at: {i.reorderPoint}</span>}
                                  {i.supplierName && <span>Supplier: {i.supplierName}</span>}
                                </div>
                              </div>
                              <div className="text-right flex-shrink-0">
                                <div className="font-bold text-gray-900 whitespace-nowrap">{(i.currentStock * i.costPerUnit).toFixed(2)}</div>
                                <div className="text-xs text-muted-foreground">value</div>
                              </div>
                            </div>
                            {/* Actions stay visible below sm. A touch screen has no hover, so
                                gating them on group-hover hid Adjust/Edit/Delete completely
                                on a phone -- that was a reachability bug, not just styling. */}
                            <div className="flex gap-1 mt-3 pt-3 border-t sm:mt-0 sm:pt-0 sm:border-t-0 sm:opacity-0 sm:group-hover:opacity-100 sm:focus-within:opacity-100 sm:transition-opacity sm:justify-end">
                              <Button variant="outline" size="sm" className="h-8 flex-1 sm:flex-none sm:h-7 text-xs" onClick={() => { setAdjustId(i.ingredientId); setAdjustQty(0); setAdjustType("PurchaseIn"); setAdjustReason(""); setAdjustDialogOpen(true) }}>Adjust</Button>
                              <Button variant="outline" size="sm" className="h-8 flex-1 sm:flex-none sm:h-7 sm:w-7 sm:p-0 text-xs" onClick={() => openIngDialog(i)}><Edit2 className="h-3 w-3 mr-1 sm:mr-0" /><span className="sm:hidden">Edit</span></Button>
                              <Button variant="outline" size="sm" className="h-8 flex-1 sm:flex-none sm:h-7 sm:w-7 sm:p-0 text-xs" onClick={() => delIng(i.ingredientId)}><Trash2 className="h-3 w-3 text-red-500 mr-1 sm:mr-0" /><span className="sm:hidden">Delete</span></Button>
                            </div>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Waste Tab */}
              <TabsContent value="waste">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-9 w-9 rounded-lg bg-amber-100 flex items-center justify-center"><TrendingDown className="h-5 w-5 text-amber-600" /></div>
                        <div><CardTitle className="text-lg">Waste Log</CardTitle><CardDescription>Track and analyze kitchen waste</CardDescription></div>
                      </div>
                      <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => { setWasteForm({ ingredientName: "", quantity: 0, unit: "kg", reason: "Spoilage" }); setWasteDialogOpen(true) }}><Plus className="h-4 w-4 mr-2" /> Log Waste</Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {wasteSummary.length > 0 && (
                      <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-3 mb-4">
                        {wasteSummary.map(ws => (
                          <Card key={ws.reason} className="bg-amber-50"><CardContent className="py-3 px-4">
                            <div className="font-bold text-amber-800">{ws.totalCost.toFixed(2)}</div>
                            <div className="text-xs text-amber-600">{ws.reason} ({ws.count}x)</div>
                          </CardContent></Card>
                        ))}
                      </div>
                    )}
                    {wasteLog.length === 0 ? (
                      <p className="text-center py-8 text-muted-foreground text-sm">No waste logged yet</p>
                    ) : (
                      <div className="space-y-2">
                        {wasteLog.slice(0, 20).map(w => (
                          <div key={w.wasteLogId} className="flex items-center justify-between p-3 border rounded-lg">
                            <div>
                              <span className="font-medium">{w.ingredientName}</span>
                              <Badge variant="outline" className="ml-2 text-[10px] h-5">{w.reason}</Badge>
                              <div className="text-xs text-muted-foreground mt-0.5">{w.quantity} {w.unit} | {new Date(w.createdAt).toLocaleDateString()} {w.loggedBy && `by ${w.loggedBy}`}</div>
                            </div>
                            <span className="font-bold text-amber-700">{w.costAmount.toFixed(2)}</span>
                          </div>
                        ))}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Value Tab */}
              <TabsContent value="value">
                <Card>
                  <CardHeader>
                    <div className="flex items-center gap-2">
                      <div className="h-9 w-9 rounded-lg bg-blue-100 flex items-center justify-center"><DollarSign className="h-5 w-5 text-blue-600" /></div>
                      <div><CardTitle className="text-lg">Inventory Valuation</CardTitle><CardDescription>Total value: <strong>{totalValue.toFixed(2)}</strong></CardDescription></div>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {invValue.length === 0 ? (
                      <p className="text-center py-8 text-muted-foreground text-sm">No inventory data</p>
                    ) : (
                      <div className="space-y-2">
                        {invValue.map(v => (
                          <div key={v.ingredientId} className={`flex items-center justify-between p-3 border rounded-lg ${v.isLow ? "border-red-200 bg-red-50/50" : ""}`}>
                            <div className="flex items-center gap-3">
                              {v.isLow && <AlertTriangle className="h-4 w-4 text-red-500" />}
                              <div>
                                <span className="font-medium">{v.name}</span>
                                {v.category && <Badge variant="outline" className="ml-2 text-[10px] h-4">{v.category}</Badge>}
                                <div className="text-xs text-muted-foreground">{v.currentStock} {v.unit} x {v.costPerUnit.toFixed(2)}</div>
                              </div>
                            </div>
                            <span className="font-bold">{v.totalValue.toFixed(2)}</span>
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

      {/* Ingredient Dialog */}
      <Dialog open={ingDialogOpen} onOpenChange={setIngDialogOpen}>
        <DialogContent className="sm:max-w-lg">
          <DialogHeader><DialogTitle>{ingEditing ? "Edit Ingredient" : "Add Ingredient"}</DialogTitle><DialogDescription>Track raw materials and supplies</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Name <span className="text-rose-500">*</span></Label><Input value={ingForm.name} onChange={e => setIngForm({ ...ingForm, name: e.target.value })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Category</Label>
                <OtherSelect
                  ref={ingCategoryOther}
                  listKey="IngredientCategory"
                  baseOptions={CATEGORIES}
                  value={ingForm.category || undefined}
                  onChange={v => setIngForm({ ...ingForm, category: v })}
                  placeholder="Select"
                /></div>
              <div className="space-y-1.5"><Label>Unit</Label>
                <Select value={ingForm.unit || "kg"} onValueChange={v => setIngForm({ ...ingForm, unit: v })}>
                  <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                  <SelectContent>{UNITS.map(u => <SelectItem key={u} value={u}>{u}</SelectItem>)}</SelectContent>
                </Select></div>
              <div className="space-y-1.5"><Label>Cost per Unit</Label><Input type="number" step="0.01" value={ingForm.costPerUnit || 0} onChange={e => setIngForm({ ...ingForm, costPerUnit: parseFloat(e.target.value) || 0 })} className="h-10" /></div>
              {!ingEditing && <div className="space-y-1.5"><Label>Opening Stock</Label><Input type="number" step="0.01" value={ingForm.currentStock || 0} onChange={e => setIngForm({ ...ingForm, currentStock: parseFloat(e.target.value) || 0 })} className="h-10" /></div>}
              <div className="space-y-1.5"><Label>Reorder Point</Label><Input type="number" step="0.01" value={ingForm.reorderPoint || 0} onChange={e => setIngForm({ ...ingForm, reorderPoint: parseFloat(e.target.value) || 0 })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Storage Area</Label>
                <Select value={ingForm.storageArea || ""} onValueChange={v => setIngForm({ ...ingForm, storageArea: v })}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Select" /></SelectTrigger>
                  <SelectContent>{STORAGE_AREAS.map(s => <SelectItem key={s} value={s}>{s}</SelectItem>)}</SelectContent>
                </Select></div>
              <div className="space-y-1.5"><Label>Supplier</Label>
                <Select value={ingForm.supplierName || "__none__"} onValueChange={v => setIngForm({ ...ingForm, supplierName: v === "__none__" ? "" : v })}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Select supplier" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">None</SelectItem>
                    {suppliers.map((s: any) => <SelectItem key={s.restaurantsupplierid} value={s.name}>{s.name}{s.category ? ` (${s.category})` : ""}</SelectItem>)}
                  </SelectContent>
                </Select>
              </div>
            </div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setIngDialogOpen(false)}>Cancel</Button><Button onClick={saveIng} className="bg-rose-600 hover:bg-rose-700">{ingEditing ? "Update" : "Add Ingredient"}</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Adjust Stock Dialog */}
      <Dialog open={adjustDialogOpen} onOpenChange={setAdjustDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>Adjust Stock</DialogTitle><DialogDescription>Record stock received or removed</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5"><Label>Type</Label>
              <Select value={adjustType} onValueChange={setAdjustType}>
                <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="PurchaseIn">Purchase / Received (+)</SelectItem>
                  <SelectItem value="AdjustmentIn">Adjustment In (+)</SelectItem>
                  <SelectItem value="AdjustmentOut">Adjustment Out (-)</SelectItem>
                  <SelectItem value="TransferOut">Transfer Out (-)</SelectItem>
                </SelectContent>
              </Select></div>
            <div className="space-y-1.5"><Label>Quantity</Label><Input type="number" step="0.01" value={adjustQty} onChange={e => setAdjustQty(parseFloat(e.target.value) || 0)} className="h-10" /></div>
            {adjustType === "TransferOut" && (
              <div className="space-y-1.5"><Label>Destination *</Label>
                <Select value={adjustReason || "__none__"} onValueChange={v => setAdjustReason(v === "__none__" ? "" : v)}>
                  <SelectTrigger className="h-10"><SelectValue placeholder="Where is it going?" /></SelectTrigger>
                  <SelectContent>
                    <SelectItem value="__none__">Select destination</SelectItem>
                    {suppliers.map((s: any) => <SelectItem key={s.restaurantsupplierid} value={`To: ${s.name}`}>{s.name}</SelectItem>)}
                    <SelectItem value="To: Another branch">Another branch</SelectItem>
                    <SelectItem value="To: Donation">Donation</SelectItem>
                    <SelectItem value="To: Return to supplier">Return to supplier</SelectItem>
                    <SelectItem value="To: Other">Other</SelectItem>
                  </SelectContent>
                </Select>
              </div>
            )}
            {adjustType !== "TransferOut" && (
              <div className="space-y-1.5"><Label>Reason</Label><Input value={adjustReason} onChange={e => setAdjustReason(e.target.value)} placeholder="e.g. Supplier delivery, count correction" className="h-10" /></div>
            )}
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setAdjustDialogOpen(false)}>Cancel</Button><Button onClick={handleAdjust} className="bg-rose-600 hover:bg-rose-700">Apply</Button></DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Waste Dialog */}
      <Dialog open={wasteDialogOpen} onOpenChange={setWasteDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader><DialogTitle>Log Waste</DialogTitle><DialogDescription>Record spoilage, prep waste, or expired items</DialogDescription></DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5"><Label>Ingredient</Label>
              <Select onValueChange={v => { const ing = ingredients.find(i => i.ingredientId === parseInt(v)); if (ing) setWasteForm({ ...wasteForm, ingredientId: ing.ingredientId, ingredientName: ing.name, unit: ing.unit, costAmount: ing.costPerUnit * wasteForm.quantity }) }}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select ingredient" /></SelectTrigger>
                <SelectContent>{ingredients.map(i => <SelectItem key={i.ingredientId} value={String(i.ingredientId)}>{i.name} ({i.currentStock} {i.unit})</SelectItem>)}</SelectContent>
              </Select></div>
            <div className="grid grid-cols-1 sm:grid-cols-2 gap-3">
              <div className="space-y-1.5"><Label>Quantity</Label><Input type="number" step="0.01" value={wasteForm.quantity} onChange={e => setWasteForm({ ...wasteForm, quantity: parseFloat(e.target.value) || 0 })} className="h-10" /></div>
              <div className="space-y-1.5"><Label>Reason</Label>
                <OtherSelect
                  ref={wasteReasonOther}
                  listKey="WasteReason"
                  baseOptions={WASTE_REASONS}
                  value={wasteForm.reason || undefined}
                  onChange={v => setWasteForm({ ...wasteForm, reason: v || "Spoilage" })}
                  placeholder="Select a reason"
                /></div>
            </div>
            <div className="space-y-1.5"><Label>Notes</Label><Input value={wasteForm.notes || ""} onChange={e => setWasteForm({ ...wasteForm, notes: e.target.value })} className="h-10" /></div>
          </div>
          <DialogFooter><Button variant="outline" onClick={() => setWasteDialogOpen(false)}>Cancel</Button><Button onClick={handleLogWaste} className="bg-rose-600 hover:bg-rose-700">Log Waste</Button></DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

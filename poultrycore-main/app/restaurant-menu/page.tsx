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
import { Plus, Trash2, Edit2, Eye, EyeOff, Search, UtensilsCrossed, LayoutGrid, Package, DollarSign, Clock, Flame, Leaf, AlertTriangle, ChevronDown, ChevronRight } from "lucide-react"
import { PageSkeleton } from "@/components/restaurant/skeleton-loaders"
import { Badge } from "@/components/ui/badge"
import { useAuthStore } from "@/lib/store/auth-store"
import { useToast } from "@/hooks/use-toast"
import {
  listMenuCategories, createMenuCategory, updateMenuCategory, deleteMenuCategory,
  listMenuItems, createMenuItem, updateMenuItem, deleteMenuItem, toggleMenuItemAvailability,
  listCombos, createCombo, updateCombo, deleteCombo,
  listComboItems, addComboItem, removeComboItem,
  listMenuCategoryTypes, listMenuItemNames, listIngredients, listRecipe, upsertRecipe, deleteRecipe,
  type MenuCategory, type MenuCategoryInput, type MenuCategoryType, type MenuItemName,
  type MenuItem, type MenuItemInput, type Ingredient, type Recipe,
  type Combo, type ComboInput, type ComboItem, type ComboItemInput,
} from "@/lib/api/restaurant"

const DIETARY_OPTIONS = [
  { key: "isVegetarian", label: "Vegetarian", emoji: "🥬", color: "bg-green-100 text-green-700 border-green-200" },
  { key: "isVegan", label: "Vegan", emoji: "🌱", color: "bg-emerald-100 text-emerald-700 border-emerald-200" },
  { key: "isGlutenFree", label: "Gluten-Free", emoji: "🌾", color: "bg-amber-100 text-amber-700 border-amber-200" },
  { key: "isHalal", label: "Halal", emoji: "☪️", color: "bg-blue-100 text-blue-700 border-blue-200" },
  { key: "isKosher", label: "Kosher", emoji: "✡️", color: "bg-purple-100 text-purple-700 border-purple-200" },
]

export default function RestaurantMenuPage() {
  const router = useRouter()
  const { toast } = useToast()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)

  const [loading, setLoading] = useState(true)
  const [search, setSearch] = useState("")
  const [filterCat, setFilterCat] = useState<number | null>(null)

  const [categories, setCategories] = useState<MenuCategory[]>([])
  const [categoryTypes, setCategoryTypes] = useState<MenuCategoryType[]>([])
  const [menuItemNames, setMenuItemNames] = useState<MenuItemName[]>([])
  const [itemNameSelection, setItemNameSelection] = useState("")
  const [allIngredients, setAllIngredients] = useState<Ingredient[]>([])
  const [itemRecipe, setItemRecipe] = useState<Recipe[]>([])
  const [recipeAddIng, setRecipeAddIng] = useState(0)
  const [recipeAddQty, setRecipeAddQty] = useState(1)
  const [recipeAddUnit, setRecipeAddUnit] = useState("kg")
  const [recipeAddWaste, setRecipeAddWaste] = useState(0)
  const [catDialogOpen, setCatDialogOpen] = useState(false)
  const [catEditing, setCatEditing] = useState<MenuCategory | null>(null)
  const [catForm, setCatForm] = useState<MenuCategoryInput>({ name: "" })

  const [items, setItems] = useState<MenuItem[]>([])
  const [itemDialogOpen, setItemDialogOpen] = useState(false)
  const [itemEditing, setItemEditing] = useState<MenuItem | null>(null)
  const [itemForm, setItemForm] = useState<MenuItemInput>({ name: "", price: 0 })

  const [combos, setCombos] = useState<Combo[]>([])
  const [comboDialogOpen, setComboDialogOpen] = useState(false)
  const [comboEditing, setComboEditing] = useState<Combo | null>(null)
  const [comboForm, setComboForm] = useState<ComboInput>({ name: "", price: 0 })
  const [comboItems, setComboItems] = useState<Record<number, ComboItem[]>>({})
  const [addComboItemDialog, setAddComboItemDialog] = useState<number | null>(null)
  const [addComboItemId, setAddComboItemId] = useState<number>(0)
  const [expandedCombos, setExpandedCombos] = useState<Set<number>>(new Set())

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    loadAll()
  }, [activeFarmType, router])

  async function loadAll() {
    setLoading(true)
    try {
      const [cats, itms, cmbs, ctypes, mins, ings] = await Promise.all([listMenuCategories(), listMenuItems(), listCombos(), listMenuCategoryTypes().catch(() => []), listMenuItemNames().catch(() => []), listIngredients().catch(() => [])])
      setCategories(cats); setItems(itms); setCombos(cmbs); setCategoryTypes(ctypes); setMenuItemNames(mins); setAllIngredients(ings)
    } catch (e: any) { toast({ title: "Failed to load", description: e?.message, variant: "destructive" }) }
    finally { setLoading(false) }
  }

  // Categories
  function openCatDialog(c?: MenuCategory) {
    if (c) { setCatEditing(c); setCatForm({ name: c.name, description: c.description, parentCategoryId: c.parentCategoryId, imageUrl: c.imageUrl, sortOrder: c.sortOrder, isActive: c.isActive }) }
    else { setCatEditing(null); setCatForm({ name: "", isActive: true, sortOrder: 0 }) }
    setCatDialogOpen(true)
  }
  async function saveCat() {
    if (!catForm.name.trim()) { toast({ title: "Category name required", variant: "destructive" }); return }
    const dup = categories.find(c => c.name.toLowerCase() === catForm.name.trim().toLowerCase() && (!catEditing || c.menuCategoryId !== catEditing.menuCategoryId))
    if (dup) { toast({ title: "Duplicate name", description: `A category named "${catForm.name}" already exists.`, variant: "destructive" }); return }
    try { if (catEditing) await updateMenuCategory(catEditing.menuCategoryId, catForm); else await createMenuCategory(catForm)
      toast({ title: catEditing ? "Category updated" : "Category created" }); setCatDialogOpen(false); setCategories(await listMenuCategories())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function deleteCat(id: number) { try { await deleteMenuCategory(id); toast({ title: "Deleted" }); setCategories(await listMenuCategories()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }

  // Items
  function openItemDialog(i?: MenuItem) {
    if (i) {
      setItemEditing(i); setItemForm({ name: i.name, menuCategoryId: i.menuCategoryId, description: i.description, price: i.price, costPrice: i.costPrice, imageUrl: i.imageUrl, prepTime: i.prepTime, calories: i.calories, allergens: i.allergens, spicyLevel: i.spicyLevel, isVegetarian: i.isVegetarian, isVegan: i.isVegan, isGlutenFree: i.isGlutenFree, isHalal: i.isHalal, isKosher: i.isKosher, isAvailable: i.isAvailable, isActive: i.isActive, sortOrder: i.sortOrder, sku: i.sku, barcode: i.barcode })
      listRecipe(i.menuItemId).then(setItemRecipe).catch(() => setItemRecipe([]))
    } else {
      setItemEditing(null); setItemForm({ name: "", price: 0, costPrice: 0, isAvailable: true, isActive: true })
      setItemRecipe([])
    }
    setRecipeAddIng(0); setRecipeAddQty(1); setRecipeAddUnit("kg"); setRecipeAddWaste(0)
    setItemNameSelection("")
    setItemDialogOpen(true)
  }
  async function saveItem() {
    if (!itemForm.name.trim()) { toast({ title: "Item name required", variant: "destructive" }); return }
    try { if (itemEditing) await updateMenuItem(itemEditing.menuItemId, itemForm); else await createMenuItem(itemForm)
      toast({ title: itemEditing ? "Item updated" : "Item created" }); setItemDialogOpen(false); setItems(await listMenuItems())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function deleteItem(id: number) { try { await deleteMenuItem(id); toast({ title: "Deleted" }); setItems(await listMenuItems()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function toggle86(item: MenuItem) {
    try { await toggleMenuItemAvailability(item.menuItemId, !item.isAvailable); toast({ title: item.isAvailable ? "Item 86'd" : "Item back on menu" }); setItems(await listMenuItems()) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  // Combos
  function openComboDialog(c?: Combo) {
    if (c) { setComboEditing(c); setComboForm({ name: c.name, description: c.description, price: c.price, imageUrl: c.imageUrl, isActive: c.isActive }) }
    else { setComboEditing(null); setComboForm({ name: "", price: 0, isActive: true }) }
    setComboDialogOpen(true)
  }
  async function saveCombo() {
    if (!comboForm.name.trim()) { toast({ title: "Combo name required", variant: "destructive" }); return }
    try { if (comboEditing) await updateCombo(comboEditing.comboId, comboForm); else await createCombo(comboForm)
      toast({ title: comboEditing ? "Combo updated" : "Combo created" }); setComboDialogOpen(false); setCombos(await listCombos())
    } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function deleteComboFn(id: number) { try { await deleteCombo(id); toast({ title: "Deleted" }); setCombos(await listCombos()) } catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) } }
  async function toggleComboExpand(comboId: number) {
    const next = new Set(expandedCombos)
    if (next.has(comboId)) { next.delete(comboId) } else { next.add(comboId); if (!comboItems[comboId]) { const ci = await listComboItems(comboId); setComboItems(prev => ({ ...prev, [comboId]: ci })) } }
    setExpandedCombos(next)
  }
  async function handleAddComboItem(comboId: number) {
    if (!addComboItemId) return
    try { await addComboItem(comboId, { menuItemId: addComboItemId, quantity: 1, sortOrder: 0 }); toast({ title: "Item added" }); setAddComboItemDialog(null); const ci = await listComboItems(comboId); setComboItems(prev => ({ ...prev, [comboId]: ci })) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }
  async function handleRemoveComboItem(id: number, comboId: number) {
    try { await removeComboItem(id); const ci = await listComboItems(comboId); setComboItems(prev => ({ ...prev, [comboId]: ci })) }
    catch (e: any) { toast({ title: "Failed", description: e?.message, variant: "destructive" }) }
  }

  const filteredItems = items.filter(i => {
    if (filterCat && i.menuCategoryId !== filterCat) return false
    if (search && !i.name.toLowerCase().includes(search.toLowerCase())) return false
    return true
  })
  const availableCount = items.filter(i => i.isAvailable).length
  const unavailableCount = items.filter(i => !i.isAvailable).length

  if (loading) return <PageSkeleton />

  return (
    <div className="flex h-screen bg-gray-50">
      <DashboardSidebar />
      <div className="flex-1 flex flex-col overflow-hidden">
        <DashboardHeader />
        <main className="flex-1 overflow-y-auto p-6">
          <div className="max-w-6xl mx-auto space-y-6">
            {/* Page Header */}
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="h-10 w-10 rounded-lg bg-rose-100 flex items-center justify-center">
                  <UtensilsCrossed className="h-5 w-5 text-rose-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-gray-900">Menu Management</h1>
                  <p className="text-sm text-muted-foreground">{items.length} items across {categories.length} categories</p>
                </div>
              </div>
              <Button onClick={() => openItemDialog()} className="bg-rose-600 hover:bg-rose-700">
                <Plus className="h-4 w-4 mr-2" /> Add Menu Item
              </Button>
            </div>

            {/* Stats cards */}
            <div className="grid grid-cols-4 gap-3">
              {[
                { label: "Total Items", value: items.length, color: "text-gray-900", bg: "bg-white" },
                { label: "Available", value: availableCount, color: "text-green-700", bg: "bg-green-50" },
                { label: "86'd Items", value: unavailableCount, color: "text-red-700", bg: "bg-red-50" },
                { label: "Combos", value: combos.length, color: "text-blue-700", bg: "bg-blue-50" },
              ].map(s => (
                <Card key={s.label} className={s.bg}>
                  <CardContent className="py-3 px-4">
                    <div className={`text-2xl font-bold ${s.color}`}>{s.value}</div>
                    <div className="text-xs text-muted-foreground">{s.label}</div>
                  </CardContent>
                </Card>
              ))}
            </div>

            <Tabs defaultValue="items" className="space-y-4">
              <TabsList className="bg-white border shadow-sm">
                <TabsTrigger value="items" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <UtensilsCrossed className="h-4 w-4 mr-2" /> Menu Items
                  <Badge variant="secondary" className="ml-2 h-5 px-1.5">{items.length}</Badge>
                </TabsTrigger>
                <TabsTrigger value="categories" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <LayoutGrid className="h-4 w-4 mr-2" /> Categories
                  <Badge variant="secondary" className="ml-2 h-5 px-1.5">{categories.length}</Badge>
                </TabsTrigger>
                <TabsTrigger value="combos" className="data-[state=active]:bg-rose-50 data-[state=active]:text-rose-700">
                  <Package className="h-4 w-4 mr-2" /> Combos
                  <Badge variant="secondary" className="ml-2 h-5 px-1.5">{combos.length}</Badge>
                </TabsTrigger>
              </TabsList>

              {/* ===== ITEMS TAB ===== */}
              <TabsContent value="items">
                <Card>
                  <CardHeader className="pb-4">
                    <div className="flex items-center gap-3">
                      <div className="relative flex-1">
                        <Search className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                        <Input className="pl-9 h-10" placeholder="Search menu items..." value={search} onChange={e => setSearch(e.target.value)} />
                      </div>
                      <Select value={filterCat ? String(filterCat) : "all"} onValueChange={v => setFilterCat(v === "all" ? null : parseInt(v))}>
                        <SelectTrigger className="w-[200px] h-10"><SelectValue placeholder="All Categories" /></SelectTrigger>
                        <SelectContent>
                          <SelectItem value="all">All Categories</SelectItem>
                          {categories.map(c => <SelectItem key={c.menuCategoryId} value={String(c.menuCategoryId)}>{c.name} ({items.filter(i => i.menuCategoryId === c.menuCategoryId).length})</SelectItem>)}
                        </SelectContent>
                      </Select>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {filteredItems.length === 0 ? (
                      <div className="text-center py-16 border-2 border-dashed rounded-xl">
                        <UtensilsCrossed className="h-12 w-12 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">{search || filterCat ? "No items match your search" : "No menu items yet"}</h3>
                        <p className="text-sm text-muted-foreground mb-4">{search || filterCat ? "Try adjusting your search or filter" : "Start building your menu by adding your first item"}</p>
                        {!search && !filterCat && <Button className="bg-rose-600 hover:bg-rose-700" onClick={() => openItemDialog()}><Plus className="h-4 w-4 mr-2" /> Add your first item</Button>}
                      </div>
                    ) : (
                      <div className="space-y-2">
                        {filteredItems.map(i => {
                          const margin = i.costPrice > 0 ? Math.round((i.price - i.costPrice) / i.price * 100) : null
                          return (
                            <div key={i.menuItemId} className={`group flex items-center gap-4 p-4 border rounded-xl transition-all hover:shadow-sm ${
                              !i.isAvailable ? "bg-red-50/50 border-red-200" : "hover:border-rose-200"
                            }`}>
                              {/* Image */}
                              {i.imageUrl && (
                                <div className="w-14 h-14 rounded-lg overflow-hidden border flex-shrink-0">
                                  <img src={i.imageUrl} alt={i.name} className="w-full h-full object-cover" onError={e => (e.currentTarget.style.display = "none")} />
                                </div>
                              )}
                              {/* Item info */}
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2 flex-wrap">
                                  <h4 className="font-semibold text-gray-900">{i.name}</h4>
                                  {i.categoryName && <Badge variant="outline" className="text-[10px] h-5 bg-gray-50">{i.categoryName}</Badge>}
                                  {!i.isAvailable && <Badge className="text-[10px] h-5 bg-red-100 text-red-700 hover:bg-red-100">86'd — Unavailable</Badge>}
                                  {DIETARY_OPTIONS.filter(d => (i as any)[d.key]).map(d => (
                                    <span key={d.key} className={`inline-flex items-center gap-0.5 text-[10px] h-5 px-1.5 rounded-full border ${d.color}`}>
                                      {d.emoji} {d.label}
                                    </span>
                                  ))}
                                  {i.spicyLevel > 0 && <span className="text-xs">{"🌶️".repeat(Math.min(i.spicyLevel, 5))}</span>}
                                </div>
                                {i.description && <p className="text-sm text-muted-foreground mt-1 line-clamp-1">{i.description}</p>}
                                <div className="flex items-center gap-3 mt-1.5 text-xs text-muted-foreground">
                                  {i.prepTime > 0 && <span className="flex items-center gap-1"><Clock className="h-3 w-3" />{i.prepTime} min</span>}
                                  {i.calories && <span>{i.calories} cal</span>}
                                  {i.allergens && <span className="flex items-center gap-1"><AlertTriangle className="h-3 w-3" />{i.allergens}</span>}
                                  {i.sku && <span>SKU: {i.sku}</span>}
                                </div>
                              </div>
                              {/* Pricing */}
                              <div className="text-right flex-shrink-0 min-w-[100px]">
                                <div className="text-lg font-bold text-gray-900">{i.price.toFixed(2)}</div>
                                {i.costPrice > 0 && (
                                  <div className="text-xs text-muted-foreground">
                                    Cost: {i.costPrice.toFixed(2)}
                                    {margin !== null && <span className={`ml-1 font-medium ${margin >= 60 ? "text-green-600" : margin >= 30 ? "text-amber-600" : "text-red-600"}`}>{margin}%</span>}
                                  </div>
                                )}
                              </div>
                              {/* Actions */}
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity flex-shrink-0">
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => toggle86(i)} title={i.isAvailable ? "Mark 86'd" : "Back on menu"}>
                                  {i.isAvailable ? <EyeOff className="h-4 w-4 text-gray-500" /> : <Eye className="h-4 w-4 text-green-600" />}
                                </Button>
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openItemDialog(i)}><Edit2 className="h-4 w-4" /></Button>
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => deleteItem(i.menuItemId)}><Trash2 className="h-4 w-4 text-red-500" /></Button>
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ===== CATEGORIES TAB ===== */}
              <TabsContent value="categories">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-9 w-9 rounded-lg bg-amber-100 flex items-center justify-center"><LayoutGrid className="h-5 w-5 text-amber-600" /></div>
                        <div>
                          <CardTitle className="text-lg">Menu Categories</CardTitle>
                          <CardDescription>Organize your menu items into logical groups</CardDescription>
                        </div>
                      </div>
                      <Button onClick={() => openCatDialog()} className="bg-rose-600 hover:bg-rose-700"><Plus className="h-4 w-4 mr-2" /> Add Category</Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {categories.length === 0 ? (
                      <div className="text-center py-12 border-2 border-dashed rounded-xl">
                        <LayoutGrid className="h-10 w-10 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No categories yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create categories like Appetizers, Main Course, Desserts, Beverages</p>
                        <Button variant="outline" onClick={() => openCatDialog()}><Plus className="h-4 w-4 mr-2" /> Create your first category</Button>
                      </div>
                    ) : (
                      <div className="grid grid-cols-1 md:grid-cols-2 gap-3">
                        {categories.map(c => {
                          const count = items.filter(i => i.menuCategoryId === c.menuCategoryId).length
                          return (
                            <div key={c.menuCategoryId} className="group flex items-center gap-4 p-4 border rounded-xl hover:border-rose-200 hover:shadow-sm transition-all">
                              <div className={`h-12 w-12 rounded-xl flex items-center justify-center flex-shrink-0 ${c.isActive ? "bg-rose-100" : "bg-gray-100"}`}>
                                <LayoutGrid className={`h-6 w-6 ${c.isActive ? "text-rose-600" : "text-gray-400"}`} />
                              </div>
                              <div className="flex-1 min-w-0">
                                <div className="flex items-center gap-2">
                                  <h4 className="font-semibold text-gray-900">{c.name}</h4>
                                  {!c.isActive && <Badge variant="secondary" className="text-[10px] h-4">Inactive</Badge>}
                                </div>
                                {c.description && <p className="text-sm text-muted-foreground mt-0.5 truncate">{c.description}</p>}
                                <p className="text-xs text-muted-foreground mt-1">{count} item{count !== 1 ? "s" : ""}</p>
                              </div>
                              <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity">
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openCatDialog(c)}><Edit2 className="h-3.5 w-3.5" /></Button>
                                <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => deleteCat(c.menuCategoryId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                              </div>
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>

              {/* ===== COMBOS TAB ===== */}
              <TabsContent value="combos">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className="h-9 w-9 rounded-lg bg-blue-100 flex items-center justify-center"><Package className="h-5 w-5 text-blue-600" /></div>
                        <div>
                          <CardTitle className="text-lg">Combos & Meal Deals</CardTitle>
                          <CardDescription>Bundle menu items together at a special price</CardDescription>
                        </div>
                      </div>
                      <Button onClick={() => openComboDialog()} className="bg-rose-600 hover:bg-rose-700"><Plus className="h-4 w-4 mr-2" /> Add Combo</Button>
                    </div>
                  </CardHeader>
                  <CardContent>
                    {combos.length === 0 ? (
                      <div className="text-center py-12 border-2 border-dashed rounded-xl">
                        <Package className="h-10 w-10 mx-auto text-gray-300 mb-3" />
                        <h3 className="font-medium text-gray-900 mb-1">No combos yet</h3>
                        <p className="text-sm text-muted-foreground mb-4">Create meal deals by bundling items together at a discounted price</p>
                        <Button variant="outline" onClick={() => openComboDialog()}><Plus className="h-4 w-4 mr-2" /> Create your first combo</Button>
                      </div>
                    ) : (
                      <div className="space-y-3">
                        {combos.map(cb => {
                          const expanded = expandedCombos.has(cb.comboId)
                          const cbItems = comboItems[cb.comboId] || []
                          return (
                            <div key={cb.comboId} className="border rounded-xl overflow-hidden">
                              <div className="group flex items-center gap-4 p-4 cursor-pointer hover:bg-gray-50/50 transition-colors" onClick={() => toggleComboExpand(cb.comboId)}>
                                <div className={`h-10 w-10 rounded-lg flex items-center justify-center flex-shrink-0 ${cb.isActive ? "bg-blue-100" : "bg-gray-100"}`}>
                                  <Package className={`h-5 w-5 ${cb.isActive ? "text-blue-600" : "text-gray-400"}`} />
                                </div>
                                <div className="flex-1 min-w-0">
                                  <div className="flex items-center gap-2">
                                    <h4 className="font-semibold text-gray-900">{cb.name}</h4>
                                    {!cb.isActive && <Badge variant="secondary" className="text-[10px] h-4">Inactive</Badge>}
                                  </div>
                                  {cb.description && <p className="text-sm text-muted-foreground mt-0.5">{cb.description}</p>}
                                </div>
                                <div className="text-right flex-shrink-0 mr-2">
                                  <div className="text-lg font-bold text-gray-900">{cb.price.toFixed(2)}</div>
                                </div>
                                <div className="flex items-center gap-1">
                                  {expanded ? <ChevronDown className="h-4 w-4 text-gray-400" /> : <ChevronRight className="h-4 w-4 text-gray-400" />}
                                  <div className="flex gap-1 opacity-0 group-hover:opacity-100 transition-opacity" onClick={e => e.stopPropagation()}>
                                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => openComboDialog(cb)}><Edit2 className="h-3.5 w-3.5" /></Button>
                                    <Button variant="ghost" size="icon" className="h-8 w-8" onClick={() => deleteComboFn(cb.comboId)}><Trash2 className="h-3.5 w-3.5 text-red-500" /></Button>
                                  </div>
                                </div>
                              </div>
                              {expanded && (
                                <div className="border-t bg-gray-50/50">
                                  <div className="divide-y">
                                    {cbItems.map(ci => (
                                      <div key={ci.comboItemId} className="flex items-center justify-between px-4 py-2.5 pl-14">
                                        <div className="flex items-center gap-2">
                                          <span className="text-sm font-medium text-rose-600">{ci.quantity}x</span>
                                          <span className="text-sm text-gray-700">{ci.menuItemName || ci.categoryName || "Unknown"}</span>
                                        </div>
                                        <Button variant="ghost" size="icon" className="h-7 w-7" onClick={() => handleRemoveComboItem(ci.comboItemId, cb.comboId)}><Trash2 className="h-3 w-3 text-red-500" /></Button>
                                      </div>
                                    ))}
                                  </div>
                                  <div className="px-4 py-2 pl-14">
                                    <Button variant="ghost" size="sm" className="text-xs text-rose-600 hover:text-rose-700 hover:bg-rose-50 -ml-2" onClick={() => { setAddComboItemDialog(cb.comboId); setAddComboItemId(items[0]?.menuItemId || 0) }}>
                                      <Plus className="h-3 w-3 mr-1" /> Add item to combo
                                    </Button>
                                  </div>
                                </div>
                              )}
                            </div>
                          )
                        })}
                      </div>
                    )}
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      {/* Category Dialog */}
      <Dialog open={catDialogOpen} onOpenChange={setCatDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{catEditing ? "Edit Category" : "Add Category"}</DialogTitle>
            <DialogDescription>Organize your menu items into logical groups</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Category Type <span className="text-rose-500">*</span></Label>
              <Select onValueChange={v => {
                if (v === "__none__") return
                setCatForm({ ...catForm, name: v })
              }}>
                <SelectTrigger className="h-10"><SelectValue placeholder="Select a category type" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="__none__">Select type</SelectItem>
                  {categoryTypes.map(t => <SelectItem key={t.restaurantMenuCategoryTypeId} value={t.description}>{t.description}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Category Name <span className="text-rose-500">*</span></Label>
              <Input value={catForm.name} onChange={e => setCatForm({ ...catForm, name: e.target.value })} placeholder="Auto-filled from type, but editable" className="h-10" />
              <p className="text-xs text-muted-foreground">Auto-filled from the type above. Edit to customise (e.g. &quot;House Appetizers&quot;).</p>
            </div>
            <div className="space-y-1.5">
              <Label>Description</Label>
              <Input value={catForm.description || ""} onChange={e => setCatForm({ ...catForm, description: e.target.value })} placeholder="Brief description (optional)" className="h-10" />
            </div>
            <div className="space-y-1.5">
              <Label>Parent Category</Label>
              <Select value={catForm.parentCategoryId ? String(catForm.parentCategoryId) : "none"} onValueChange={v => setCatForm({ ...catForm, parentCategoryId: v === "none" ? null : parseInt(v) })}>
                <SelectTrigger className="h-10"><SelectValue placeholder="None (top-level)" /></SelectTrigger>
                <SelectContent>
                  <SelectItem value="none">None (top-level)</SelectItem>
                  {categories.filter(c => c.menuCategoryId !== catEditing?.menuCategoryId).map(c => <SelectItem key={c.menuCategoryId} value={String(c.menuCategoryId)}>{c.name}</SelectItem>)}
                </SelectContent>
              </Select>
            </div>
            <div className="space-y-1.5">
              <Label>Sort Order</Label>
              <Input type="number" value={catForm.sortOrder || 0} onChange={e => setCatForm({ ...catForm, sortOrder: parseInt(e.target.value) || 0 })} className="h-10" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setCatDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveCat} className="bg-rose-600 hover:bg-rose-700">{catEditing ? "Update" : "Create Category"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Item Dialog */}
      <Dialog open={itemDialogOpen} onOpenChange={setItemDialogOpen}>
        <DialogContent className="sm:max-w-2xl max-h-[85vh] overflow-y-auto">
          <DialogHeader>
            <DialogTitle>{itemEditing ? "Edit Menu Item" : "Add Menu Item"}</DialogTitle>
            <DialogDescription>Fill in the details for this menu item</DialogDescription>
          </DialogHeader>
          <div className="space-y-6">
            {/* Basic info */}
            <div>
              <h4 className="text-sm font-medium text-gray-500 mb-3">Basic Information</h4>
              <div className="grid grid-cols-2 gap-4">
                <div className="space-y-1.5">
                  <Label>Item Name <span className="text-rose-500">*</span></Label>
                  <Select value={itemNameSelection || "__none__"} onValueChange={v => {
                    const sel = v === "__none__" ? "" : v
                    setItemNameSelection(sel)
                    if (sel && sel !== "Other") setItemForm({ ...itemForm, name: sel })
                    else if (sel === "Other") setItemForm({ ...itemForm, name: "" })
                  }}>
                    <SelectTrigger className="h-10"><SelectValue placeholder="Select or type a name" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="__none__">Select item</SelectItem>
                      {menuItemNames.map(n => <SelectItem key={n.restaurantMenuItemNameId} value={n.description}>{n.description}{n.category ? ` (${n.category})` : ""}</SelectItem>)}
                      <SelectItem value="Other">Other (type custom name)</SelectItem>
                    </SelectContent>
                  </Select>
                  {(itemNameSelection === "Other" || itemEditing) && (
                    <Input value={itemForm.name} onChange={e => setItemForm({ ...itemForm, name: e.target.value })} placeholder="Type item name" className="h-10 mt-1.5" />
                  )}
                </div>
                <div className="space-y-1.5">
                  <Label>Category</Label>
                  <Select value={itemForm.menuCategoryId ? String(itemForm.menuCategoryId) : "none"} onValueChange={v => setItemForm({ ...itemForm, menuCategoryId: v === "none" ? null : parseInt(v) })}>
                    <SelectTrigger className="h-10"><SelectValue placeholder="Uncategorized" /></SelectTrigger>
                    <SelectContent>
                      <SelectItem value="none">Uncategorized</SelectItem>
                      {categories.map(c => <SelectItem key={c.menuCategoryId} value={String(c.menuCategoryId)}>{c.name}</SelectItem>)}
                    </SelectContent>
                  </Select>
                </div>
              </div>
              <div className="mt-3 space-y-1.5">
                <Label>Description</Label>
                <textarea className="w-full min-h-[60px] rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-rose-500 focus-visible:ring-offset-2" value={itemForm.description || ""} onChange={e => setItemForm({ ...itemForm, description: e.target.value })} placeholder="Describe this dish..." />
              </div>
              <div className="mt-3 space-y-1.5">
                <Label>Image (optional)</Label>
                <div className="flex items-center gap-3">
                  <label className="flex items-center gap-2 px-4 py-2 border rounded-lg cursor-pointer hover:bg-rose-50 transition-colors text-sm">
                    <Package className="h-4 w-4 text-rose-600" /> Choose Photo
                    <input type="file" accept="image/*" className="hidden" onChange={e => {
                      const file = e.target.files?.[0]
                      if (file) {
                        const reader = new FileReader()
                        reader.onload = () => setItemForm({ ...itemForm, imageUrl: reader.result as string })
                        reader.readAsDataURL(file)
                      }
                    }} />
                  </label>
                  {itemForm.imageUrl && (
                    <div className="relative w-16 h-16 rounded-lg overflow-hidden border">
                      <img src={itemForm.imageUrl} alt="Preview" className="w-full h-full object-cover" />
                      <button type="button" onClick={() => setItemForm({ ...itemForm, imageUrl: "" })} className="absolute top-0 right-0 bg-red-500 text-white rounded-bl-lg p-0.5"><Trash2 className="h-3 w-3" /></button>
                    </div>
                  )}
                </div>
              </div>
            </div>

            {/* Pricing */}
            <div>
              <h4 className="text-sm font-medium text-gray-500 mb-3 flex items-center gap-1.5"><DollarSign className="h-3.5 w-3.5" /> Pricing</h4>
              <div className="grid grid-cols-3 gap-4">
                <div className="space-y-1.5">
                  <Label>Selling Price <span className="text-rose-500">*</span></Label>
                  <div className="relative"><DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input type="number" step="0.01" value={itemForm.price} onChange={e => setItemForm({ ...itemForm, price: parseFloat(e.target.value) || 0 })} className="h-10 pl-9" /></div>
                </div>
                <div className="space-y-1.5">
                  <Label>Cost Price</Label>
                  <div className="relative"><DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
                  <Input type="number" step="0.01" value={itemForm.costPrice || 0} onChange={e => setItemForm({ ...itemForm, costPrice: parseFloat(e.target.value) || 0 })} className="h-10 pl-9" /></div>
                </div>
                <div className="space-y-1.5">
                  <Label>Margin</Label>
                  <div className="h-10 rounded-md border bg-gray-50 flex items-center justify-center text-sm font-medium">
                    {itemForm.costPrice && itemForm.price ? `${Math.round((itemForm.price - itemForm.costPrice) / itemForm.price * 100)}%` : "—"}
                  </div>
                </div>
              </div>
            </div>

            {/* Details */}
            <div>
              <h4 className="text-sm font-medium text-gray-500 mb-3 flex items-center gap-1.5"><Clock className="h-3.5 w-3.5" /> Details</h4>
              <div className="grid grid-cols-4 gap-4">
                <div className="space-y-1.5">
                  <Label>Prep Time (min)</Label>
                  <Input type="number" min={0} value={itemForm.prepTime || 0} onChange={e => setItemForm({ ...itemForm, prepTime: parseInt(e.target.value) || 0 })} className="h-10" />
                </div>
                <div className="space-y-1.5">
                  <Label>Calories</Label>
                  <Input type="number" min={0} value={itemForm.calories || ""} onChange={e => setItemForm({ ...itemForm, calories: e.target.value ? parseInt(e.target.value) : null })} className="h-10" placeholder="—" />
                </div>
                <div className="space-y-1.5">
                  <Label>Spicy Level</Label>
                  <div className="flex gap-1 h-10 items-center">
                    {[0, 1, 2, 3, 4, 5].map(l => (
                      <button key={l} type="button" onClick={() => setItemForm({ ...itemForm, spicyLevel: l })}
                        className={`h-8 w-8 rounded-lg text-sm transition-all ${itemForm.spicyLevel === l ? "bg-red-500 text-white shadow-sm" : l === 0 ? "bg-gray-100 text-gray-500" : "bg-gray-100 hover:bg-red-100"}`}>
                        {l === 0 ? "0" : "🌶️"}
                      </button>
                    ))}
                  </div>
                </div>
                <div className="space-y-1.5">
                  <Label>SKU</Label>
                  <Input value={itemForm.sku || ""} onChange={e => setItemForm({ ...itemForm, sku: e.target.value })} className="h-10" placeholder="Optional" />
                </div>
              </div>
              <div className="mt-3 space-y-1.5">
                <Label className="flex items-center gap-1.5"><AlertTriangle className="h-3.5 w-3.5 text-amber-500" /> Allergens</Label>
                <Input value={itemForm.allergens || ""} onChange={e => setItemForm({ ...itemForm, allergens: e.target.value })} placeholder="e.g. Nuts, Dairy, Gluten, Shellfish" className="h-10" />
              </div>
            </div>

            {/* Dietary */}
            <div>
              <h4 className="text-sm font-medium text-gray-500 mb-3 flex items-center gap-1.5"><Leaf className="h-3.5 w-3.5" /> Dietary Options</h4>
              <div className="flex flex-wrap gap-2">
                {DIETARY_OPTIONS.map(d => {
                  const active = (itemForm as any)[d.key] || false
                  return (
                    <button key={d.key} type="button" onClick={() => setItemForm({ ...itemForm, [d.key]: !active })}
                      className={`flex items-center gap-1.5 px-3 py-2 rounded-lg border-2 text-sm font-medium transition-all ${
                        active ? d.color + " border-current shadow-sm" : "border-gray-200 text-gray-500 hover:border-gray-300"
                      }`}>
                      <span>{d.emoji}</span> {d.label}
                    </button>
                  )
                })}
              </div>
            </div>
            {/* Recipe / Ingredients */}
            {itemEditing && (
              <div>
                <h4 className="text-sm font-medium text-gray-500 mb-3 flex items-center gap-1.5">
                  <Package className="h-3.5 w-3.5" /> Recipe / Ingredients
                  <span className="text-xs text-muted-foreground ml-auto">
                    Cost: {itemRecipe.reduce((s, r) => s + (r.lineCost || r.quantity * r.costPerUnit), 0).toFixed(2)}
                  </span>
                </h4>
                {itemRecipe.length > 0 && (
                  <table className="w-full text-xs mb-3">
                    <thead className="bg-gray-50 border-b"><tr><th className="text-left p-2">Ingredient</th><th className="text-right p-2">Qty</th><th className="text-left p-2">Unit</th><th className="text-right p-2">Waste %</th><th className="text-right p-2">Cost</th><th className="p-2"></th></tr></thead>
                    <tbody>
                      {itemRecipe.map(r => (
                        <tr key={r.recipeId} className="border-b">
                          <td className="p-2 font-medium">{r.ingredientName}</td>
                          <td className="p-2 text-right">{r.quantity}</td>
                          <td className="p-2">{r.unit}</td>
                          <td className="p-2 text-right">{r.wastePercent}%</td>
                          <td className="p-2 text-right font-semibold">{(r.lineCost || r.quantity * r.costPerUnit).toFixed(2)}</td>
                          <td className="p-2"><Button variant="ghost" size="icon" className="h-6 w-6 text-red-500" onClick={async () => { await deleteRecipe(r.recipeId); setItemRecipe(await listRecipe(itemEditing.menuItemId)) }}><Trash2 className="h-3 w-3" /></Button></td>
                        </tr>
                      ))}
                    </tbody>
                  </table>
                )}
                <div className="flex gap-2 items-end flex-wrap">
                  <div className="flex-1 min-w-[140px]">
                    <Label className="text-xs">Ingredient</Label>
                    <Select value={recipeAddIng ? String(recipeAddIng) : "0"} onValueChange={v => {
                      setRecipeAddIng(Number(v))
                      const ing = allIngredients.find(i => i.ingredientId === Number(v))
                      if (ing) setRecipeAddUnit(ing.unit)
                    }}>
                      <SelectTrigger className="h-9"><SelectValue placeholder="Select" /></SelectTrigger>
                      <SelectContent>
                        <SelectItem value="0">Select ingredient</SelectItem>
                        {allIngredients.filter(i => !itemRecipe.find(r => r.ingredientId === i.ingredientId)).map(i => (
                          <SelectItem key={i.ingredientId} value={String(i.ingredientId)}>{i.name} ({i.unit})</SelectItem>
                        ))}
                      </SelectContent>
                    </Select>
                  </div>
                  <div className="w-20"><Label className="text-xs">Qty</Label><Input type="number" step="0.01" className="h-9" value={recipeAddQty} onChange={e => setRecipeAddQty(Number(e.target.value))} /></div>
                  <div className="w-20"><Label className="text-xs">Unit</Label><Input className="h-9" value={recipeAddUnit} onChange={e => setRecipeAddUnit(e.target.value)} /></div>
                  <div className="w-20"><Label className="text-xs">Waste %</Label><Input type="number" className="h-9" value={recipeAddWaste} onChange={e => setRecipeAddWaste(Number(e.target.value))} /></div>
                  <Button size="sm" className="h-9 bg-rose-600 hover:bg-rose-700" disabled={!recipeAddIng} onClick={async () => {
                    await upsertRecipe(itemEditing.menuItemId, recipeAddIng, recipeAddQty, recipeAddUnit, recipeAddWaste)
                    setItemRecipe(await listRecipe(itemEditing.menuItemId))
                    setRecipeAddIng(0); setRecipeAddQty(1); setRecipeAddWaste(0)
                    toast({ title: "Ingredient added to recipe" })
                  }}><Plus className="h-4 w-4" /></Button>
                </div>
                {itemRecipe.length === 0 && <p className="text-xs text-muted-foreground mt-2">No ingredients defined. Add ingredients to auto-deduct stock when orders are completed.</p>}
              </div>
            )}
            {!itemEditing && (
              <div className="bg-gray-50 rounded-lg p-3 text-xs text-muted-foreground">
                <Package className="h-4 w-4 inline mr-1" /> Save the item first, then edit it to define the recipe/ingredients.
              </div>
            )}
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setItemDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveItem} className="bg-rose-600 hover:bg-rose-700">{itemEditing ? "Update Item" : "Add Item"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Combo Dialog */}
      <Dialog open={comboDialogOpen} onOpenChange={setComboDialogOpen}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>{comboEditing ? "Edit Combo" : "Add Combo / Meal Deal"}</DialogTitle>
            <DialogDescription>Bundle items together at a special price</DialogDescription>
          </DialogHeader>
          <div className="space-y-4">
            <div className="space-y-1.5">
              <Label>Combo Name <span className="text-rose-500">*</span></Label>
              <Input value={comboForm.name} onChange={e => setComboForm({ ...comboForm, name: e.target.value })} placeholder="e.g. Family Meal Deal" className="h-10" />
            </div>
            <div className="space-y-1.5">
              <Label>Combo Price</Label>
              <div className="relative"><DollarSign className="absolute left-3 top-1/2 -translate-y-1/2 h-4 w-4 text-muted-foreground" />
              <Input type="number" step="0.01" value={comboForm.price} onChange={e => setComboForm({ ...comboForm, price: parseFloat(e.target.value) || 0 })} className="h-10 pl-9" /></div>
            </div>
            <div className="space-y-1.5">
              <Label>Description</Label>
              <Input value={comboForm.description || ""} onChange={e => setComboForm({ ...comboForm, description: e.target.value })} placeholder="What's included in this deal?" className="h-10" />
            </div>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setComboDialogOpen(false)}>Cancel</Button>
            <Button onClick={saveCombo} className="bg-rose-600 hover:bg-rose-700">{comboEditing ? "Update" : "Create Combo"}</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>

      {/* Add Combo Item Dialog */}
      <Dialog open={addComboItemDialog !== null} onOpenChange={() => setAddComboItemDialog(null)}>
        <DialogContent className="sm:max-w-md">
          <DialogHeader>
            <DialogTitle>Add Item to Combo</DialogTitle>
            <DialogDescription>Select a menu item to include in this combo</DialogDescription>
          </DialogHeader>
          <div className="space-y-1.5">
            <Label>Menu Item</Label>
            <Select value={String(addComboItemId)} onValueChange={v => setAddComboItemId(parseInt(v))}>
              <SelectTrigger className="h-10"><SelectValue /></SelectTrigger>
              <SelectContent>{items.map(i => <SelectItem key={i.menuItemId} value={String(i.menuItemId)}>{i.name} — {i.price.toFixed(2)}</SelectItem>)}</SelectContent>
            </Select>
          </div>
          <DialogFooter>
            <Button variant="outline" onClick={() => setAddComboItemDialog(null)}>Cancel</Button>
            <Button onClick={() => addComboItemDialog && handleAddComboItem(addComboItemDialog)} className="bg-rose-600 hover:bg-rose-700">Add to Combo</Button>
          </DialogFooter>
        </DialogContent>
      </Dialog>
    </div>
  )
}

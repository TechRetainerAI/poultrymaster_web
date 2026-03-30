"use client"

import { useEffect, useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Card, CardContent, CardHeader, CardTitle } from "@/components/ui/card"
import { Button } from "@/components/ui/button"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle } from "@/components/ui/dialog"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Home, Plus, Pencil, Trash2, Loader2 } from "lucide-react"
import { getHouses, createHouse, updateHouse, deleteHouse } from "@/lib/api/house"
import { getUserContext } from "@/lib/utils/user-context"
import { useToast } from "@/hooks/use-toast"

export default function HousesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [houses, setHouses] = useState<any[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState("")
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deletingHouse, setDeletingHouse] = useState<any | null>(null)
  const [isDeleting, setIsDeleting] = useState(false)

  const [dialogOpen, setDialogOpen] = useState(false)
  const [editing, setEditing] = useState<any | null>(null)
  const [name, setName] = useState("")
  const [capacity, setCapacity] = useState<string>("")
  const [location, setLocation] = useState<string>("")
  const [saving, setSaving] = useState(false)

  const handleLogout = () => {
    localStorage.removeItem("auth_token")
    localStorage.removeItem("refresh_token")
    router.push("/login")
  }

  const load = async () => {
    try {
      setLoading(true)
      setError("")
      const { userId, farmId } = getUserContext()
      if (!userId) throw new Error("User not found")
      if (!farmId) throw new Error("Farm not selected")
      const res = await getHouses(userId, farmId)
      if (res.success && res.data) setHouses(res.data as any[])
      else setError(res.message || "Failed to load houses")
    } catch (e: any) {
      setError(e?.message || "Failed to load houses")
    } finally {
      setLoading(false)
    }
  }

  useEffect(() => { load() }, [])

  const openCreate = () => {
    setEditing(null)
    setName("")
    setCapacity("")
    setLocation("")
    setDialogOpen(true)
  }

  const openEdit = (h: any) => {
    setEditing(h)
    setName(h.name || h.houseName || "")
    setCapacity(h.capacity != null ? String(h.capacity) : "")
    setLocation(h.location || "")
    setDialogOpen(true)
  }

  const submit = async () => {
    try {
      setSaving(true)
      if (!name.trim()) {
        toast({ title: "Required fields missing", description: "House name is required before saving.", variant: "destructive" })
        setSaving(false)
        return
      }
      const { userId, farmId } = getUserContext()
      if (!userId) throw new Error("User not found")
      if (!farmId) throw new Error("Farm not selected")
      const payload = { userId, farmId, name, capacity: capacity ? parseInt(capacity) : null, location: location || null }
      const res = editing ? await updateHouse(editing.houseId, payload) : await createHouse(payload)
      if (!res.success) throw new Error(res.message || "Request failed")
      setDialogOpen(false)
      await load()
    } catch (e: any) {
      setError(e?.message || "Save failed")
    } finally {
      setSaving(false)
    }
  }

  const openDeleteDialog = (h: any) => {
    setDeletingHouse(h)
    setDeleteDialogOpen(true)
  }

  const remove = async () => {
    if (!deletingHouse) return
    const { userId, farmId } = getUserContext()
    if (!userId || !farmId) {
      toast({ title: "Error", description: "Missing user/farm context. Please log in again.", variant: "destructive" })
      return
    }
    setIsDeleting(true)
    const res = await deleteHouse(deletingHouse.houseId, userId, farmId)
    if (res.success) {
      toast({ title: "House deleted", description: `"${deletingHouse.houseName ?? deletingHouse.name}" has been successfully deleted.` })
      await load()
    } else {
      toast({ title: "Delete failed", description: res.message || "Something went wrong. Please try again.", variant: "destructive" })
    }
    setIsDeleting(false)
    setDeleteDialogOpen(false)
    setDeletingHouse(null)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 bg-blue-100 rounded-lg flex items-center justify-center">
                  <Home className="w-5 h-5 text-blue-600" />
                </div>
                <div>
                  <h1 className="text-2xl font-bold text-slate-900">Houses</h1>
                  <p className="text-slate-600">Manage poultry houses</p>
                </div>
              </div>
              <Button onClick={openCreate} className="flex items-center gap-2">
                <Plus className="w-4 h-4" />
                Add House
              </Button>
            </div>

            {error && (
              <div className="p-4 bg-red-50 border border-red-200 rounded-lg text-red-700">{error}</div>
            )}

            {loading ? (
              <div className="text-center py-12 text-slate-600">Loading houses...</div>
            ) : houses.length === 0 ? (
              <Card>
                <CardContent className="text-center py-12">
                  <Home className="h-12 w-12 text-slate-400 mx-auto mb-3" />
                  <p className="text-slate-600">No houses yet.</p>
                </CardContent>
              </Card>
            ) : (
              <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
                {houses.map((h) => (
                  <Card key={h.houseId} className="hover:shadow-md transition-shadow">
                    <CardHeader className="pb-3">
                      <div className="flex justify-between items-start">
                        <div className="flex items-center gap-2">
                          <Home className="h-5 w-5 text-blue-600" />
                          <CardTitle className="text-lg">{h.name || h.houseName}</CardTitle>
                        </div>
                        <div className="flex gap-1">
                          <Button size="icon" variant="ghost" onClick={() => openEdit(h)} className="h-8 w-8">
                            <Pencil className="h-4 w-4" />
                          </Button>
                          <Button size="icon" variant="ghost" onClick={() => openDeleteDialog(h)} className="h-8 w-8 text-red-600">
                            <Trash2 className="h-4 w-4" />
                          </Button>
                        </div>
                      </div>
                    </CardHeader>
                    <CardContent className="space-y-2 text-sm">
                      <div className="flex justify-between">
                        <span className="text-slate-600">Capacity:</span>
                        <span className="font-medium">{h.capacity ?? "Not set"}</span>
                      </div>
                      {h.location ? (
                        <div className="flex justify-between">
                          <span className="text-slate-600">Location:</span>
                          <span className="font-medium">{h.location}</span>
                        </div>
                      ) : null}
                    </CardContent>
                  </Card>
                ))}
              </div>
            )}
          </div>
        </main>
      </div>

      <Dialog open={dialogOpen} onOpenChange={setDialogOpen}>
        <DialogContent className="max-w-4xl w-[95vw] sm:max-w-[900px] max-h-[90vh] flex flex-col">
          <DialogHeader>
            <DialogTitle>{editing ? "Edit House" : "Create New House"}</DialogTitle>
            <DialogDescription>
              {editing ? "Update the house information below." : "Add a new poultry house to your farm records."}
            </DialogDescription>
          </DialogHeader>

          <div className="space-y-5 py-4 overflow-y-auto pr-1">
            <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
              <div className="bg-blue-600 px-4 py-2 text-sm font-semibold text-white">House Details</div>
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 p-4">
                <div className="space-y-2">
                  <Label htmlFor="name">House Name *</Label>
                  <Input
                    id="name"
                    value={name}
                    onChange={(e) => setName(e.target.value)}
                    required
                    placeholder="House A"
                  />
                </div>
                <div className="space-y-2">
                  <Label htmlFor="capacity">Capacity (birds)</Label>
                  <Input
                    id="capacity"
                    type="number"
                    min="0"
                    value={capacity}
                    onChange={(e) => setCapacity(e.target.value)}
                    placeholder="1000"
                  />
                </div>
              </div>
            </div>

            <div className="rounded-xl border border-slate-200 overflow-hidden bg-slate-50">
              <div className="bg-indigo-600 px-4 py-2 text-sm font-semibold text-white">Additional Information</div>
              <div className="grid grid-cols-1 gap-4 p-4">
                <div className="space-y-2">
                  <Label htmlFor="location">Location</Label>
                  <Input
                    id="location"
                    value={location}
                    onChange={(e) => setLocation(e.target.value)}
                    placeholder="North Wing"
                  />
                </div>
              </div>
            </div>
          </div>

          <div className="flex justify-end space-x-2 pt-2 border-t">
            <Button onClick={() => setDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
              Cancel
            </Button>
            <Button onClick={submit} disabled={saving} className="bg-blue-600 hover:bg-blue-700">
              {saving ? (
                <span className="flex items-center gap-2">
                  <span className="w-4 h-4 border-2 border-white border-t-transparent rounded-full animate-spin"></span>
                  Saving...
                </span>
              ) : editing ? (
                "Update House"
              ) : (
                "Create House"
              )}
            </Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete House</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deletingHouse?.houseName ?? deletingHouse?.name}&quot;? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel disabled={isDeleting}>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={remove} disabled={isDeleting} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              {isDeleting ? <><Loader2 className="w-4 h-4 mr-2 animate-spin" />Deleting...</> : "Delete"}
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

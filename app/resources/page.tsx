"use client"

import { useState } from "react"
import { useRouter } from "next/navigation"
import { DashboardSidebar } from "@/components/dashboard/sidebar"
import { DashboardHeader } from "@/components/dashboard/header"
import { Button } from "@/components/ui/button"
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from "@/components/ui/card"
import { Tabs, TabsContent, TabsList, TabsTrigger } from "@/components/ui/tabs"
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from "@/components/ui/table"
import { Dialog, DialogContent, DialogDescription, DialogHeader, DialogTitle, DialogTrigger } from "@/components/ui/dialog"
import { Input } from "@/components/ui/input"
import { Label } from "@/components/ui/label"
import { Textarea } from "@/components/ui/textarea"
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from "@/components/ui/select"
import { Badge } from "@/components/ui/badge"
import { AlertDialog, AlertDialogAction, AlertDialogCancel, AlertDialogContent, AlertDialogDescription, AlertDialogFooter, AlertDialogHeader, AlertDialogTitle } from "@/components/ui/alert-dialog"
import { Plus, Edit, Trash2, BookOpen, Calendar, Pill, UtensilsCrossed } from "lucide-react"
import { SortableHeader, type SortDirection, toggleSort, sortData } from "@/components/ui/sortable-header"
import { useToast } from "@/hooks/use-toast"

interface VaccinationSchedule {
  id?: number
  vaccineName: string
  ageInWeeks: number
  ageInDays: number
  dosage: string
  route: string
  notes?: string
}

interface MedicationSchedule {
  id?: number
  medicationName: string
  ageInWeeks: number
  ageInDays: number
  dosage: string
  frequency: string
  duration: string
  notes?: string
}

interface FeedFormulation {
  id?: number
  feedName: string
  ageRange: string
  protein: number
  energy: number
  ingredients: string
  notes?: string
}

export default function ResourcesPage() {
  const router = useRouter()
  const { toast } = useToast()
  const [activeTab, setActiveTab] = useState("vaccination")
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false)
  const [deleteTarget, setDeleteTarget] = useState<{ id: number; type: "vaccination" | "medication" | "feed"; name: string } | null>(null)

  // Vaccination schedules
  const [vaccinationSchedules, setVaccinationSchedules] = useState<VaccinationSchedule[]>([
    {
      id: 1,
      vaccineName: "Newcastle Disease",
      ageInWeeks: 0,
      ageInDays: 1,
      dosage: "0.2ml",
      route: "Eye drop",
      notes: "First vaccination"
    },
    {
      id: 2,
      vaccineName: "Infectious Bursal Disease",
      ageInWeeks: 2,
      ageInDays: 14,
      dosage: "0.2ml",
      route: "Drinking water",
      notes: "Second vaccination"
    }
  ])

  // Medication schedules
  const [medicationSchedules, setMedicationSchedules] = useState<MedicationSchedule[]>([
    {
      id: 1,
      medicationName: "Vitamin Supplement",
      ageInWeeks: 0,
      ageInDays: 1,
      dosage: "1ml per liter",
      frequency: "Daily",
      duration: "First week",
      notes: "Boost immunity"
    }
  ])

  // Feed formulations
  const [feedFormulations, setFeedFormulations] = useState<FeedFormulation[]>([
    {
      id: 1,
      feedName: "Starter Feed",
      ageRange: "0-4 weeks",
      protein: 20,
      energy: 3000,
      ingredients: "Corn, Soybean meal, Fish meal, Vitamins",
      notes: "For day-old to 4 weeks"
    },
    {
      id: 2,
      feedName: "Grower Feed",
      ageRange: "4-16 weeks",
      protein: 18,
      energy: 2900,
      ingredients: "Corn, Soybean meal, Wheat, Vitamins",
      notes: "For growing birds"
    }
  ])

  const [isVaccinationDialogOpen, setIsVaccinationDialogOpen] = useState(false)
  const [isMedicationDialogOpen, setIsMedicationDialogOpen] = useState(false)
  const [isFeedDialogOpen, setIsFeedDialogOpen] = useState(false)
  const [isVaccinationEditDialogOpen, setIsVaccinationEditDialogOpen] = useState(false)
  const [isMedicationEditDialogOpen, setIsMedicationEditDialogOpen] = useState(false)
  const [isFeedEditDialogOpen, setIsFeedEditDialogOpen] = useState(false)
  const [editingVaccinationId, setEditingVaccinationId] = useState<number | null>(null)
  const [editingMedicationId, setEditingMedicationId] = useState<number | null>(null)
  const [editingFeedId, setEditingFeedId] = useState<number | null>(null)
  const [sortKey, setSortKey] = useState<string | null>(null)
  const [sortDir, setSortDir] = useState<SortDirection>(null)
  const handleSort = (key: string) => { const r = toggleSort(key, sortKey, sortDir); setSortKey(r.key); setSortDir(r.direction) }

  const [vaccinationForm, setVaccinationForm] = useState<Omit<VaccinationSchedule, 'id'>>({
    vaccineName: "",
    ageInWeeks: 0,
    ageInDays: 0,
    dosage: "",
    route: "",
    notes: "",
  })

  const [medicationForm, setMedicationForm] = useState<Omit<MedicationSchedule, 'id'>>({
    medicationName: "",
    ageInWeeks: 0,
    ageInDays: 0,
    dosage: "",
    frequency: "",
    duration: "",
    notes: "",
  })

  const [feedForm, setFeedForm] = useState<Omit<FeedFormulation, 'id'>>({
    feedName: "",
    ageRange: "",
    protein: 0,
    energy: 0,
    ingredients: "",
    notes: "",
  })
  const [editVaccinationForm, setEditVaccinationForm] = useState<Omit<VaccinationSchedule, 'id'>>({
    vaccineName: "",
    ageInWeeks: 0,
    ageInDays: 0,
    dosage: "",
    route: "",
    notes: "",
  })
  const [editMedicationForm, setEditMedicationForm] = useState<Omit<MedicationSchedule, 'id'>>({
    medicationName: "",
    ageInWeeks: 0,
    ageInDays: 0,
    dosage: "",
    frequency: "",
    duration: "",
    notes: "",
  })
  const [editFeedForm, setEditFeedForm] = useState<Omit<FeedFormulation, 'id'>>({
    feedName: "",
    ageRange: "",
    protein: 0,
    energy: 0,
    ingredients: "",
    notes: "",
  })

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

  const handleAddVaccination = () => {
    const newSchedule: VaccinationSchedule = {
      ...vaccinationForm,
      id: Date.now(),
    }
    setVaccinationSchedules([...vaccinationSchedules, newSchedule])
    setIsVaccinationDialogOpen(false)
    setVaccinationForm({
      vaccineName: "",
      ageInWeeks: 0,
      ageInDays: 0,
      dosage: "",
      route: "",
      notes: "",
    })
  }

  const handleAddMedication = () => {
    const newSchedule: MedicationSchedule = {
      ...medicationForm,
      id: Date.now(),
    }
    setMedicationSchedules([...medicationSchedules, newSchedule])
    setIsMedicationDialogOpen(false)
    setMedicationForm({
      medicationName: "",
      ageInWeeks: 0,
      ageInDays: 0,
      dosage: "",
      frequency: "",
      duration: "",
      notes: "",
    })
  }

  const handleAddFeed = () => {
    const newFormulation: FeedFormulation = {
      ...feedForm,
      id: Date.now(),
    }
    setFeedFormulations([...feedFormulations, newFormulation])
    setIsFeedDialogOpen(false)
    setFeedForm({
      feedName: "",
      ageRange: "",
      protein: 0,
      energy: 0,
      ingredients: "",
      notes: "",
    })
  }

  const openVaccinationEditDialog = (schedule: VaccinationSchedule) => {
    setEditingVaccinationId(schedule.id ?? null)
    setEditVaccinationForm({
      vaccineName: schedule.vaccineName,
      ageInWeeks: schedule.ageInWeeks,
      ageInDays: schedule.ageInDays,
      dosage: schedule.dosage,
      route: schedule.route,
      notes: schedule.notes ?? "",
    })
    setIsVaccinationEditDialogOpen(true)
  }

  const openMedicationEditDialog = (schedule: MedicationSchedule) => {
    setEditingMedicationId(schedule.id ?? null)
    setEditMedicationForm({
      medicationName: schedule.medicationName,
      ageInWeeks: schedule.ageInWeeks,
      ageInDays: schedule.ageInDays,
      dosage: schedule.dosage,
      frequency: schedule.frequency,
      duration: schedule.duration,
      notes: schedule.notes ?? "",
    })
    setIsMedicationEditDialogOpen(true)
  }

  const openFeedEditDialog = (formulation: FeedFormulation) => {
    setEditingFeedId(formulation.id ?? null)
    setEditFeedForm({
      feedName: formulation.feedName,
      ageRange: formulation.ageRange,
      protein: formulation.protein,
      energy: formulation.energy,
      ingredients: formulation.ingredients,
      notes: formulation.notes ?? "",
    })
    setIsFeedEditDialogOpen(true)
  }

  const handleUpdateVaccination = () => {
    if (editingVaccinationId == null) return
    setVaccinationSchedules((prev) =>
      prev.map((item) => (item.id === editingVaccinationId ? { ...editVaccinationForm, id: editingVaccinationId } : item))
    )
    setIsVaccinationEditDialogOpen(false)
    setEditingVaccinationId(null)
    toast({ title: "Schedule updated", description: "Vaccination schedule updated successfully." })
  }

  const handleUpdateMedication = () => {
    if (editingMedicationId == null) return
    setMedicationSchedules((prev) =>
      prev.map((item) => (item.id === editingMedicationId ? { ...editMedicationForm, id: editingMedicationId } : item))
    )
    setIsMedicationEditDialogOpen(false)
    setEditingMedicationId(null)
    toast({ title: "Schedule updated", description: "Medication schedule updated successfully." })
  }

  const handleUpdateFeed = () => {
    if (editingFeedId == null) return
    setFeedFormulations((prev) =>
      prev.map((item) => (item.id === editingFeedId ? { ...editFeedForm, id: editingFeedId } : item))
    )
    setIsFeedEditDialogOpen(false)
    setEditingFeedId(null)
    toast({ title: "Formulation updated", description: "Feed formulation updated successfully." })
  }

  const openDeleteDialog = (id: number, type: "vaccination" | "medication" | "feed", name: string) => {
    setDeleteTarget({ id, type, name })
    setDeleteDialogOpen(true)
  }

  const handleConfirmDelete = () => {
    if (!deleteTarget) return
    const { id, type } = deleteTarget
    if (type === "vaccination") {
      setVaccinationSchedules(vaccinationSchedules.filter(v => v.id !== id))
      toast({ title: "Schedule deleted", description: "The vaccination schedule has been removed." })
    } else if (type === "medication") {
      setMedicationSchedules(medicationSchedules.filter(m => m.id !== id))
      toast({ title: "Schedule deleted", description: "The medication schedule has been removed." })
    } else if (type === "feed") {
      setFeedFormulations(feedFormulations.filter(f => f.id !== id))
      toast({ title: "Formulation deleted", description: "The feed formulation has been removed." })
    }
    setDeleteDialogOpen(false)
    setDeleteTarget(null)
  }

  return (
    <div className="flex min-h-screen bg-slate-50">
      <DashboardSidebar onLogout={handleLogout} />
      <div className="flex-1 flex flex-col">
        <DashboardHeader />
        <main className="overflow-y-visible overflow-x-hidden p-4 sm:p-6 pb-16 lg:pb-4 min-w-0">
          <div className="space-y-6">
            {/* Page Header */}
            <div className="flex items-center gap-3 mb-6">
              <div className="w-10 h-10 bg-green-100 rounded-lg flex items-center justify-center">
                <BookOpen className="w-5 h-5 text-green-600" />
              </div>
              <div>
                <h1 className="text-2xl font-bold text-slate-900">Resources & Information Center</h1>
                <p className="text-slate-600">Access vaccination schedules, medication guides, and feed formulations</p>
              </div>
            </div>

            <Tabs value={activeTab} onValueChange={setActiveTab} className="w-full">
              <TabsList className="grid w-full grid-cols-3">
                <TabsTrigger value="vaccination">
                  <Calendar className="w-4 h-4 mr-2" />
                  Vaccination Schedules
                </TabsTrigger>
                <TabsTrigger value="medication">
                  <Pill className="w-4 h-4 mr-2" />
                  Medication Schedules
                </TabsTrigger>
                <TabsTrigger value="feed">
                  <UtensilsCrossed className="w-4 h-4 mr-2" />
                  Feed Formulations
                </TabsTrigger>
              </TabsList>

              {/* Vaccination Schedules Tab */}
              <TabsContent value="vaccination" className="space-y-4">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div>
                        <CardTitle>Vaccination Schedules</CardTitle>
                        <CardDescription>Track vaccination schedules for your flocks</CardDescription>
                      </div>
                      <Dialog
                        open={isVaccinationDialogOpen}
                        onOpenChange={setIsVaccinationDialogOpen}
                      >
                        <DialogTrigger asChild>
                          <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                            <Plus className="w-4 h-4" />
                            Add Schedule
                          </Button>
                        </DialogTrigger>
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>Add Vaccination Schedule</DialogTitle>
                            <DialogDescription>
                              Create a new vaccination schedule entry
                            </DialogDescription>
                          </DialogHeader>
                          <div className="grid gap-4 py-4">
                            <div className="space-y-2">
                              <Label htmlFor="vaccineName">Vaccine Name *</Label>
                              <Input
                                id="vaccineName"
                                value={vaccinationForm.vaccineName}
                                onChange={(e) => setVaccinationForm(prev => ({ ...prev, vaccineName: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-2">
                                <Label htmlFor="ageInWeeks">Age (Weeks)</Label>
                                <Input
                                  id="ageInWeeks"
                                  type="number"
                                  min="0"
                                  value={vaccinationForm.ageInWeeks}
                                  onChange={(e) => setVaccinationForm(prev => ({ ...prev, ageInWeeks: parseInt(e.target.value) || 0 }))}
                                />
                              </div>
                              <div className="space-y-2">
                                <Label htmlFor="ageInDays">Age (Days)</Label>
                                <Input
                                  id="ageInDays"
                                  type="number"
                                  min="0"
                                  value={vaccinationForm.ageInDays}
                                  onChange={(e) => setVaccinationForm(prev => ({ ...prev, ageInDays: parseInt(e.target.value) || 0 }))}
                                />
                              </div>
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-2">
                                <Label htmlFor="dosage">Dosage *</Label>
                                <Input
                                  id="dosage"
                                  value={vaccinationForm.dosage}
                                  onChange={(e) => setVaccinationForm(prev => ({ ...prev, dosage: e.target.value }))}
                                  required
                                />
                              </div>
                              <div className="space-y-2">
                                <Label htmlFor="route">Route *</Label>
                                <Input
                                  id="route"
                                  value={vaccinationForm.route}
                                  onChange={(e) => setVaccinationForm(prev => ({ ...prev, route: e.target.value }))}
                                  required
                                />
                              </div>
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="notes">Notes</Label>
                              <Textarea
                                id="notes"
                                value={vaccinationForm.notes}
                                onChange={(e) => setVaccinationForm(prev => ({ ...prev, notes: e.target.value }))}
                              />
                            </div>
                          </div>
                          <div className="flex justify-end space-x-2">
                            <Button onClick={() => setIsVaccinationDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                              Cancel
                            </Button>
                            <Button onClick={handleAddVaccination}>Add Schedule</Button>
                          </div>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <SortableHeader label="Vaccine Name" sortKey="vaccineName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Age" sortKey="ageInDays" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Dosage" sortKey="dosage" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Route" sortKey="route" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <TableHead>Notes</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {sortData(vaccinationSchedules, sortKey, sortDir).map((schedule) => (
                          <TableRow key={schedule.id}>
                            <TableCell className="font-medium">{schedule.vaccineName}</TableCell>
                            <TableCell>
                              {schedule.ageInWeeks > 0 && `${schedule.ageInWeeks} weeks`}
                              {schedule.ageInWeeks > 0 && schedule.ageInDays > 0 && ", "}
                              {schedule.ageInDays > 0 && `${schedule.ageInDays} days`}
                            </TableCell>
                            <TableCell>{schedule.dosage}</TableCell>
                            <TableCell>
                              <Badge variant="outline">{schedule.route}</Badge>
                            </TableCell>
                            <TableCell>{schedule.notes || "-"}</TableCell>
                            <TableCell className="text-right">
                              <div className="flex items-center justify-end gap-1">
                                <Button variant="ghost" size="sm" onClick={() => openVaccinationEditDialog(schedule)}>
                                  <Edit className="h-4 w-4" />
                                </Button>
                                <Button variant="ghost" size="sm" className="text-red-600" onClick={() => openDeleteDialog(schedule.id!, "vaccination", schedule.vaccineName)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Medication Schedules Tab */}
              <TabsContent value="medication" className="space-y-4">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div>
                        <CardTitle>Medication Schedules</CardTitle>
                        <CardDescription>Track medication schedules for your flocks</CardDescription>
                      </div>
                      <Dialog
                        open={isMedicationDialogOpen}
                        onOpenChange={setIsMedicationDialogOpen}
                      >
                        <DialogTrigger asChild>
                          <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                            <Plus className="w-4 h-4" />
                            Add Schedule
                          </Button>
                        </DialogTrigger>
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>Add Medication Schedule</DialogTitle>
                            <DialogDescription>
                              Create a new medication schedule entry
                            </DialogDescription>
                          </DialogHeader>
                          <div className="grid gap-4 py-4">
                            <div className="space-y-2">
                              <Label htmlFor="medicationName">Medication Name *</Label>
                              <Input
                                id="medicationName"
                                value={medicationForm.medicationName}
                                onChange={(e) => setMedicationForm(prev => ({ ...prev, medicationName: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-2">
                                <Label htmlFor="medAgeInWeeks">Age (Weeks)</Label>
                                <Input
                                  id="medAgeInWeeks"
                                  type="number"
                                  min="0"
                                  value={medicationForm.ageInWeeks}
                                  onChange={(e) => setMedicationForm(prev => ({ ...prev, ageInWeeks: parseInt(e.target.value) || 0 }))}
                                />
                              </div>
                              <div className="space-y-2">
                                <Label htmlFor="medAgeInDays">Age (Days)</Label>
                                <Input
                                  id="medAgeInDays"
                                  type="number"
                                  min="0"
                                  value={medicationForm.ageInDays}
                                  onChange={(e) => setMedicationForm(prev => ({ ...prev, ageInDays: parseInt(e.target.value) || 0 }))}
                                />
                              </div>
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="medDosage">Dosage *</Label>
                              <Input
                                id="medDosage"
                                value={medicationForm.dosage}
                                onChange={(e) => setMedicationForm(prev => ({ ...prev, dosage: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-2">
                                <Label htmlFor="frequency">Frequency *</Label>
                                <Input
                                  id="frequency"
                                  value={medicationForm.frequency}
                                  onChange={(e) => setMedicationForm(prev => ({ ...prev, frequency: e.target.value }))}
                                  required
                                />
                              </div>
                              <div className="space-y-2">
                                <Label htmlFor="duration">Duration *</Label>
                                <Input
                                  id="duration"
                                  value={medicationForm.duration}
                                  onChange={(e) => setMedicationForm(prev => ({ ...prev, duration: e.target.value }))}
                                  required
                                />
                              </div>
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="medNotes">Notes</Label>
                              <Textarea
                                id="medNotes"
                                value={medicationForm.notes}
                                onChange={(e) => setMedicationForm(prev => ({ ...prev, notes: e.target.value }))}
                              />
                            </div>
                          </div>
                          <div className="flex justify-end space-x-2">
                            <Button onClick={() => setIsMedicationDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                              Cancel
                            </Button>
                            <Button onClick={handleAddMedication}>Add Schedule</Button>
                          </div>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <SortableHeader label="Medication Name" sortKey="medicationName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Age" sortKey="ageInDays" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Dosage" sortKey="dosage" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Frequency" sortKey="frequency" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Duration" sortKey="duration" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <TableHead>Notes</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {sortData(medicationSchedules, sortKey, sortDir).map((schedule) => (
                          <TableRow key={schedule.id}>
                            <TableCell className="font-medium">{schedule.medicationName}</TableCell>
                            <TableCell>
                              {schedule.ageInWeeks > 0 && `${schedule.ageInWeeks} weeks`}
                              {schedule.ageInWeeks > 0 && schedule.ageInDays > 0 && ", "}
                              {schedule.ageInDays > 0 && `${schedule.ageInDays} days`}
                            </TableCell>
                            <TableCell>{schedule.dosage}</TableCell>
                            <TableCell>{schedule.frequency}</TableCell>
                            <TableCell>{schedule.duration}</TableCell>
                            <TableCell>{schedule.notes || "-"}</TableCell>
                            <TableCell className="text-right">
                              <div className="flex items-center justify-end gap-1">
                                <Button variant="ghost" size="sm" onClick={() => openMedicationEditDialog(schedule)}>
                                  <Edit className="h-4 w-4" />
                                </Button>
                                <Button variant="ghost" size="sm" className="text-red-600" onClick={() => openDeleteDialog(schedule.id!, "medication", schedule.medicationName)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              </TabsContent>

              {/* Feed Formulations Tab */}
              <TabsContent value="feed" className="space-y-4">
                <Card>
                  <CardHeader>
                    <div className="flex items-center justify-between">
                      <div>
                        <CardTitle>Feed Formulations</CardTitle>
                        <CardDescription>Manage feed composition and nutritional information</CardDescription>
                      </div>
                      <Dialog
                        open={isFeedDialogOpen}
                        onOpenChange={setIsFeedDialogOpen}
                      >
                        <DialogTrigger asChild>
                          <Button className="gap-2 bg-blue-600 hover:bg-blue-700">
                            <Plus className="w-4 h-4" />
                            Add Formulation
                          </Button>
                        </DialogTrigger>
                        <DialogContent>
                          <DialogHeader>
                            <DialogTitle>Add Feed Formulation</DialogTitle>
                            <DialogDescription>
                              Create a new feed formulation entry
                            </DialogDescription>
                          </DialogHeader>
                          <div className="grid gap-4 py-4">
                            <div className="space-y-2">
                              <Label htmlFor="feedName">Feed Name *</Label>
                              <Input
                                id="feedName"
                                value={feedForm.feedName}
                                onChange={(e) => setFeedForm(prev => ({ ...prev, feedName: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="ageRange">Age Range *</Label>
                              <Input
                                id="ageRange"
                                placeholder="e.g., 0-4 weeks"
                                value={feedForm.ageRange}
                                onChange={(e) => setFeedForm(prev => ({ ...prev, ageRange: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="grid grid-cols-2 gap-4">
                              <div className="space-y-2">
                                <Label htmlFor="protein">Protein (%)</Label>
                                <Input
                                  id="protein"
                                  type="number"
                                  min="0"
                                  step="0.1"
                                  value={feedForm.protein}
                                  onChange={(e) => setFeedForm(prev => ({ ...prev, protein: parseFloat(e.target.value) || 0 }))}
                                />
                              </div>
                              <div className="space-y-2">
                                <Label htmlFor="energy">Energy (kcal/kg)</Label>
                                <Input
                                  id="energy"
                                  type="number"
                                  min="0"
                                  value={feedForm.energy}
                                  onChange={(e) => setFeedForm(prev => ({ ...prev, energy: parseFloat(e.target.value) || 0 }))}
                                />
                              </div>
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="ingredients">Ingredients *</Label>
                              <Textarea
                                id="ingredients"
                                value={feedForm.ingredients}
                                onChange={(e) => setFeedForm(prev => ({ ...prev, ingredients: e.target.value }))}
                                required
                              />
                            </div>
                            <div className="space-y-2">
                              <Label htmlFor="feedNotes">Notes</Label>
                              <Textarea
                                id="feedNotes"
                                value={feedForm.notes}
                                onChange={(e) => setFeedForm(prev => ({ ...prev, notes: e.target.value }))}
                              />
                            </div>
                          </div>
                          <div className="flex justify-end space-x-2">
                            <Button onClick={() => setIsFeedDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">
                              Cancel
                            </Button>
                            <Button onClick={handleAddFeed}>Add Formulation</Button>
                          </div>
                        </DialogContent>
                      </Dialog>
                    </div>
                  </CardHeader>
                  <CardContent>
                    <Table>
                      <TableHeader>
                        <TableRow>
                          <SortableHeader label="Feed Name" sortKey="feedName" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Age Range" sortKey="ageRange" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Protein (%)" sortKey="protein" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <SortableHeader label="Energy (kcal/kg)" sortKey="energy" currentSort={sortKey} currentDirection={sortDir} onSort={handleSort} />
                          <TableHead>Ingredients</TableHead>
                          <TableHead>Notes</TableHead>
                          <TableHead className="text-right">Actions</TableHead>
                        </TableRow>
                      </TableHeader>
                      <TableBody>
                        {sortData(feedFormulations, sortKey, sortDir).map((formulation) => (
                          <TableRow key={formulation.id}>
                            <TableCell className="font-medium">{formulation.feedName}</TableCell>
                            <TableCell>
                              <Badge variant="outline">{formulation.ageRange}</Badge>
                            </TableCell>
                            <TableCell>{formulation.protein}%</TableCell>
                            <TableCell>{formulation.energy.toLocaleString()}</TableCell>
                            <TableCell className="max-w-xs truncate">{formulation.ingredients}</TableCell>
                            <TableCell>{formulation.notes || "-"}</TableCell>
                            <TableCell className="text-right">
                              <div className="flex items-center justify-end gap-1">
                                <Button variant="ghost" size="sm" onClick={() => openFeedEditDialog(formulation)}>
                                  <Edit className="h-4 w-4" />
                                </Button>
                                <Button variant="ghost" size="sm" className="text-red-600" onClick={() => openDeleteDialog(formulation.id!, "feed", formulation.feedName)}>
                                  <Trash2 className="h-4 w-4" />
                                </Button>
                              </div>
                            </TableCell>
                          </TableRow>
                        ))}
                      </TableBody>
                    </Table>
                  </CardContent>
                </Card>
              </TabsContent>
            </Tabs>
          </div>
        </main>
      </div>

      <Dialog open={isVaccinationEditDialogOpen} onOpenChange={setIsVaccinationEditDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Vaccination Schedule</DialogTitle>
            <DialogDescription>Update this vaccination schedule entry.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="editVaccineName">Vaccine Name *</Label>
              <Input id="editVaccineName" value={editVaccinationForm.vaccineName} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, vaccineName: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="editVaccineWeeks">Age (Weeks)</Label>
                <Input id="editVaccineWeeks" type="number" min="0" value={editVaccinationForm.ageInWeeks} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, ageInWeeks: parseInt(e.target.value) || 0 }))} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="editVaccineDays">Age (Days)</Label>
                <Input id="editVaccineDays" type="number" min="0" value={editVaccinationForm.ageInDays} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, ageInDays: parseInt(e.target.value) || 0 }))} />
              </div>
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="editVaccineDosage">Dosage *</Label>
                <Input id="editVaccineDosage" value={editVaccinationForm.dosage} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, dosage: e.target.value }))} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="editVaccineRoute">Route *</Label>
                <Input id="editVaccineRoute" value={editVaccinationForm.route} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, route: e.target.value }))} />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="editVaccineNotes">Notes</Label>
              <Textarea id="editVaccineNotes" value={editVaccinationForm.notes} onChange={(e) => setEditVaccinationForm((prev) => ({ ...prev, notes: e.target.value }))} />
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setIsVaccinationEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={handleUpdateVaccination}>Save Changes</Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={isMedicationEditDialogOpen} onOpenChange={setIsMedicationEditDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Medication Schedule</DialogTitle>
            <DialogDescription>Update this medication schedule entry.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="editMedicationName">Medication Name *</Label>
              <Input id="editMedicationName" value={editMedicationForm.medicationName} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, medicationName: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="editMedicationWeeks">Age (Weeks)</Label>
                <Input id="editMedicationWeeks" type="number" min="0" value={editMedicationForm.ageInWeeks} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, ageInWeeks: parseInt(e.target.value) || 0 }))} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="editMedicationDays">Age (Days)</Label>
                <Input id="editMedicationDays" type="number" min="0" value={editMedicationForm.ageInDays} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, ageInDays: parseInt(e.target.value) || 0 }))} />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="editMedicationDosage">Dosage *</Label>
              <Input id="editMedicationDosage" value={editMedicationForm.dosage} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, dosage: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="editMedicationFrequency">Frequency *</Label>
                <Input id="editMedicationFrequency" value={editMedicationForm.frequency} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, frequency: e.target.value }))} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="editMedicationDuration">Duration *</Label>
                <Input id="editMedicationDuration" value={editMedicationForm.duration} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, duration: e.target.value }))} />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="editMedicationNotes">Notes</Label>
              <Textarea id="editMedicationNotes" value={editMedicationForm.notes} onChange={(e) => setEditMedicationForm((prev) => ({ ...prev, notes: e.target.value }))} />
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setIsMedicationEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={handleUpdateMedication}>Save Changes</Button>
          </div>
        </DialogContent>
      </Dialog>

      <Dialog open={isFeedEditDialogOpen} onOpenChange={setIsFeedEditDialogOpen}>
        <DialogContent>
          <DialogHeader>
            <DialogTitle>Edit Feed Formulation</DialogTitle>
            <DialogDescription>Update this feed formulation entry.</DialogDescription>
          </DialogHeader>
          <div className="grid gap-4 py-4">
            <div className="space-y-2">
              <Label htmlFor="editFeedName">Feed Name *</Label>
              <Input id="editFeedName" value={editFeedForm.feedName} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, feedName: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="editFeedAgeRange">Age Range *</Label>
              <Input id="editFeedAgeRange" value={editFeedForm.ageRange} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, ageRange: e.target.value }))} />
            </div>
            <div className="grid grid-cols-2 gap-4">
              <div className="space-y-2">
                <Label htmlFor="editFeedProtein">Protein (%)</Label>
                <Input id="editFeedProtein" type="number" min="0" step="0.1" value={editFeedForm.protein} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, protein: parseFloat(e.target.value) || 0 }))} />
              </div>
              <div className="space-y-2">
                <Label htmlFor="editFeedEnergy">Energy (kcal/kg)</Label>
                <Input id="editFeedEnergy" type="number" min="0" value={editFeedForm.energy} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, energy: parseFloat(e.target.value) || 0 }))} />
              </div>
            </div>
            <div className="space-y-2">
              <Label htmlFor="editFeedIngredients">Ingredients *</Label>
              <Textarea id="editFeedIngredients" value={editFeedForm.ingredients} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, ingredients: e.target.value }))} />
            </div>
            <div className="space-y-2">
              <Label htmlFor="editFeedNotes">Notes</Label>
              <Textarea id="editFeedNotes" value={editFeedForm.notes} onChange={(e) => setEditFeedForm((prev) => ({ ...prev, notes: e.target.value }))} />
            </div>
          </div>
          <div className="flex justify-end gap-2">
            <Button onClick={() => setIsFeedEditDialogOpen(false)} className="bg-red-600 hover:bg-red-700 text-white">Cancel</Button>
            <Button onClick={handleUpdateFeed}>Save Changes</Button>
          </div>
        </DialogContent>
      </Dialog>

      {/* Delete Confirmation Dialog */}
      <AlertDialog open={deleteDialogOpen} onOpenChange={setDeleteDialogOpen}>
        <AlertDialogContent>
          <AlertDialogHeader>
            <AlertDialogTitle>Delete {deleteTarget?.type === "vaccination" ? "Vaccination Schedule" : deleteTarget?.type === "medication" ? "Medication Schedule" : "Feed Formulation"}</AlertDialogTitle>
            <AlertDialogDescription>
              Are you sure you want to delete &quot;{deleteTarget?.name}&quot;? This action cannot be undone.
            </AlertDialogDescription>
          </AlertDialogHeader>
          <AlertDialogFooter>
            <AlertDialogCancel>Cancel</AlertDialogCancel>
            <AlertDialogAction onClick={handleConfirmDelete} className="bg-red-600 hover:bg-red-700 focus:ring-red-600">
              Delete
            </AlertDialogAction>
          </AlertDialogFooter>
        </AlertDialogContent>
      </AlertDialog>
    </div>
  )
}

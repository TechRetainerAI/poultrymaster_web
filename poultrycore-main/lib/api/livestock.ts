// Livestock — client for api/Livestock/* (migration 458+).
//
// The API hands back the database functions' own JSON (camelCase already), so
// these types are the shapes splivestock*_list / _get build. Every rule lives
// in the database; a refusal arrives as a 400 with a plain-English message,
// which `call` throws as the Error's message for the page to show.

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"
import { forceReauth } from "./session-expiry"

export type SpeciesCategory = "Bird" | "SmallMammal" | "Ruminant" | "Large"

export interface LivestockSpecies {
  speciesCode: string
  name: string
  singular: string
  category: SpeciesCategory
  producesEggs: boolean
  producesMilk: boolean
  breedsOnFarm: boolean
  defaultTracking: "Group" | "Individual"
  penTerm: string
  groupTerm: string
  birthTerm: string | null
  youngTerm: string | null
  gestationDays: number | null
  weaningDays: number | null
  enabled: boolean
  activeGroups: number
  head: number
}

export interface LivestockPen {
  penId: number
  name: string
  speciesCode: string | null
  speciesName: string | null
  capacity: number | null
  location: string | null
  notes: string | null
  isActive: boolean
  activeGroups: number
  head: number
}

export type IntakeSource = "Purchased" | "Gift" | "Transfer" | "Other"

export interface LivestockBatch {
  batchId: number
  batchCode: string
  speciesCode: string
  speciesName: string
  breed: string | null
  quantity: number
  intakeDate: string
  source: IntakeSource
  supplierId: number | null
  costPerHead: number | null
  totalCost: number | null
  ageAtIntake: string | null
  notes: string | null
  allocated: number
  unallocated: number
  groups: { groupId: number; name: string }[]
}

export type GroupPurpose = "Meat" | "Eggs" | "Milk" | "Breeding" | "Mixed"

export interface LivestockGroup {
  groupId: number
  name: string
  speciesCode: string
  speciesName: string
  groupTerm: string
  penId: number | null
  penName: string | null
  penCapacity: number | null
  batchId: number | null
  batchCode: string | null
  breed: string | null
  purpose: GroupPurpose
  startDate: string
  ageAtStartDays: number | null
  status: "Active" | "Closed"
  closedDate: string | null
  closeReason: string | null
  notes: string | null
  head: number
  placed: number
  deaths: number
  tagged: number
  ageDays: number
}

export type MovementType =
  | "Opening" | "Intake" | "Birth" | "TransferIn"
  | "Death" | "Cull" | "Sale" | "TransferOut" | "Correction"

export interface HeadMovement {
  movementId: number
  date: string
  type: MovementType
  quantity: number
  batchCode: string | null
  animalId: number | null
  tagNumber: string | null
  sourceType: string | null
  sourceId: number | null
  notes: string | null
  createdBy: string | null
  createdAt: string
  reversedAt: string | null
  reverseReason: string | null
}

export interface LivestockGroupDetail extends LivestockGroup {
  movements: HeadMovement[]
}

export type AnimalSex = "Female" | "Male" | "Unknown"
export type AnimalStatus = "Active" | "Sold" | "Dead" | "Culled"
export type AnimalSource = "OnFarm" | "Purchased" | "BornOnFarm" | "Other"

export interface LivestockAnimal {
  animalId: number
  tagNumber: string
  name: string | null
  sex: AnimalSex
  breed: string | null
  speciesCode: string
  speciesName: string
  groupId: number
  groupName: string
  penName: string | null
  birthDate: string | null
  ageDays: number | null
  damId: number | null
  damTag: string | null
  sireId: number | null
  sireTag: string | null
  source: AnimalSource
  acquiredDate: string | null
  purchaseCost: number | null
  status: AnimalStatus
  statusDate: string | null
  statusNotes: string | null
  notes: string | null
}

export interface LivestockAnimalDetail extends LivestockAnimal {
  offspring: { animalId: number; tagNumber: string; sex: AnimalSex; birthDate: string | null; status: AnimalStatus }[]
  movements: { movementId: number; date: string; type: MovementType; groupName: string; quantity: number; notes: string | null; reversedAt: string | null }[]
}

export interface LivestockOverview {
  speciesKept: number
  activeGroups: number
  pens: number
  head: number
  tagged: number
  deathsLast30: number
  unallocatedBatches: number
  species: { speciesCode: string; name: string; groupTerm: string; groups: number; head: number; tagged: number }[]
}

// ---------------------------------------------------------------------------

/** A refusal from the API, with its code when it has one (e.g. "WithdrawalPeriod"). */
export class LivestockApiError extends Error {
  constructor(message: string, public code?: string) {
    super(message)
    this.name = "LivestockApiError"
  }
}

function farmId(): string {
  const { farmId } = getUserContext()
  if (!farmId) throw new Error("No active company. Pick a company first.")
  return farmId
}

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(farmApiUrl(path), {
    method,
    headers: getAuthHeaders(),
    body: body === undefined ? undefined : JSON.stringify(body),
  })
  if (!res.ok) {
    if (res.status === 401) forceReauth()
    const raw = await res.text().catch(() => "")
    let message: string | undefined
    let code: string | undefined
    try { const j = JSON.parse(raw); message = j?.message; code = j?.code } catch { /* not JSON */ }
    if ([400, 403, 404, 409].includes(res.status) && message) throw new LivestockApiError(message, code)
    throw new Error(explainHttpError(method, path, res.status, raw))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

const q = () => `farmId=${encodeURIComponent(farmId())}`
const withFarm = <T extends object>(o: T) => ({ ...o, farmId: farmId() })

// ---- Species --------------------------------------------------------------
export const listSpecies = () => call<LivestockSpecies[]>("GET", `/Livestock/species?${q()}`)
export const setSpeciesKept = (speciesCodes: string[]) =>
  call<LivestockSpecies[]>("PUT", "/Livestock/species", withFarm({ speciesCodes }))

// ---- Pens -----------------------------------------------------------------
export interface PenInput {
  name: string
  speciesCode: string | null
  capacity: number | null
  location: string | null
  notes: string | null
  isActive: boolean
}
export const listPens = () => call<LivestockPen[]>("GET", `/Livestock/pens?${q()}`)
export const savePen = (input: PenInput, penId?: number) =>
  penId
    ? call<{ penId: number }>("PUT", `/Livestock/pens/${penId}`, withFarm(input))
    : call<{ penId: number }>("POST", "/Livestock/pens", withFarm(input))
export const deletePen = (penId: number) => call<void>("DELETE", `/Livestock/pens/${penId}?${q()}`)

// ---- Intake batches -------------------------------------------------------
export interface BatchInput {
  batchCode: string | null
  speciesCode: string
  breed: string | null
  quantity: number
  intakeDate: string
  source: IntakeSource
  supplierId: number | null
  costPerHead: number | null
  totalCost: number | null
  ageAtIntake: string | null
  notes: string | null
}
export const listBatches = () => call<LivestockBatch[]>("GET", `/Livestock/batches?${q()}`)
export const saveBatch = (input: BatchInput, batchId?: number) =>
  batchId
    ? call<{ batchId: number }>("PUT", `/Livestock/batches/${batchId}`, withFarm(input))
    : call<{ batchId: number }>("POST", "/Livestock/batches", withFarm(input))
export const deleteBatch = (batchId: number) => call<void>("DELETE", `/Livestock/batches/${batchId}?${q()}`)
export interface DivideGroupInput { name: string; penId: number | null; quantity: number; purpose: GroupPurpose; notes: string | null }
export const divideBatch = (batchId: number, startDate: string | null, groups: DivideGroupInput[]) =>
  call<number[]>("POST", `/Livestock/batches/${batchId}/groups`, withFarm({ startDate, groups }))

// ---- Groups ---------------------------------------------------------------
export interface GroupInput {
  name: string
  speciesCode: string
  penId: number | null
  breed: string | null
  purpose: GroupPurpose
  startDate: string
  /** How old the animals were on the start date, in days (vaccination timing). */
  ageAtStartDays?: number | null
  notes: string | null
  /** Create only. */
  source?: "Batch" | "Opening" | "Empty"
  batchId?: number | null
  quantity?: number | null
}
export const listGroups = (includeClosed = false) =>
  call<LivestockGroup[]>("GET", `/Livestock/groups?${q()}&includeClosed=${includeClosed}`)
export const getGroup = (groupId: number) => call<LivestockGroupDetail>("GET", `/Livestock/groups/${groupId}?${q()}`)
export const saveGroup = (input: GroupInput, groupId?: number) =>
  groupId
    ? call<{ groupId: number }>("PUT", `/Livestock/groups/${groupId}`, withFarm(input))
    : call<{ groupId: number }>("POST", "/Livestock/groups", withFarm(input))
export const deleteGroup = (groupId: number) => call<void>("DELETE", `/Livestock/groups/${groupId}?${q()}`)
export const closeGroup = (groupId: number, date: string, reason: string | null) =>
  call<void>("PUT", `/Livestock/groups/${groupId}/closure`, withFarm({ date, reason }))
export const reopenGroup = (groupId: number) => call<void>("PUT", `/Livestock/groups/${groupId}/reopening`, withFarm({}))

export type HeadChangeType = "Death" | "Cull" | "Correction" | "Transfer"
export interface HeadChangeInput { date: string; type: HeadChangeType; quantity: number; notes: string | null; toGroupId?: number | null }
export const changeHead = (groupId: number, input: HeadChangeInput) =>
  call<{ movementId: number; head: number; toHead?: number }>("POST", `/Livestock/groups/${groupId}/movements`, withFarm(input))
export const reverseHeadChange = (movementId: number, reason: string) =>
  call<void>("POST", `/Livestock/groups/movements/${movementId}/reversal`, withFarm({ reason }))

// ---- Animals --------------------------------------------------------------
export interface AnimalInput {
  tagNumber: string
  name: string | null
  sex: AnimalSex
  breed: string | null
  birthDate: string | null
  damId: number | null
  sireId: number | null
  source: AnimalSource
  acquiredDate: string | null
  purchaseCost: number | null
  notes: string | null
  /** Register only. */
  groupId?: number
  addsToHead?: boolean
}
export interface AnimalFilter { groupId?: number; speciesCode?: string; status?: AnimalStatus | "All"; search?: string }
export const listAnimals = (f: AnimalFilter = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  if (f.groupId) p.set("groupId", String(f.groupId))
  if (f.speciesCode) p.set("speciesCode", f.speciesCode)
  if (f.status) p.set("status", f.status)
  if (f.search) p.set("search", f.search)
  return call<LivestockAnimal[]>("GET", `/Livestock/animals?${p}`)
}
export const getAnimal = (animalId: number) => call<LivestockAnimalDetail>("GET", `/Livestock/animals/${animalId}?${q()}`)
export const saveAnimal = (input: AnimalInput, animalId?: number) =>
  animalId
    ? call<{ animalId: number }>("PUT", `/Livestock/animals/${animalId}`, withFarm(input))
    : call<{ animalId: number }>("POST", "/Livestock/animals", withFarm(input))
/** One row of "Tag several animals": what tells this animal apart. */
export interface TagManyRow {
  tagNumber: string; name: string | null; sex: AnimalSex; breed: string | null; birthDate: string | null
  damId: number | null; sireId: number | null; notes: string | null
  /** A parent being tagged in the same list, by its tag (472). Wins over damId / sireId. */
  damTag?: string | null; sireTag?: string | null
}
export interface TagManyInput {
  groupId: number
  addsToHead: boolean
  source: AnimalSource
  acquiredDate: string | null
  /** Price paid for EACH animal. */
  purchaseCost: number | null
  animals: TagManyRow[]
}
/** All or nothing (468); parents may be other rows of the list by tag (472). */
export const saveAnimals = (input: TagManyInput) =>
  call<{ animalIds: number[] }>("POST", "/Livestock/animals/many", withFarm(input))
export const deleteAnimal = (animalId: number) => call<void>("DELETE", `/Livestock/animals/${animalId}?${q()}`)
export const setAnimalStatus = (animalId: number, status: AnimalStatus, date: string | null, notes: string | null) =>
  call<void>("PUT", `/Livestock/animals/${animalId}/status`, withFarm({ status, date, notes }))
export const moveAnimal = (animalId: number, toGroupId: number, date: string | null) =>
  call<void>("PUT", `/Livestock/animals/${animalId}/group`, withFarm({ toGroupId, date }))

// ---- Overview -------------------------------------------------------------
export const getOverview = () => call<LivestockOverview>("GET", `/Livestock/overview?${q()}`)

// ===========================================================================
// 459: stock items, daily production records, breeding, weigh-ins
// ===========================================================================

export type ItemCategory = "Feed" | "Ingredient" | "Medication" | "Vaccine" | "Supply" | "Produce" | "Other"

export interface LivestockItem {
  itemId: number
  name: string
  category: ItemCategory
  unit: string
  kgPerUnit: number | null
  minimumStock: number | null
  speciesCode: string | null
  speciesName: string | null
  notes: string | null
  isActive: boolean
  /** 494: feed collected from the forest / bush, not bought (Collect feed). Feed items only. */
  isForage: boolean
  stock: number
  value: number
  avgCost: number | null
  isLow: boolean
  hasMovements: boolean
}

export type StockMovementType = "Opening" | "StockIn" | "Purchase" | "Usage" | "Adjustment" | "Produced" | "Loss" | "Collected"

export interface StockMovement {
  movementId: number
  date: string
  type: StockMovementType
  quantity: number
  unitCost: number | null
  totalCost: number
  sourceType: string | null
  sourceId: number | null
  groupName: string | null
  notes: string | null
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}

export interface LivestockItemDetail extends LivestockItem { movements: StockMovement[] }

export interface ItemInput {
  name: string
  category: ItemCategory
  unit: string
  kgPerUnit: number | null
  minimumStock: number | null
  speciesCode: string | null
  notes: string | null
  isActive?: boolean
  /** 494: Feed only. */
  isForage?: boolean
}

export const listItems = (category?: ItemCategory | "Health", includeInactive = false) =>
  call<LivestockItem[]>("GET", `/Livestock/items?${q()}${category ? `&category=${category}` : ""}&includeInactive=${includeInactive}`)
export const getItem = (itemId: number) => call<LivestockItemDetail>("GET", `/Livestock/items/${itemId}?${q()}`)
export const saveItem = (input: ItemInput, itemId?: number) =>
  itemId
    ? call<{ itemId: number }>("PUT", `/Livestock/items/${itemId}`, withFarm(input))
    : call<{ itemId: number }>("POST", "/Livestock/items", withFarm(input))
export const deleteItem = (itemId: number) => call<void>("DELETE", `/Livestock/items/${itemId}?${q()}`)
export const changeStock = (input: { itemId: number; date: string; type: "Adjustment"; quantity: number; unitCost: number | null; notes: string | null }) =>
  call<LivestockItem & { movementId: number }>("POST", "/Livestock/stock", withFarm(input))
export const reverseStockChange = (movementId: number, reason: string) =>
  call<void>("POST", `/Livestock/stock/${movementId}/reversal`, withFarm({ reason }))

// 494: feed collected from the forest / bush (forage). Goes into stock at what
// collecting it cost (0 if nothing); that cost is paid from a cash account.
export interface ForageCollection {
  collectionId: number
  itemId: number
  itemName: string
  unit: string
  date: string
  quantity: number
  kg: number | null
  place: string | null
  collectedBy: string | null
  cost: number
  costPerUnit: number
  accountId: number | null
  accountName: string | null
  notes: string | null
  createdBy: string | null
  createdAt: string
  reversedAt: string | null
  reversedBy: string | null
  reverseReason: string | null
}
export interface ForageCollectionInput {
  itemId: number
  date: string
  quantity: number
  place: string | null
  collectedBy: string | null
  cost: number
  accountId: number | null
  notes: string | null
}
export const listForageCollections = (f: { from?: string; to?: string; itemId?: number } = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  if (f.from) p.set("from", f.from)
  if (f.to) p.set("to", f.to)
  if (f.itemId) p.set("itemId", String(f.itemId))
  return call<ForageCollection[]>("GET", `/Livestock/stock/collections?${p}`)
}
export const collectForage = (input: ForageCollectionInput) =>
  call<ForageCollection>("POST", "/Livestock/stock/collections", withFarm(input))
export const reverseForageCollection = (collectionId: number, reason: string) =>
  call<void>("POST", `/Livestock/stock/collections/${collectionId}/reversal`, withFarm({ reason }))

export interface ProductionLine {
  lineId: number
  lineType: "Feed" | "Medication"
  itemId: number
  itemName: string
  unit: string
  quantity: number
  unitCost: number | null
  totalCost: number | null
  notes: string | null
}

export interface ProductionRecord {
  recordId: number
  groupId: number
  groupName: string
  speciesCode: string
  speciesName: string
  date: string
  deaths: number
  deathCause: string | null
  culls: number
  eggsCollected: number | null
  eggsBroken: number | null
  milkLitres: number | null
  waterLitres: number | null
  notes: string | null
  /** 494: the animals went out to graze (nothing goes into stock). */
  grazed: boolean
  grazingHours: number | null
  grazingPlace: string | null
  headEndOfDay: number
  feedQuantity: number
  feedKg: number | null
  feedCost: number
  medicationCost: number
  lines: ProductionLine[]
  createdBy: string | null
  createdAt: string
  updatedBy: string | null
  updatedAt: string | null
}

export interface ProductionForm {
  groupId: number
  groupName: string
  speciesCode: string
  speciesName: string
  producesEggs: boolean
  producesMilk: boolean
  startDate: string
  status: "Active" | "Closed"
  headStartOfDay: number
  headNow: number
  existingRecordId: number | null
  lastRecord: ProductionRecord | null
}

export interface ProductionLineInput { itemId: number; quantity: number; notes: string | null }

export interface ProductionInput {
  groupId: number
  date: string
  deaths: number
  deathCause: string | null
  culls: number
  eggsCollected: number | null
  eggsBroken: number | null
  milkLitres: number | null
  waterLitres: number | null
  notes: string | null
  grazed: boolean
  grazingHours: number | null
  grazingPlace: string | null
  feedLines: ProductionLineInput[]
  medicationLines: ProductionLineInput[]
}

export interface ProductionFilter { groupId?: number; speciesCode?: string; from?: string; to?: string }
export const listProductionRecords = (f: ProductionFilter = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  if (f.groupId) p.set("groupId", String(f.groupId))
  if (f.speciesCode) p.set("speciesCode", f.speciesCode)
  if (f.from) p.set("from", f.from)
  if (f.to) p.set("to", f.to)
  return call<ProductionRecord[]>("GET", `/Livestock/production-records?${p}`)
}
export const getProductionRecord = (recordId: number) =>
  call<ProductionRecord>("GET", `/Livestock/production-records/${recordId}?${q()}`)
export const getProductionForm = (groupId: number, date: string) =>
  call<ProductionForm>("GET", `/Livestock/production-records/form?${q()}&groupId=${groupId}&date=${date}`)
export const saveProductionRecord = (input: ProductionInput, recordId?: number) =>
  recordId
    ? call<{ recordId: number }>("PUT", `/Livestock/production-records/${recordId}`, withFarm(input))
    : call<{ recordId: number }>("POST", "/Livestock/production-records", withFarm(input))
export const deleteProductionRecord = (recordId: number) =>
  call<void>("DELETE", `/Livestock/production-records/${recordId}?${q()}`)

export type BreedingEventType = "Mating" | "PregnancyCheck" | "Birth" | "Weaning" | "Loss"

export interface BreedingEvent {
  eventId: number
  eventType: BreedingEventType
  date: string
  speciesCode: string
  speciesName: string
  birthTerm: string | null
  youngTerm: string | null
  damId: number | null
  damTag: string | null
  sireId: number | null
  sireTag: string | null
  groupId: number | null
  groupName: string | null
  toGroupId: number | null
  toGroupName: string | null
  method: "Natural" | "AI" | null
  result: "Pregnant" | "NotPregnant" | null
  bornAlive: number | null
  bornDead: number | null
  weanedCount: number | null
  notes: string | null
  expectedBirth: string | null
  createdBy: string | null
}

export interface DueBreeding extends BreedingEvent { pregnancyConfirmed: boolean; daysToDue: number | null }

export interface BreedingInput {
  eventType: BreedingEventType
  date: string
  damId: number | null
  sireId: number | null
  groupId: number | null
  toGroupId: number | null
  method: "Natural" | "AI" | null
  result: "Pregnant" | "NotPregnant" | null
  bornAlive: number | null
  bornDead: number | null
  weanedCount: number | null
  notes: string | null
}

export interface BreedingFilter { damId?: number; groupId?: number; speciesCode?: string; eventType?: BreedingEventType; from?: string; to?: string }
export const listBreeding = (f: BreedingFilter = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<BreedingEvent[]>("GET", `/Livestock/breeding?${p}`)
}
export const listBreedingDue = () => call<DueBreeding[]>("GET", `/Livestock/breeding/due?${q()}`)
export const saveBreeding = (input: BreedingInput, eventId?: number) =>
  eventId
    ? call<{ eventId: number }>("PUT", `/Livestock/breeding/${eventId}`, withFarm(input))
    : call<{ eventId: number }>("POST", "/Livestock/breeding", withFarm(input))
export const deleteBreeding = (eventId: number) => call<void>("DELETE", `/Livestock/breeding/${eventId}?${q()}`)

export interface GroupWeighIn {
  weighInId: number
  date: string
  sampleSize: number | null
  avgWeightKg: number
  head: number
  notes: string | null
  gainKg: number | null
  days: number | null
  dailyGainG: number | null
  feedKg: number | null
  fcr: number | null
}
export interface Growth {
  groupId: number
  weighIns: GroupWeighIn[]
  animalWeighIns: { weighInId: number; date: string; animalId: number; tagNumber: string; avgWeightKg: number; notes: string | null }[]
  feedKgTotal: number | null
  feedWithoutKg: boolean
}
export interface WeighInInput { groupId?: number | null; animalId?: number | null; date: string; avgWeightKg: number; sampleSize: number | null; notes: string | null }
export const getGrowth = (groupId: number) => call<Growth>("GET", `/Livestock/weigh-ins/growth/${groupId}?${q()}`)
export const listAnimalWeights = (animalId: number) =>
  call<{ weighInId: number; date: string; avgWeightKg: number; notes: string | null }[]>("GET", `/Livestock/weigh-ins/animal/${animalId}?${q()}`)
export const saveWeighIn = (input: WeighInInput, weighInId?: number) =>
  weighInId
    ? call<{ weighInId: number }>("PUT", `/Livestock/weigh-ins/${weighInId}`, withFarm(input))
    : call<{ weighInId: number }>("POST", "/Livestock/weigh-ins", withFarm(input))
export const deleteWeighIn = (weighInId: number) => call<void>("DELETE", `/Livestock/weigh-ins/${weighInId}?${q()}`)

// ===========================================================================
// 460: health, vaccination, treatments, feed formulas & mixing, distribution,
// days of supply, alerts
// ===========================================================================

export type HealthKind = "Observation" | "Illness" | "Treatment" | "Vaccination" | "Deworming" | "VetVisit"

export interface HealthRecord {
  healthId: number
  groupId: number
  groupName: string
  speciesName: string
  animalId: number | null
  tagNumber: string | null
  date: string
  kind: HealthKind
  affected: number | null
  signs: string | null
  diagnosis: string | null
  action: string | null
  vetName: string | null
  itemId: number | null
  itemName: string | null
  unit: string | null
  quantity: number | null
  cost: number | null
  stepId: number | null
  stepName: string | null
  status: "Open" | "Resolved"
  resolvedDate: string | null
  notes: string | null
  createdBy: string | null
}

export interface HealthInput {
  groupId: number | null
  animalId: number | null
  date: string
  kind: HealthKind
  affected: number | null
  signs: string | null
  diagnosis: string | null
  action: string | null
  vetName: string | null
  itemId: number | null
  quantity: number | null
  stepId: number | null
  status: "Open" | "Resolved"
  resolvedDate?: string | null
  notes: string | null
}

export interface HealthFilter { groupId?: number; animalId?: number; kind?: HealthKind; status?: "Open" | "Resolved"; from?: string; to?: string }
export const listHealth = (f: HealthFilter = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<HealthRecord[]>("GET", `/Livestock/health?${p}`)
}
export const saveHealth = (input: HealthInput, healthId?: number) =>
  healthId
    ? call<{ healthId: number }>("PUT", `/Livestock/health/${healthId}`, withFarm(input))
    : call<{ healthId: number }>("POST", "/Livestock/health", withFarm(input))
export const deleteHealth = (healthId: number) => call<void>("DELETE", `/Livestock/health/${healthId}?${q()}`)

export type PlanStepKind = "Vaccination" | "Deworming" | "Treatment"
export interface PlanStep {
  stepId?: number
  name: string
  kind: PlanStepKind
  dayOfAge: number
  repeatDays: number | null
  method: string | null
  notes: string | null
}
export interface VaccinePlan {
  planId: number
  speciesCode: string
  speciesName: string
  name: string
  notes: string | null
  isSuggested: boolean
  copiedFrom: number | null
  inUse: boolean
  steps: PlanStep[]
}
export interface DueStep {
  groupId: number
  groupName: string
  speciesCode: string
  stepId: number
  name: string
  kind: PlanStepKind
  method: string | null
  dayOfAge: number
  repeatDays: number | null
  due: string
  lastGiven: string | null
  ageOnDue: number
  daysToDue: number
  status: "Overdue" | "DueSoon" | "Upcoming"
}
export const listDueSteps = (horizonDays = 60, groupId?: number) =>
  call<DueStep[]>("GET", `/Livestock/vaccination/due?${q()}&horizonDays=${horizonDays}${groupId ? `&groupId=${groupId}` : ""}`)
export const listPlans = () => call<VaccinePlan[]>("GET", `/Livestock/vaccination/plans?${q()}`)
export const savePlan = (input: { speciesCode?: string; name: string; notes: string | null; steps: PlanStep[] }, planId?: number) =>
  planId
    ? call<{ planId: number }>("PUT", `/Livestock/vaccination/plans/${planId}`, withFarm(input))
    : call<{ planId: number }>("POST", "/Livestock/vaccination/plans", withFarm(input))
export const copyPlan = (planId: number) => call<{ planId: number }>("POST", `/Livestock/vaccination/plans/${planId}/copy`, withFarm({}))
export const deletePlan = (planId: number) => call<void>("DELETE", `/Livestock/vaccination/plans/${planId}?${q()}`)
export const setPlanInUse = (speciesCode: string, planId: number | null) =>
  call<void>("PUT", "/Livestock/vaccination/plan-in-use", withFarm({ speciesCode, planId }))

export type DoseBasis = "PerAnimal" | "Per100Animals" | "PerGroup"
export interface TreatmentDay {
  dayId: number
  date: string
  notes: string | null
  postedBy: string | null
  reversedAt: string | null
  reverseReason: string | null
  lines: { groupId: number; groupName: string; head: number; quantity: number }[]
}
export interface Treatment {
  treatmentId: number
  name: string
  itemId: number
  itemName: string
  unit: string
  reason: string | null
  startDate: string
  endDate: string
  doseQuantity: number
  doseBasis: DoseBasis
  meatWithdrawalDays: number | null
  milkWithdrawalDays: number | null
  eggWithdrawalDays: number | null
  lifecycle: "Open" | "Completed" | "Cancelled"
  status: "Scheduled" | "InProgress" | "Completed" | "Cancelled"
  notes: string | null
  groups: { groupId: number; name: string; head: number; status: string; suggested: number }[]
  postedDays: number
  plannedDays: number
  totalQuantity: number
  totalCost: number
  days: TreatmentDay[]
  createdBy: string | null
  cancelReason: string | null
}
export interface TreatmentInput {
  name: string
  itemId: number
  reason: string | null
  startDate: string
  endDate: string
  doseQuantity: number
  doseBasis: DoseBasis
  meatWithdrawalDays: number | null
  milkWithdrawalDays: number | null
  eggWithdrawalDays: number | null
  notes: string | null
  groupIds: number[]
}
export interface Withdrawal {
  groupId: number
  groupName: string
  treatmentId: number
  treatmentName: string
  itemName: string
  lastDose: string
  meatUntil: string | null
  milkUntil: string | null
  eggsUntil: string | null
}
export const listTreatments = () => call<Treatment[]>("GET", `/Livestock/treatments?${q()}`)
export const getTreatment = (id: number) => call<Treatment>("GET", `/Livestock/treatments/${id}?${q()}`)
export const listWithdrawals = (groupId?: number) =>
  call<Withdrawal[]>("GET", `/Livestock/treatments/withdrawals?${q()}${groupId ? `&groupId=${groupId}` : ""}`)
export const createTreatment = (input: TreatmentInput) => call<{ treatmentId: number }>("POST", "/Livestock/treatments", withFarm(input))
export const postTreatmentDay = (id: number, date: string, lines: { groupId: number; quantity: number }[] | null, notes: string | null) =>
  call<{ dayId: number }>("POST", `/Livestock/treatments/${id}/days`, withFarm({ date, lines, notes }))
export const reverseTreatmentDay = (dayId: number, reason: string) =>
  call<void>("POST", `/Livestock/treatments/days/${dayId}/reversal`, withFarm({ reason }))
export const closeTreatment = (id: number, action: "Complete" | "Cancel", reason: string | null) =>
  call<void>("PUT", `/Livestock/treatments/${id}/closure`, withFarm({ action, reason }))

export interface FeedFormula {
  formulaId: number
  name: string
  outputItemId: number
  outputItemName: string
  outputUnit: string
  batchQuantity: number
  speciesCode: string | null
  notes: string | null
  isActive: boolean
  lines: { itemId: number; itemName: string; unit: string; quantity: number; stock: number; avgCost: number | null }[]
  batchCost: number | null
  batchesPossible: number | null
}
export interface FormulaInput {
  name: string
  outputItemId: number
  batchQuantity: number
  speciesCode: string | null
  notes: string | null
  isActive?: boolean
  lines: { itemId: number; quantity: number }[]
}
export const listFormulas = () => call<FeedFormula[]>("GET", `/Livestock/feed-formulas?${q()}`)
export const saveFormula = (input: FormulaInput, formulaId?: number) =>
  formulaId
    ? call<{ formulaId: number }>("PUT", `/Livestock/feed-formulas/${formulaId}`, withFarm(input))
    : call<{ formulaId: number }>("POST", "/Livestock/feed-formulas", withFarm(input))
export const deleteFormula = (formulaId: number) => call<void>("DELETE", `/Livestock/feed-formulas/${formulaId}?${q()}`)

export interface FeedRun {
  runId: number
  formulaId: number
  formulaName: string
  date: string
  batches: number
  outputQuantity: number
  outputItemName: string
  outputUnit: string
  otherCost: number
  totalCost: number | null
  unitCost: number | null
  notes: string | null
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export const listFeedRuns = () => call<FeedRun[]>("GET", `/Livestock/feed-production?${q()}`)
export const mixFeed = (input: { formulaId: number; date: string; batches: number; outputQuantity: number | null; otherCost: number | null; notes: string | null }) =>
  call<{ runId: number }>("POST", "/Livestock/feed-production", withFarm(input))
export const reverseFeedRun = (runId: number, reason: string) =>
  call<void>("POST", `/Livestock/feed-production/${runId}/reversal`, withFarm({ reason }))

export const distributeFeed = (date: string, itemId: number, lines: { groupId: number; quantity: number }[]) =>
  call<{ groupId: number; recordId: number; quantity: number }[]>("POST", "/Livestock/feed-distribution", withFarm({ date, itemId, lines }))

export interface FeedSupply {
  itemId: number
  name: string
  category: ItemCategory
  unit: string
  stock: number
  usedPerDay: number
  daysLeft: number | null
  runsOutOn: string | null
}
export const getFeedSupply = (windowDays = 14) => call<FeedSupply[]>("GET", `/Livestock/feed-supply?${q()}&windowDays=${windowDays}`)

export interface LivestockAlert {
  severity: "High" | "Medium" | "Info"
  kind: string
  title: string
  message: string
  href: string
  groupId?: number
  itemId?: number
  date?: string | null
}
export const listAlerts = () => call<LivestockAlert[]>("GET", `/Livestock/alerts?${q()}`)

// ===========================================================================
// 461: cash accounts, purchases, supplier payments & balances, stock losses,
// head counts, animal stock report. Suppliers are the shared lib/api/supplier.
// ===========================================================================

export type CashAccountType = "Cash" | "Bank" | "MobileMoney" | "Other"
export interface CashAccount {
  accountId: number
  name: string
  accountType: CashAccountType
  openingBalance: number
  openingDate: string
  allowNegative: boolean
  isDefault: boolean
  isActive: boolean
  notes: string | null
  balance: number
  hasTransactions: boolean
}
export interface CashTransaction {
  txId: number
  date: string
  amount: number
  category: string
  description: string | null
  sourceType: string | null
  sourceId: number | null
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export interface CashAccountDetail extends CashAccount { balanceBefore: number; transactions: CashTransaction[] }
export interface CashAccountInput {
  name: string
  accountType: CashAccountType
  openingBalance: number
  openingDate: string
  allowNegative: boolean
  isDefault: boolean
  isActive?: boolean
  notes: string | null
}
export const listCashAccounts = (includeInactive = false) =>
  call<CashAccount[]>("GET", `/Livestock/cash-accounts?${q()}&includeInactive=${includeInactive}`)
export const getCashAccount = (id: number, from?: string, to?: string) =>
  call<CashAccountDetail>("GET", `/Livestock/cash-accounts/${id}?${q()}${from ? `&from=${from}` : ""}${to ? `&to=${to}` : ""}`)
export const saveCashAccount = (input: CashAccountInput, id?: number) =>
  id
    ? call<{ accountId: number }>("PUT", `/Livestock/cash-accounts/${id}`, withFarm(input))
    : call<{ accountId: number }>("POST", "/Livestock/cash-accounts", withFarm(input))

export interface PurchaseLine {
  lineId: number
  lineType: "Item" | "Animals" | "Expense"
  expenseCategory: string | null
  description: string | null
  itemId: number | null
  itemName: string | null
  unit: string | null
  batchId: number | null
  batchCode: string | null
  speciesName: string | null
  quantity: number
  unitCost: number
  lineTotal: number
}
export interface Purchase {
  purchaseId: number
  supplierId: number | null
  supplierName: string | null
  date: string
  reference: string | null
  dueDate: string | null
  total: number
  notes: string | null
  paid: number
  owed: number
  status: "Unpaid" | "PartPaid" | "Paid" | "Reversed"
  overdue: boolean
  lines: PurchaseLine[]
  payments: { paymentId: number; date: string; amount: number; accountName: string; isUpfront: boolean; reversedAt: string | null }[]
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export type PurchaseLineInput =
  | { lineType: "Item"; itemId: number; quantity: number; unitCost: number }
  | { lineType: "Expense"; expenseCategory: string; description: string | null; groupId: number | null; quantity: number; unitCost: number }
  | { lineType: "Animals"; batchCode?: string | null; speciesCode: string; quantity: number; unitCost: number; breed: string | null; ageAtIntake: string | null }
export interface PurchaseInput {
  supplierId: number | null
  date: string
  reference: string | null
  dueDate: string | null
  notes: string | null
  lines: PurchaseLineInput[]
  amountPaid: number
  accountId: number | null
}
export const listPurchases = (f: { supplierId?: number; status?: "Unpaid" | "All"; from?: string; to?: string } = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<Purchase[]>("GET", `/Livestock/purchases?${p}`)
}
export const getPurchase = (id: number) => call<Purchase>("GET", `/Livestock/purchases/${id}?${q()}`)
export const createPurchase = (input: PurchaseInput) => call<{ purchaseId: number }>("POST", "/Livestock/purchases", withFarm(input))
export const reversePurchase = (id: number, reason: string) => call<void>("POST", `/Livestock/purchases/${id}/reversal`, withFarm({ reason }))

export interface SupplierPayment {
  paymentId: number
  supplierId: number | null
  supplierName: string | null
  date: string
  amount: number
  accountId: number
  accountName: string
  reference: string | null
  notes: string | null
  isUpfront: boolean
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
  purchases: { purchaseId: number; amount: number }[]
}
export interface SupplierBalance {
  supplierId: number
  name: string
  phone: string | null
  bought: number
  paid: number
  owed: number
  overdue: number
  lastPurchase: string | null
}
export interface SupplierStatement {
  supplierId: number
  name: string
  owed: number
  lines: { date: string; kind: "Purchase" | "Payment"; id: number; description: string; bought: number | null; paid: number | null; balance: number }[]
}
export const listSupplierPayments = (supplierId?: number) =>
  call<SupplierPayment[]>("GET", `/Livestock/supplier-payments?${q()}${supplierId ? `&supplierId=${supplierId}` : ""}`)
export const paySupplier = (input: { supplierId: number; date: string; amount: number; accountId: number; reference: string | null; notes: string | null; purchaseId?: number | null }) =>
  call<{ paymentId: number }>("POST", "/Livestock/supplier-payments", withFarm(input))
export const reverseSupplierPayment = (id: number, reason: string) =>
  call<void>("POST", `/Livestock/supplier-payments/${id}/reversal`, withFarm({ reason }))
export const listSupplierBalances = () => call<SupplierBalance[]>("GET", `/Livestock/supplier-balances?${q()}`)
export const getSupplierStatement = (supplierId: number) => call<SupplierStatement>("GET", `/Livestock/supplier-balances/${supplierId}?${q()}`)

export type LossReason = "Spoiled" | "Expired" | "Spilled" | "Stolen" | "Damaged" | "Other"
export interface Losses {
  stock: { movementId: number; date: string; itemId: number; itemName: string; unit: string; quantity: number; value: number; reason: LossReason; notes: string | null; createdBy: string | null; reversedAt: string | null }[]
  stockValue: number
  animals: { groupId: number; groupName: string; speciesName: string; deaths: number; culls: number; placed: number }[]
}
export const getLosses = (from: string, to: string) => call<Losses>("GET", `/Livestock/losses?${q()}&from=${from}&to=${to}`)
export const recordLoss = (input: { itemId: number; date: string; quantity: number; reason: LossReason; notes: string | null }) =>
  call<{ movementId: number }>("POST", "/Livestock/losses", withFarm(input))

export interface HeadCountRow { groupId: number; name: string; speciesName: string; penName: string | null; headOnDate: number; headNow: number; tagged: number }
export const getHeadCountSheet = (date: string, speciesCode?: string, batchId?: number) =>
  call<HeadCountRow[]>("GET", `/Livestock/head-count?${q()}&date=${date}${speciesCode ? `&speciesCode=${speciesCode}` : ""}${batchId ? `&batchId=${batchId}` : ""}`)
export const postHeadCount = (date: string, lines: { groupId: number; counted: number }[], notes: string | null) =>
  call<{ groupId: number; name: string; before: number; counted: number; change: number; headNow: number }[]>("POST", "/Livestock/head-count", withFarm({ date, lines, notes }))

export interface AnimalStockRow {
  groupId: number
  groupName: string
  speciesCode: string
  speciesName: string
  status: "Active" | "Closed"
  opening: number
  cameIn: number
  born: number
  movedIn: number
  movedOut: number
  died: number
  culled: number
  sold: number
  corrections: number
  closing: number
}
export const getAnimalStock = (from: string, to: string, speciesCode?: string) =>
  call<AnimalStockRow[]>("GET", `/Livestock/animal-stock?${q()}&from=${from}&to=${to}${speciesCode ? `&speciesCode=${speciesCode}` : ""}`)

// ===========================================================================
// 462: sales, customer payments & balances, expenses. Customers are the shared
// api/Customer list (called directly here: lib/api/customer falls back to mock
// customers on failure, which must never reach a sale).
// ===========================================================================

export interface LsCustomer { customerId: number; name: string; contactPhone: string; contactEmail: string; address: string; city: string }
export const listCustomers = async () => {
  const { userId } = getUserContext()
  const rows = await call<any[]>("GET", `/Customer?${q()}&userId=${encodeURIComponent(userId)}`)
  return (rows ?? []).map((r) => ({
    customerId: Number(r.customerId ?? r.CustomerId), name: String(r.name ?? r.Name ?? ""),
    contactPhone: String(r.contactPhone ?? r.ContactPhone ?? ""), contactEmail: String(r.contactEmail ?? r.ContactEmail ?? ""),
    address: String(r.address ?? r.Address ?? ""), city: String(r.city ?? r.City ?? ""),
  } as LsCustomer)).sort((a, b) => a.name.localeCompare(b.name))
}
export const saveCustomer = (input: { name: string; contactPhone: string; contactEmail: string | null; address: string; city: string }, customerId?: number) => {
  const { userId } = getUserContext()
  const body = withFarm({ ...input, userId, customerId: customerId ?? 0, contactEmail: input.contactEmail?.trim() || null, createdDate: new Date().toISOString() })
  return customerId ? call<void>("PUT", `/Customer/${customerId}`, body) : call<unknown>("POST", "/Customer", body)
}

export type SaleLineType = "Animals" | "Tagged" | "Product"
export interface SaleLine {
  lineId: number
  lineType: SaleLineType
  groupId: number | null
  groupName: string | null
  animalId: number | null
  tagNumber: string | null
  itemId: number | null
  itemName: string | null
  unit: string | null
  speciesName: string | null
  quantity: number
  unitPrice: number
  lineTotal: number
  costTotal: number | null
  weightKg: number | null
}
export interface Sale {
  saleId: number
  customerId: number | null
  customerName: string | null
  customerPhone: string | null
  date: string
  reference: string | null
  dueDate: string | null
  total: number
  notes: string | null
  withdrawalOverride: string | null
  paid: number
  owed: number
  cost: number
  status: "Unpaid" | "PartPaid" | "Paid" | "Reversed"
  overdue: boolean
  lines: SaleLine[]
  payments: { paymentId: number; date: string; amount: number; accountName: string; isUpfront: boolean; reversedAt: string | null }[]
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export type SaleLineInput =
  | { lineType: "Animals"; groupId: number; quantity: number; unitPrice: number; weightKg: number | null }
  | { lineType: "Tagged"; animalId: number; unitPrice: number; weightKg: number | null }
  | { lineType: "Product"; itemId: number; quantity: number; unitPrice: number }
export interface SaleInput {
  customerId: number | null
  date: string
  reference: string | null
  dueDate: string | null
  notes: string | null
  overrideWithdrawal: string | null
  lines: SaleLineInput[]
  amountReceived: number
  accountId: number | null
}
export interface SaleOptions {
  groups: { groupId: number; name: string; speciesName: string; head: number; untagged: number; meatWithdrawalUntil: string | null }[]
  animals: { animalId: number; tagNumber: string; name: string | null; sex: string; speciesName: string; groupId: number; groupName: string }[]
  products: { itemId: number; name: string; unit: string; category: ItemCategory; stock: number; avgCost: number | null }[]
}
export const listSales = (f: { customerId?: number; status?: "Unpaid"; from?: string; to?: string; groupId?: number } = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<Sale[]>("GET", `/Livestock/sales?${p}`)
}
export const getSale = (id: number) => call<Sale>("GET", `/Livestock/sales/${id}?${q()}`)
export const getSaleOptions = () => call<SaleOptions>("GET", `/Livestock/sales/options?${q()}`)
export const createSale = (input: SaleInput) => call<{ saleId: number }>("POST", "/Livestock/sales", withFarm(input))
export const reverseSale = (id: number, reason: string) => call<void>("POST", `/Livestock/sales/${id}/reversal`, withFarm({ reason }))

export interface CustomerPayment {
  paymentId: number
  customerId: number | null
  customerName: string | null
  date: string
  amount: number
  accountId: number
  accountName: string
  reference: string | null
  notes: string | null
  isUpfront: boolean
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export interface CustomerBalance { customerId: number; name: string; phone: string | null; bought: number; paid: number; owes: number; overdue: number; lastSale: string | null }
export interface CustomerStatement {
  customerId: number
  name: string
  owes: number
  lines: { date: string; kind: "Sale" | "Payment"; id: number; description: string; sold: number | null; paid: number | null; balance: number }[]
}
export const listCustomerPayments = (customerId?: number) =>
  call<CustomerPayment[]>("GET", `/Livestock/customer-payments?${q()}${customerId ? `&customerId=${customerId}` : ""}`)
export const receivePayment = (input: { customerId: number; date: string; amount: number; accountId: number; reference: string | null; notes: string | null; saleId?: number | null }) =>
  call<{ paymentId: number }>("POST", "/Livestock/customer-payments", withFarm(input))
export const reverseCustomerPayment = (id: number, reason: string) =>
  call<void>("POST", `/Livestock/customer-payments/${id}/reversal`, withFarm({ reason }))
export const listCustomerBalances = () => call<CustomerBalance[]>("GET", `/Livestock/customer-balances?${q()}`)
export const getCustomerStatement = (customerId: number) => call<CustomerStatement>("GET", `/Livestock/customer-balances/${customerId}?${q()}`)

export type ExpenseCategory = "Labour" | "Veterinary" | "Transport" | "Fuel" | "Utilities" | "Rent" | "Repairs" | "Equipment" | "Fees" | "Security" | "Other"
export const EXPENSE_CATEGORIES: ExpenseCategory[] = ["Labour", "Veterinary", "Transport", "Fuel", "Utilities", "Rent", "Repairs", "Equipment", "Fees", "Security", "Other"]
// 471: the list reads every ledger that costs money, like poultry's Expenses page.
// Only "Paid" rows (typed in here) can be reversed from the Expenses page.
export type ExpenseSource =
  | "Paid" | "Bill" | "Purchase" | "Batch" | "Animal" | "StockUsed" | "StockLost" | "PayRun" | "LoanInterest" | "Depreciation"
  | "ForageCollection"
// Spent: money out or owed. Bought: stock/animals bought. Used: stock already bought,
// now used or lost (no new payment). NonCash: depreciation.
export type ExpenseCostKind = "Spent" | "Bought" | "Used" | "NonCash"
export interface Expense {
  source: ExpenseSource
  costKind: ExpenseCostKind
  id: number
  sourceId: number | null
  date: string
  /** An ExpenseCategory for typed-in rows; item category, "Animals", "Staff pay" ... for the rest. */
  category: string
  description: string | null
  amount: number
  groupId: number | null
  groupName: string | null
  accountName: string | null
  payee: string | null
  /** Purchase number, batch code, or (StockUsed) the record type: ProductionRecord | TreatmentDay | HealthRecord. */
  reference: string | null
  purchaseId: number | null
  paid: number | null
  owed: number | null
  payStatus: "Paid" | "PartPaid" | "Unpaid" | "Reversed" | "NotRecorded" | null
  createdBy: string | null
  reversedAt: string | null
  reverseReason: string | null
}
export interface ExpenseInput { date: string; category: ExpenseCategory; description: string | null; amount: number; groupId: number | null; accountId: number; paidTo: string | null; reference: string | null }
export const listExpenses = (f: { from?: string; to?: string; category?: string; costKind?: ExpenseCostKind; groupId?: number } = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<Expense[]>("GET", `/Livestock/expenses?${p}`)
}
export const createExpense = (input: ExpenseInput) => call<{ expenseId: number }>("POST", "/Livestock/expenses", withFarm(input))
export const reverseExpense = (id: number, reason: string) => call<void>("POST", `/Livestock/expenses/${id}/reversal`, withFarm({ reason }))

// ===========================================================================
// 463: transfers, reconciliation, staff & payroll, staff advances, owner
// money, loans, assets, profit & loss, cash flow
// ===========================================================================

export interface CashTransfer {
  transferId: number; date: string; fromAccountId: number; fromName: string; toAccountId: number; toName: string
  amount: number; fee: number; notes: string | null; createdBy: string | null; reversedAt: string | null; reverseReason: string | null
}
export const listTransfers = () => call<CashTransfer[]>("GET", `/Livestock/cash-transfers?${q()}`)
export const createTransfer = (input: { date: string; fromAccountId: number; toAccountId: number; amount: number; fee: number; notes: string | null }) =>
  call<{ transferId: number }>("POST", "/Livestock/cash-transfers", withFarm(input))
export const reverseTransfer = (id: number, reason: string) => call<void>("POST", `/Livestock/cash-transfers/${id}/reversal`, withFarm({ reason }))

export interface Reconciliation { reconId: number; accountId: number; accountName: string; date: string; booked: number; counted: number; difference: number; notes: string | null; createdBy: string | null }
export const listReconciliations = (accountId?: number) =>
  call<Reconciliation[]>("GET", `/Livestock/cash-reconciliation?${q()}${accountId ? `&accountId=${accountId}` : ""}`)
export const reconcile = (input: { accountId: number; date: string; counted: number; notes: string | null }) =>
  call<{ reconId: number; booked: number; counted: number; difference: number; balance: number }>("POST", "/Livestock/cash-reconciliation", withFarm(input))

export interface Staff {
  staffId: number; name: string; role: string | null; phone: string | null; payType: "Monthly" | "Daily"; payRate: number
  startDate: string | null; isActive: boolean; notes: string | null; owes: number; lastPaid: string | null
}
export interface StaffInput { name: string; role: string | null; phone: string | null; payType: "Monthly" | "Daily"; payRate: number; startDate: string | null; isActive?: boolean; notes: string | null }
export const listStaff = (includeInactive = false) => call<Staff[]>("GET", `/Livestock/staff?${q()}&includeInactive=${includeInactive}`)
export const saveStaff = (input: StaffInput, id?: number) =>
  id ? call<{ staffId: number }>("PUT", `/Livestock/staff/${id}`, withFarm(input)) : call<{ staffId: number }>("POST", "/Livestock/staff", withFarm(input))

export interface PayLine { staffId: number; name?: string; days: number | null; gross: number; deductions: number; loanRepayment: number; net?: number; notes: string | null }
export interface PayRun {
  runId: number; periodStart: string; periodEnd: string; payDate: string; accountId: number; accountName: string; notes: string | null
  createdBy: string | null; reversedAt: string | null; reverseReason: string | null; gross: number; net: number; lines: PayLine[]
}
export const listPayRuns = () => call<PayRun[]>("GET", `/Livestock/payroll?${q()}`)
export const createPayRun = (input: { periodStart: string; periodEnd: string; payDate: string; accountId: number; notes: string | null; lines: PayLine[] }) =>
  call<{ runId: number }>("POST", "/Livestock/payroll", withFarm(input))
export const reversePayRun = (id: number, reason: string) => call<void>("POST", `/Livestock/payroll/${id}/reversal`, withFarm({ reason }))

export interface StaffLoanEntry { kind: "Loan" | "Repayment"; id: number; staffId: number; name: string; date: string; amount: number; accountName: string | null; note: string | null; fromPay?: boolean; reversedAt: string | null }
export const listStaffLoans = (staffId?: number) => call<StaffLoanEntry[]>("GET", `/Livestock/staff-loans?${q()}${staffId ? `&staffId=${staffId}` : ""}`)
export const lendToStaff = (input: { staffId: number; date: string; amount: number; accountId: number; reason: string | null }) =>
  call<{ loanId: number }>("POST", "/Livestock/staff-loans", withFarm(input))
export const staffRepays = (input: { staffId: number; date: string; amount: number; accountId: number }) =>
  call<{ repaymentId: number }>("POST", "/Livestock/staff-loans/repayments", withFarm(input))
export const reverseStaffLoan = (kind: "Loan" | "Repayment", id: number, reason: string) =>
  call<void>("POST", `/Livestock/staff-loans/${kind}/${id}/reversal`, withFarm({ reason }))

export interface OwnerMoney {
  putIn: number; tookOut: number
  entries: { entryId: number; date: string; direction: "In" | "Out"; amount: number; accountName: string; notes: string | null; createdBy: string | null; reversedAt: string | null; reverseReason: string | null }[]
}
export const getOwnerMoney = () => call<OwnerMoney>("GET", `/Livestock/owner-money?${q()}`)
export const recordOwnerMoney = (input: { date: string; direction: "In" | "Out"; amount: number; accountId: number; notes: string | null }) =>
  call<{ entryId: number }>("POST", "/Livestock/owner-money", withFarm(input))
export const reverseOwnerMoney = (id: number, reason: string) => call<void>("POST", `/Livestock/owner-money/${id}/reversal`, withFarm({ reason }))

export interface Loan {
  loanId: number; lender: string; date: string; amount: number; accountName: string; interestNote: string | null; dueDate: string | null
  notes: string | null; balance: number; interestPaid: number; reversedAt: string | null; reverseReason: string | null
  repayments: { repaymentId: number; date: string; principal: number; interest: number; accountName: string; notes: string | null; reversedAt: string | null }[]
}
export const listLoans = () => call<Loan[]>("GET", `/Livestock/loans?${q()}`)
export const borrow = (input: { lender: string; date: string; amount: number; accountId: number; interestNote: string | null; dueDate: string | null; notes: string | null }) =>
  call<{ loanId: number }>("POST", "/Livestock/loans", withFarm(input))
export const repayLoan = (input: { loanId: number; date: string; principal: number; interest: number; accountId: number; notes: string | null }) =>
  call<{ repaymentId: number }>("POST", "/Livestock/loans/repayments", withFarm(input))
export const reverseLoan = (kind: "Loan" | "Repayment", id: number, reason: string) =>
  call<void>("POST", `/Livestock/loans/${kind}/${id}/reversal`, withFarm({ reason }))

export type AssetCategory = "Building" | "Equipment" | "Vehicle" | "Land" | "Other"
export interface Asset {
  assetId: number; name: string; category: AssetCategory; acquiredDate: string; cost: number; salvageValue: number; usefulMonths: number | null
  accountName: string | null; notes: string | null; bookValue: number; depreciationToDate: number; monthlyDepreciation: number
  disposedDate: string | null; disposalAmount: number | null; gainOnDisposal: number | null; createdBy: string | null; reversedAt: string | null; reverseReason: string | null
}
export const listAssets = () => call<Asset[]>("GET", `/Livestock/assets?${q()}`)
export const createAsset = (input: { name: string; category: AssetCategory; acquiredDate: string; cost: number; salvageValue: number; usefulMonths: number | null; accountId: number | null; notes: string | null }) =>
  call<{ assetId: number }>("POST", "/Livestock/assets", withFarm(input))
export const disposeAsset = (id: number, input: { date: string; amount: number; accountId: number | null }) =>
  call<{ bookValue: number; gain: number }>("PUT", `/Livestock/assets/${id}/disposal`, withFarm(input))
export const reverseAsset = (id: number, reason: string) => call<void>("POST", `/Livestock/assets/${id}/reversal`, withFarm({ reason }))

export interface ProfitLoss {
  from: string; to: string; groupId: number | null; groupName: string | null; producesNotByGroup: boolean
  income: { animals: number; produce: number; otherStock: number; assetGain: number; total: number }
  costs: {
    stockSold: number; animalsBought: number; feed: number; medicine: number; otherStock: number; stockLost: number
    expenses: { category: string; amount: number }[]; expensesTotal: number; staffPay: number; loanInterest: number
    depreciation: number; cashDifferences: number; assetLoss: number; total: number
  }
  profit: number
}
export interface GroupProfit { groupId: number; name: string; speciesName: string; status: string; income: number; costs: number; profit: number; feed: number; animalsBought: number; head: number }
export interface CashFlow {
  from: string; to: string; opening: number; accountsOpened: number; totalIn: number; totalOut: number; closing: number
  moneyIn: { category: string; amount: number }[]; moneyOut: { category: string; amount: number }[]
  accounts: { accountId: number; name: string; closing: number }[]
}
export const getProfitLoss = (from: string, to: string, groupId?: number) =>
  call<ProfitLoss>("GET", `/Livestock/reports/profit-loss?${q()}&from=${from}&to=${to}${groupId ? `&groupId=${groupId}` : ""}`)
export const getProfitByGroup = (from: string, to: string) => call<GroupProfit[]>("GET", `/Livestock/reports/profit-by-group?${q()}&from=${from}&to=${to}`)
export const getCashFlow = (from: string, to: string) => call<CashFlow>("GET", `/Livestock/reports/cash-flow?${q()}&from=${from}&to=${to}`)

// ===========================================================================
// 464: daily closing, missing records, delivery
// ===========================================================================

export interface DaySummary {
  date: string
  isClosed: boolean
  closing: { status: "Closed" | "Reopened"; closedBy: string | null; closedAt: string; notes: string | null; acknowledged: { kind: string; message: string }[] | null;
             reopenedBy: string | null; reopenedAt: string | null; reopenReason: string | null } | null
  groups: { groupId: number; name: string; speciesName: string; producesEggs: boolean; producesMilk: boolean; headStart: number; headEnd: number
            deaths: number; culls: number; sold: number; born: number; recordId: number | null; eggs: number | null; milk: number | null; feedCost: number }[]
  totals: { head: number; deaths: number; eggs: number | null; milk: number | null; feedCost: number; sales: number; salesCount: number; expenses: number; moneyIn: number; moneyOut: number }
  money: { accountId: number; name: string; opening: number; moneyIn: number; moneyOut: number; closing: number }[]
  problems: { kind: string; message: string }[]
}
export interface DayListItem { date: string; status: "Open" | "Closed" | "Reopened"; closedBy: string | null; hadProblems: boolean }
export const listDays = (days = 60) => call<DayListItem[]>("GET", `/Livestock/daily-closing?${q()}&days=${days}`)
export const getDaySummary = (date: string) => call<DaySummary>("GET", `/Livestock/daily-closing/${date}?${q()}`)
export const closeDay = (date: string, acknowledge: boolean, notes: string | null) =>
  call<DaySummary>("PUT", `/Livestock/daily-closing/${date}/closure`, withFarm({ acknowledge, notes }))
export const reopenDay = (date: string, reason: string) => call<void>("PUT", `/Livestock/daily-closing/${date}/reopening`, withFarm({ reason }))

export interface MissingRecords { groupId: number; name: string; speciesName: string; missing: number; days: string[]; lastRecord: string | null }
export const getMissingRecords = (from: string, to: string) => call<MissingRecords[]>("GET", `/Livestock/missing-records?${q()}&from=${from}&to=${to}`)

export type FleetKind = "drivers" | "vehicles" | "routes"
export interface FleetItem { id: number; name: string; phone?: string | null; licence?: string | null; registration?: string; description?: string | null; capacity?: string | null; isActive: boolean; notes?: string | null }
export const listFleet = (kind: FleetKind, includeInactive = false) => call<FleetItem[]>("GET", `/Livestock/${kind}?${q()}&includeInactive=${includeInactive}`)
export const saveFleet = (kind: FleetKind, input: Record<string, unknown>, id?: number) =>
  id ? call<{ id: number }>("PUT", `/Livestock/${kind}/${id}`, withFarm(input)) : call<{ id: number }>("POST", `/Livestock/${kind}`, withFarm(input))

export interface Delivery {
  deliveryId: number; date: string; driverId: number; driverName: string; vehicleId: number | null; vehicle: string | null; routeId: number | null; routeName: string | null
  status: "Out" | "Returned" | "Cancelled"; expected: number; collected: number | null; shortage: number | null; returnAccountName: string | null
  notes: string | null; returnNotes: string | null; createdBy: string | null; returnedAt: string | null; returnedBy: string | null
  sales: { saleId: number; customerName: string | null; customerPhone: string | null; total: number; owedNow: number; collected: number | null; reversed: boolean }[]
}
export interface DeliveryOption { saleId: number; date: string; customerName: string | null; customerPhone: string | null; total: number; owed: number }
export interface DriverReportRow { driverId: number; name: string; deliveries: number; stillOut: number; expected: number; collected: number; short: number }
export const listDeliveries = (f: { status?: string; driverId?: number; from?: string; to?: string } = {}) => {
  const p = new URLSearchParams({ farmId: farmId() })
  for (const [k, v] of Object.entries(f)) if (v != null && v !== "") p.set(k, String(v))
  return call<Delivery[]>("GET", `/Livestock/deliveries?${p}`)
}
export const getDeliveryOptions = () => call<DeliveryOption[]>("GET", `/Livestock/deliveries/options?${q()}`)
export const getDriverReport = (from: string, to: string) => call<DriverReportRow[]>("GET", `/Livestock/deliveries/driver-report?${q()}&from=${from}&to=${to}`)
export const sendOutDelivery = (input: { date: string; driverId: number; vehicleId: number | null; routeId: number | null; notes: string | null; saleIds: number[] }) =>
  call<{ deliveryId: number }>("POST", "/Livestock/deliveries", withFarm(input))
export const cancelDelivery = (id: number) => call<void>("PUT", `/Livestock/deliveries/${id}/cancellation`, withFarm({}))
export const returnDelivery = (id: number, input: { accountId: number | null; notes: string | null; collections: { saleId: number; amount: number }[] }) =>
  call<Delivery>("POST", `/Livestock/driver-returns/${id}`, withFarm(input))

// ===========================================================================
// 465: reports and trackers
// ===========================================================================

const period = (from: string, to: string) => `${q()}&from=${from}&to=${to}`

export interface ProductionReport {
  from: string; to: string
  groups: { groupId: number; name: string; speciesName: string; producesEggs: boolean; producesMilk: boolean; headStart: number; headEnd: number
            records: number; deaths: number; mortalityPct: number | null; eggs: number | null; broken: number | null; layRatePct: number | null
            milk: number | null; milkPerAnimalDay: number | null; feedKg: number | null; feedPerAnimalDayKg: number | null }[]
  daily: { date: string; eggs: number | null; milk: number | null; deaths: number | null }[]
}
export interface UsageReport {
  from: string; to: string; totalCost: number
  byItem: { itemId: number; name: string; unit: string; quantity: number; kg: number | null; cost: number }[]
  byGroup: { groupId: number; name: string; cost: number; kg: number | null; head: number }[]
  bySource: Record<string, number>
  treatments?: number; healthRecords?: number
  illnesses?: { diagnosis: string; cases: number; affected: number }[]
}
export interface SalesReport {
  from: string; to: string; total: number; sales: number; received: number
  byWhat: { what: string | null; kind: "Animals" | "Product"; unit: string; quantity: number; amount: number; averagePrice: number | null }[]
  byCustomer: { customerId: number | null; name: string; sales: number; amount: number; owes: number }[]
  daily: { date: string; amount: number }[]
}
export interface MortalityReport {
  from: string; to: string; deaths: number; culls: number
  byGroup: { groupId: number; name: string; speciesName: string; headStart: number; deaths: number; culls: number; mortalityPct: number | null }[]
  causes: { cause: string; deaths: number }[]
}
export interface BreedingReport {
  from: string; to: string
  bySpecies: { speciesName: string; youngTerm: string | null; matings: number; births: number; bornAlive: number; bornDead: number
               averageLitter: number | null; survivalPct: number | null; weaned: number; lost: number }[]
  byMother: { animalId: number; tagNumber: string; births: number; bornAlive: number; averageLitter: number }[]
}
export interface HerdRow {
  speciesCode: string; name: string; head: number; groups: number; tagged: number; females: number; males: number
  ageBands: { under6Months: number; sixTo12Months: number; oneTo2Years: number; over2Years: number; unknown: number }
}
export type GroupSummary = LivestockGroup & {
  lifeDays: number; movements: Record<string, number>; records: number; eggs: number | null; milk: number | null
  feedKg: number | null; latestWeightKg: number | null; profitLoss: ProfitLoss
}
export type TrackerKind = "Deaths" | "Eggs" | "Milk" | "Feed" | "Head"
export interface Tracker {
  month: string; kind: TrackerKind
  groups: { groupId: number; name: string }[]
  days: { date: string; values: Record<string, number> }[]
}

export const getProductionReport = (from: string, to: string, speciesCode?: string) =>
  call<ProductionReport>("GET", `/Livestock/reports/production?${period(from, to)}${speciesCode ? `&speciesCode=${speciesCode}` : ""}`)
export const getFeedReport = (from: string, to: string) => call<UsageReport>("GET", `/Livestock/reports/feed?${period(from, to)}`)
export const getMedicineReport = (from: string, to: string) => call<UsageReport>("GET", `/Livestock/reports/medicine?${period(from, to)}`)
export const getSalesReport = (from: string, to: string) => call<SalesReport>("GET", `/Livestock/reports/sales?${period(from, to)}`)
export const getMortalityReport = (from: string, to: string) => call<MortalityReport>("GET", `/Livestock/reports/mortality?${period(from, to)}`)
export const getBreedingReport = (from: string, to: string) => call<BreedingReport>("GET", `/Livestock/reports/breeding?${period(from, to)}`)
export const getHerdReport = () => call<HerdRow[]>("GET", `/Livestock/reports/herd?${q()}`)
export const getGroupSummary = (groupId: number) => call<GroupSummary>("GET", `/Livestock/reports/group-summary/${groupId}?${q()}`)
export const getTracker = (month: string, kind: TrackerKind) => call<Tracker>("GET", `/Livestock/reports/tracker?${q()}&month=${month}&kind=${kind}`)

// ===========================================================================
// 467: Company settings (the business profile). Currency and time zone are
// saved by the shared farm-settings / CompanyTime endpoints.
// ===========================================================================
export interface CompanyProfile {
  exists: boolean
  brandName: string | null; ownerName: string | null; phoneNumber: string | null; email: string | null
  mainLocation: string | null; siteAddress: string | null; totalCapacity: number | null
  operatingHours: string | null; notes: string | null; updatedBy: string | null; updatedAt: string | null
}
export type CompanyProfileInput = Omit<CompanyProfile, "exists" | "updatedBy" | "updatedAt">
export const getCompanyProfile = () => call<CompanyProfile>("GET", `/Livestock/company?${q()}`)
export const saveCompanyProfile = (input: CompanyProfileInput) => call<void>("PUT", "/Livestock/company", withFarm(input))

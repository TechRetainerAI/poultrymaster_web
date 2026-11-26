// =============================================================================
// Projects & Contracts (Generic) — API client. Migrations 482-486.
//
// A project is a label on existing Generic transactions, never a second set of
// books. Every number here comes from the database engine (484); this file only
// fetches it. Routes: /generic-company/{farmId}/projects..., /project-allocations,
// /project-reservations.
// =============================================================================

import { farmApiUrl, getAuthHeaders, getUserContext } from "./config"
import { explainHttpError } from "@/lib/api/http-error"

// ---------------------------------------------------------------- types

export type ProjectKind = "Project" | "Contract"
export type ProjectStatus = "Draft" | "Planned" | "Active" | "OnHold" | "Completed" | "Cancelled" | "Archived"
export type CostClass = "Direct" | "Shared" | "Overhead" | "Selling" | "Financing" | "Capital"

export const PROJECT_STATUSES: { value: Exclude<ProjectStatus, "Archived">; label: string }[] = [
  { value: "Draft", label: "Draft" },
  { value: "Planned", label: "Planned" },
  { value: "Active", label: "Active" },
  { value: "OnHold", label: "On hold" },
  { value: "Completed", label: "Completed" },
  { value: "Cancelled", label: "Cancelled" },
]

export const statusLabel = (s?: string | null) =>
  s === "OnHold" ? "On hold" : (s ?? "")

export interface GenericProject {
  projectId: number
  projectNumber: string
  name: string
  label: string
  kind: ProjectKind
  status: ProjectStatus
  customerId?: number | null
  customerName?: string | null
  description?: string | null
  startDate?: string | null
  expectedEndDate?: string | null
  actualEndDate?: string | null
  managerStaffId?: number | null
  managerName?: string | null
  notes?: string | null
  externalContractNumber?: string | null
  contractReference?: string | null
  contractingOrganization?: string | null
  awardDate?: string | null
  awardValue?: number | null
  approvedBudget?: number | null
  estimatedDirectCost?: number | null
  estimatedOverhead?: number | null
  expectedProfit?: number | null
  expectedMarginPercent?: number | null
  workingCapitalNeeded?: number | null
  category?: string | null
  location?: string | null
  createdBy?: string | null
  createdAt?: string | null
  updatedAt?: string | null
  archivedAt?: string | null
  statusHistory?: { fromStatus?: string | null; toStatus: string; note?: string | null; changedBy?: string | null; changedAt: string }[]
}

export type ProjectInput = Partial<Omit<GenericProject, "projectId" | "projectNumber" | "label" | "statusHistory">> & { name: string }

export interface ProjectOption {
  projectId: number
  projectNumber: string
  name: string
  label: string
  kind: ProjectKind
  status: ProjectStatus
  customerId?: number | null
}

export interface ProjectPage {
  items: GenericProject[]
  total: number
  page: number
  pageSize: number
  enabled: boolean
}

/** One project's financial position. Every figure is its own measure — see the labels. */
export interface ProjectSummary {
  projectId: number | null
  projectNumber?: string | null
  name: string
  kind?: ProjectKind | null
  status?: ProjectStatus | null
  customerName?: string | null
  expectedEndDate?: string | null
  actualEndDate?: string | null
  awardValue?: number | null
  approvedBudget?: number | null
  remainingAwardValue?: number | null
  revenue: number
  costOfGoodsSold: number
  directCosts: number
  grossProfit: number
  operatingExpenses: number
  allocatedOverhead: number
  operatingProfit: number
  depreciation: number
  financingCosts: number
  netProfit: number
  profitMarginPercent: number | null
  totalCosts: number
  capitalSpend: number
  ownerContributed: number
  ownerDrawn: number
  netOwnerFunding: number
  purchaseValue: number
  cashIn: number
  cashOut: number
  customerCashReceived: number
  procurementCashPaid: number
  expenseCashPaid: number
  operatingCashFlow: number
  investingCashFlow: number
  financingCashFlow: number
  netCashFlow: number
  workingCapitalExposure: number
  receivable: number
  overdueReceivable: number
  payable: number
  customerAdvances: number
  supplierAdvances: number
  budgetVariance?: number | null
  warnings?: string[]
}

export interface ProjectCashFlow {
  moneyIn: number
  moneyOut: number
  net: number
  byActivity: Record<string, number>
  byCategory: { activity: string; category: string; moneyIn: number; moneyOut: number; net: number }[]
  rows: {
    projectId: number | null; cashTransactionId: number; date: string; activity: string; category: string
    sourceType: string; sourceId: number; description: string; amount: number; share: number
  }[]
}

export interface ProjectPnlRow {
  section: string; line: string; date: string; ref: string; description: string
  amount: number; sourceType: string; sourceId: number; costClass?: string | null; share: number
}

export interface ProjectTransactions {
  pnl: ProjectPnlRow[]
  purchases: {
    purchaseId: number; lineId: number; productId: number | null; productName?: string | null
    date: string; ref: string; supplier?: string | null; quantity: number; amount: number
  }[]
  balances: {
    kind: "Receivable" | "Payable" | "CustomerAdvance" | "SupplierAdvance"
    documentType: string; documentId: number; date: string; ref: string; party?: string | null
    dueDate?: string | null; amount: number
  }[]
  cash: ProjectCashFlow
}

export interface ProjectInventory {
  products: {
    productId: number; productName: string; unit?: string | null; costPrice?: number | null
    purchasedQuantity: number; purchasedValue: number; reservedQuantity: number
    deliveredQuantity: number; deliveredValue: number; remainingReserved: number; remainingReservedValue: number
    companyOnHand: number; reservedForAllProjects: number; availableToCompany: number
  }[]
  entries: {
    entryId: number; productId: number; productName: string
    entryType: "Reserve" | "Release" | "TransferOut" | "TransferIn"; quantity: number; date: string
    note?: string | null; createdBy?: string | null; createdAt: string; otherProject?: string | null
    reversedAt?: string | null; reversedBy?: string | null; reversalReason?: string | null
  }[]
}

export type BudgetCategory = "Revenue" | "Materials" | "Labor" | "Transport" | "OtherDirect" | "Overhead" | "Contingency"
export const BUDGET_CATEGORIES: { value: BudgetCategory; label: string }[] = [
  { value: "Revenue", label: "Expected contract revenue" },
  { value: "Materials", label: "Materials / inventory" },
  { value: "Labor", label: "Labour" },
  { value: "Transport", label: "Transport" },
  { value: "OtherDirect", label: "Other direct costs" },
  { value: "Overhead", label: "Shared overhead" },
  { value: "Contingency", label: "Contingency" },
]
export const budgetCategoryLabel = (c: string) => BUDGET_CATEGORIES.find((b) => b.value === c)?.label ?? c

export interface ProjectBudget {
  version: number | null
  effectiveDate?: string | null
  totalPlannedCost?: number | null
  lines: {
    category: BudgetCategory; planned: number | null; notes?: string | null
    committed: number; cash: number; recognised: number
    varianceCommitted: number | null; varianceCash: number | null; varianceRecognised: number | null
  }[]
  alerts: { category: string; overBy: number; message: string }[]
  versions: { version: number; createdBy?: string | null; createdAt: string; total: number | null }[]
}

export type MilestoneStatus = "Planned" | "InProgress" | "Completed" | "Missed" | "Cancelled"
export interface ProjectMilestone {
  milestoneId: number; name: string; description?: string | null
  plannedDate?: string | null; completedDate?: string | null; status: MilestoneStatus; isLate: boolean
  responsibleStaffId?: number | null; responsibleName?: string | null
  amount?: number | null; billingReference?: string | null; notes?: string | null
}

/** One project's part of a transaction (or line). Give ONE of share / amount / quantity. */
export interface ProjectSplit {
  projectId: number
  share?: number
  amount?: number
  quantity?: number
  costClass?: CostClass
}

/**
 * What a save sends as "projects" (483, saved in the same statement as the transaction):
 *   { projectId }            the whole transaction to one project (null = General company activity)
 *   { lines: [...] }         per line, in line order (null = General)
 *   { splits: [...] }        several projects for one non-line transaction
 */
export type ProjectAssignment =
  | { projectId: number | null; costClass?: CostClass }
  | { lines: (ProjectSplit[] | null)[] }
  | { splits: ProjectSplit[] }

export interface AllocationView {
  sourceType: string
  sourceId: number
  active: { lineId: number | null; projectId: number; projectLabel: string; share: number; basis: string; enteredValue: number | null; costClass: CostClass; createdBy?: string | null; createdAt: string }[]
  history: { lineId: number | null; projectId: number; projectLabel: string; share: number; costClass: CostClass; status: "Active" | "Superseded"; reason?: string | null; createdBy?: string | null; createdAt: string; supersededBy?: string | null; supersededAt?: string | null; supersededReason?: string | null }[]
}

export type LinkDocumentType = "Sale" | "Purchase" | "Expense" | "OwnerEntry" | "Loan" | "PayrollRun" | "CapitalAsset"
export interface LinkCandidate {
  documentType: LinkDocumentType; documentId: number; date: string; ref: string; party?: string | null
  amount: number; status: string; detail?: string | null; projects: { projectId: number; label: string }[]
}

export interface ReconcileResult {
  pnl: { section: string; company: number; projects: number; general: number; difference: number }[]
  cash: { company: number; projects: number; general: number; difference: number }
  balanced: boolean
}

// ---------------------------------------------------------------- plumbing

const base = (farmId?: string) => `/generic-company/${encodeURIComponent(farmId ?? getUserContext().farmId ?? "")}`

async function call<T>(method: string, path: string, body?: unknown): Promise<T> {
  const res = await fetch(farmApiUrl(path), {
    method,
    headers: getAuthHeaders(),
    ...(body === undefined ? {} : { body: JSON.stringify({ ...(body as object), farmId: getUserContext().farmId }) }),
  })
  if (!res.ok) {
    const text = await res.text().catch(() => "")
    throw new Error(explainHttpError(method, path, res.status, text))
  }
  if (res.status === 204) return undefined as T
  const text = await res.text()
  return (text ? JSON.parse(text) : undefined) as T
}

const qs = (o: Record<string, string | number | boolean | null | undefined>) => {
  const p = new URLSearchParams()
  for (const [k, v] of Object.entries(o)) if (v !== undefined && v !== null && v !== "") p.append(k, String(v))
  const s = p.toString()
  return s ? `?${s}` : ""
}

// ---------------------------------------------------------------- register

export const listProjects = (f: { search?: string; status?: string; kind?: string; customerId?: number; page?: number; pageSize?: number } = {}) =>
  call<ProjectPage>("GET", `${base()}/projects${qs(f)}`)

/** For pickers. includeClosed adds Completed/Cancelled (report filters, linking). */
export const getProjectOptions = (includeClosed = false) =>
  call<ProjectOption[]>("GET", `${base()}/projects/options${qs({ includeClosed })}`)

export const getProject = (id: number) => call<GenericProject>("GET", `${base()}/projects/${id}`)
export const createProject = (p: ProjectInput) => call<GenericProject>("POST", `${base()}/projects`, p)
export const updateProject = (id: number, p: ProjectInput) => call<GenericProject>("PUT", `${base()}/projects/${id}`, p)
export const setProjectStatus = (id: number, status: string, note?: string) =>
  call<GenericProject>("PUT", `${base()}/projects/${id}/status`, { status, note })
export const archiveProject = (id: number, note?: string) =>
  call<void>("DELETE", `${base()}/projects/${id}${qs({ note })}`)
export const restoreProject = (id: number) => call<GenericProject>("PUT", `${base()}/projects/${id}/restore`, {})

// ---------------------------------------------------------------- financials

type Range = { fromDate?: string; toDate?: string }

export const getProjectSummary = (id: number, r: Range = {}) =>
  call<ProjectSummary>("GET", `${base()}/projects/${id}/financials/summary${qs(r)}`)
export const getProjectCashFlow = (id: number, r: Range = {}) =>
  call<ProjectCashFlow>("GET", `${base()}/projects/${id}/financials/cashflow${qs(r)}`)
export const getProjectTransactions = (id: number, r: Range = {}) =>
  call<ProjectTransactions>("GET", `${base()}/projects/${id}/financials/transactions${qs(r)}`)
export const compareProjects = (ids: number[] | null, r: Range = {}) =>
  call<{ projects: ProjectSummary[]; general: ProjectSummary | null }>(
    "GET", `${base()}/projects/financials/compare${qs({ ids: ids?.join(","), ...r })}`)
export const reconcileProjects = (r: Range = {}) =>
  call<ReconcileResult>("GET", `${base()}/projects/financials/reconcile${qs(r)}`)
/** Cash flow for a report filter value (see ProjectFilterValue). */
export const getScopedCashFlow = (project: string, r: Range = {}) =>
  call<ProjectCashFlow>("GET", `${base()}/projects/financials/cashflow${qs({ project, ...r })}`)

// ---------------------------------------------------------------- assignment

export const getAllocations = (sourceType: string, sourceId: number) =>
  call<AllocationView>("GET", `${base()}/project-allocations${qs({ sourceType, sourceId })}`)

/** Reassign a whole document (corrections). Never creates or changes the transaction. */
export const reassignDocument = (documentType: string, documentId: number, projectId: number | null, reason?: string, costClass?: CostClass) =>
  call<AllocationView>("PUT", `${base()}/project-allocations`, { documentType, documentId, projectId, costClass, reason })

/** Change the split of one source (line). */
export const setSplit = (sourceType: string, sourceId: number, lineId: number | null, splits: ProjectSplit[], reason?: string) =>
  call<AllocationView>("PUT", `${base()}/project-allocations`, { sourceType, sourceId, lineId, splits, reason })

export const setLineSplits = (documentType: "Sale" | "Purchase", documentId: number, lines: (ProjectSplit[] | null)[], reason?: string) =>
  call<AllocationView>("PUT", `${base()}/project-allocations`, { documentType, documentId, lines, reason })

/** Which projects each of many documents belongs to (list columns). */
export const getProjectLabels = (sourceType: string, ids?: number[]) =>
  call<{ sourceId: number; projects: { projectId: number; label: string }[] }[]>(
    "GET", `${base()}/project-allocations/labels${qs({ sourceType, ids: ids?.join(",") })}`)

/** 493: Financial Activity -- each event in the period that belongs (partly) to a project. */
export const getActivityShares = (fromDate: string, toDate: string) =>
  call<{ eventKey: string; projects: { projectId: number; share: number }[] }[]>(
    "GET", `${base()}/project-allocations/activity-shares${qs({ fromDate, toDate })}`)

/** 493: one open document behind a customer / supplier balance, with its project shares. */
export interface ProjectOpenBalance {
  partyId: number
  documentType: string
  documentId: number
  documentDate: string
  amountPaid: number
  balance: number
  dueDate?: string | null
  isOverdue: boolean
  projects: { projectId: number; share: number }[]
}
export const getProjectOpenBalances = (side: "customer" | "supplier") =>
  call<ProjectOpenBalance[]>("GET", `${base()}/project-allocations/open-balances${qs({ side })}`)

export const getLinkCandidates =(f: { documentType: LinkDocumentType; fromDate?: string; toDate?: string; search?: string; onlyUnassigned?: boolean }) =>
  call<LinkCandidate[]>("GET", `${base()}/project-allocations/link-candidates${qs(f)}`)
export const previewLink = (projectId: number, items: { documentType: LinkDocumentType; documentId: number }[]) =>
  call<{ before: ProjectSummary; adds: { revenue: number; costs: number; ownerFunding: number; purchaseValue: number }; note: string }>(
    "POST", `${base()}/project-allocations/link-preview`, { projectId, items })
export const linkDocuments = (projectId: number, items: { documentType: LinkDocumentType; documentId: number }[], reason?: string) =>
  call<{ linked: number }>("PUT", `${base()}/project-allocations/link`, { projectId, items, reason })

// ---------------------------------------------------------------- stock reservations

export const getProjectInventory = (id: number) => call<ProjectInventory>("GET", `${base()}/projects/${id}/reservations`)
export const reserveStock = (id: number, r: { productId: number; action: "Reserve" | "Release" | "Transfer"; quantity: number; toProjectId?: number; date?: string; note?: string }) =>
  call<ProjectInventory>("POST", `${base()}/projects/${id}/reservations`, r)
export const undoReservation = (id: number, entryId: number, reason: string) =>
  call<ProjectInventory>("POST", `${base()}/projects/${id}/reservations/${entryId}/undo`, { reason })
export const getReservedStock = () =>
  call<{ productId: number; reserved: number; projects: { projectId: number; label: string; remaining: number }[] }[]>(
    "GET", `${base()}/project-reservations`)

// ---------------------------------------------------------------- budget + milestones

export const getProjectBudget = (id: number) => call<ProjectBudget>("GET", `${base()}/projects/${id}/budget`)
export const saveProjectBudget = (id: number, lines: { category: BudgetCategory; plannedAmount: number; notes?: string }[], effectiveDate?: string) =>
  call<ProjectBudget>("PUT", `${base()}/projects/${id}/budget`, { lines, effectiveDate })
export const setExpenseCategoryBudget = (categoryId: number, budgetCategory: string | null) =>
  call<void>("PUT", `${base()}/projects/budget-categories/${categoryId}`, { budgetCategory })

export const getMilestones = (id: number) => call<ProjectMilestone[]>("GET", `${base()}/projects/${id}/milestones`)
export const saveMilestone = (id: number, m: Partial<ProjectMilestone> & { name: string }) =>
  m.milestoneId
    ? call<ProjectMilestone[]>("PUT", `${base()}/projects/${id}/milestones/${m.milestoneId}`, m)
    : call<ProjectMilestone[]>("POST", `${base()}/projects/${id}/milestones`, m)
export const deleteMilestone = (id: number, milestoneId: number) =>
  call<void>("DELETE", `${base()}/projects/${id}/milestones/${milestoneId}`)

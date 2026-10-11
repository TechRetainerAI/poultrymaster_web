// PROMPT 2: typed client for the Farm API's platform-admin analytics endpoints
// (api/PlatformActivity — the Prompt 1 normalized activity foundation).
// All requests require the same SystemAdmin/PlatformOwner JWT as the directory.

import { farmApiBase } from "./api"

export type TrendDto = {
  currentPeriodCount: number
  previousPeriodCount: number
  percentChange: number | null
  status: "NewActivity" | "Increasing" | "Stable" | "Declining" | "Inactive"
}

export type CompanySummary = {
  companyId: string
  companyName: string
  companyFamily?: string | null
  businessTemplateCode?: string | null
  organizationId?: string | null
  timeZoneId?: string | null
  createdAtUtc?: string | null
  firstMeaningfulActivityAtUtc?: string | null
  planCode?: string | null
  billingParticipation?: string | null
  lastMeaningfulActivityAtUtc?: string | null
  lastActivityAtUtc?: string | null
  meaningfulActivityCountToday: number
  meaningfulActivityCount7d: number
  meaningfulActivityCount30d: number
  activeDays7d: number
  activeDays30d: number
  activeUsers7d: number
  activeUsers30d: number
  activityStatus: ActivityStatus
  trend: TrendDto
  categoryBreakdown: CategoryCount[]
  failedRequests7d: number
  health?: string | null
  healthReasons: string[]
  setupPercent: number
  requiredMilestonesComplete: number
  requiredMilestonesTotal: number
  missingMilestones: string[]
  activated: boolean
  timeToActivationDays?: number | null
}

export type ActivityStatus = "NoActivity" | "ActiveToday" | "Active7Days" | "Active30Days" | "Inactive30Plus"

export type OrganizationSummary = {
  organizationId: string
  organizationName?: string | null
  ownerEmail?: string | null
  orgCode?: string | null
  countryCode?: string | null
  companyCount: number
  activeCompanies30d: number
  firstCompanyCreatedAtUtc?: string | null
  firstMeaningfulActivityAtUtc?: string | null
  lastMeaningfulActivityAtUtc?: string | null
  meaningfulActivityCount30d: number
  activeUsers30d: number
  activityStatus: ActivityStatus
  trend: TrendDto
  subscriptionStatus: string
  hasPastDueInvoice: boolean
  trialEndUtc?: string | null
  setupPercent: number
  health?: string | null
  healthReasons: string[]
  hasRecentFailedPayment: boolean
  attention: string[]
  companies: CompanySummary[]
}

export type CategoryCount = { key: string; meaningfulCount: number; totalCount: number }

export type TimePoint = { businessDate: string; meaningfulCount: number; totalCount: number; activeUsers: number }

export type RecentActivity = {
  id: number
  organizationId?: string | null
  companyId?: string | null
  companyName?: string | null
  companyFamily?: string | null
  userId?: string | null
  category: string
  activityType: string
  sourceModule: string
  sourceRecordId?: string | null
  occurredAtUtc: string
  businessDate?: string | null
  isMeaningful: boolean
  source: string
}

export type Overview = {
  windowDays: number
  meaningfulEvents: number
  totalEvents: number
  companiesActiveToday: number
  companiesActive7d: number
  companiesActive30d: number
  companiesInactive30Plus: number
  totalCompanies: number
  totalOrganizations: number
  activeUsers7d: number
  activeUsers30d: number
  newOrganizationsThisMonth: number
  trialOrganizations: number
  payingOrganizations: number
  pastDueOrganizations: number
  trend: TrendDto
  byCategory: CategoryCount[]
  byCompanyFamily: CategoryCount[]
  byBusinessTemplate: CategoryCount[]
}

export type GoingQuietRow = {
  companyId: string
  companyName: string
  companyFamily?: string | null
  organizationId?: string | null
  organizationName?: string | null
  baselineMeaningfulCount: number
  recentMeaningfulCount: number
  lastMeaningfulActivityAtUtc?: string | null
}

export type NewCustomerRow = {
  organizationId: string
  organizationName?: string | null
  registeredAtUtc?: string | null
  firstCompanyId?: string | null
  firstCompanyName?: string | null
  firstCompanyFamily?: string | null
  firstMeaningfulActivityAtUtc?: string | null
  setupPercent: number
  subscriptionStatus: string
  trialEndUtc?: string | null
}

export type ModuleAdoptionRow = {
  category: string
  companyFamily: string
  meaningfulCount: number
  activeCompanies: number
}

async function get<T>(token: string, path: string): Promise<T> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformActivity/${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 401 || res.status === 403) {
    throw new Error("Farm API denied this token (needs SystemAdmin or PlatformOwner).")
  }
  if (!res.ok) {
    const t = await res.text()
    throw new Error(t || `Platform activity request failed (${res.status})`)
  }
  return (await res.json()) as T
}

export const fetchOverview = (token: string, days = 30) => get<Overview>(token, `overview?days=${days}`)
export const fetchOrganizations = (token: string) => get<OrganizationSummary[]>(token, "organizations")
export const fetchTimeSeries = (token: string, days: number, family?: string | null, organizationId?: string | null, companyId?: string | null) =>
  get<TimePoint[]>(token, `timeseries?days=${days}`
    + (family ? `&companyFamily=${encodeURIComponent(family)}` : "")
    + (organizationId ? `&organizationId=${encodeURIComponent(organizationId)}` : "")
    + (companyId ? `&companyId=${encodeURIComponent(companyId)}` : ""))
export const fetchRecent = (token: string, limit = 25) => get<RecentActivity[]>(token, `recent?limit=${limit}`)
export const fetchGoingQuiet = (token: string) => get<GoingQuietRow[]>(token, "going-quiet")
export const fetchNewCustomers = (token: string, days = 31) => get<NewCustomerRow[]>(token, `new-customers?days=${days}`)
export const fetchModuleAdoption = (token: string, days = 30) => get<ModuleAdoptionRow[]>(token, `module-adoption?days=${days}`)

// ---- shared formatting helpers for the admin pages ----

export function timeAgo(iso?: string | null): string {
  if (!iso) return "—"
  const ms = Date.now() - +new Date(iso)
  if (Number.isNaN(ms)) return "—"
  if (ms < 0) return "just now"
  const mins = Math.floor(ms / 60000)
  if (mins < 1) return "just now"
  if (mins < 60) return `${mins} min${mins === 1 ? "" : "s"} ago`
  const hours = Math.floor(mins / 60)
  if (hours < 24) return `${hours} hour${hours === 1 ? "" : "s"} ago`
  const days = Math.floor(hours / 24)
  if (days < 60) return `${days} day${days === 1 ? "" : "s"} ago`
  const months = Math.floor(days / 30)
  return `${months} month${months === 1 ? "" : "s"} ago`
}

/** "Production posted", "Sale recorded" — ActivityType in plain words. */
export function describeActivity(type: string): string {
  const spaced = type.replace(/([a-z0-9])([A-Z])/g, "$1 $2")
  return spaced.charAt(0).toUpperCase() + spaced.slice(1).toLowerCase()
}

export const FAMILIES = ["Poultry", "Water", "Hotel", "Restaurant", "Generic"] as const

export function statusLabel(s: ActivityStatus): string {
  switch (s) {
    case "ActiveToday": return "Active today"
    case "Active7Days": return "Active 7d"
    case "Active30Days": return "Active 30d"
    case "Inactive30Plus": return "Inactive 30+"
    default: return "No activity"
  }
}

export function statusTone(s: ActivityStatus): "green" | "teal" | "amber" | "red" | "slate" {
  switch (s) {
    case "ActiveToday": return "green"
    case "Active7Days": return "teal"
    case "Active30Days": return "amber"
    case "Inactive30Plus": return "red"
    default: return "slate"
  }
}

// ---- Prompt 3: Customer Health / Needs Attention ----

export type AttentionNote = { id: number; note: string; createdBy: string; createdAtUtc: string }

export type AttentionItem = {
  id: number
  organizationId: string
  organizationName?: string | null
  companyId?: string | null
  companyName?: string | null
  attentionType: string
  severity: "High" | "Medium" | "Low"
  title: string
  reason: string
  sourceRule: string
  status: "Open" | "Assigned" | "Contacted" | "Resolved" | "Dismissed"
  assignedToUserId?: string | null
  assignedToName?: string | null
  followUpAtUtc?: string | null
  detectedAtUtc: string
  lastDetectedAtUtc: string
  resolvedAtUtc?: string | null
  resolvedBy?: string | null
  resolutionNote?: string | null
  revenueAtRisk?: number | null
  notes: AttentionNote[]
}

async function healthCall<T>(token: string, path: string, method = "GET", body?: unknown): Promise<T> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformHealth/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 401 || res.status === 403) {
    throw new Error("Farm API denied this token (needs SystemAdmin or PlatformOwner).")
  }
  const data = (await res.json().catch(() => ({}))) as T & { message?: string }
  if (!res.ok) throw new Error((data as { message?: string }).message || `Request failed (${res.status})`)
  return data
}

export const fetchAttentionQueue = (token: string, status?: string, refresh = true) =>
  healthCall<AttentionItem[]>(token, `queue?refresh=${refresh}${status ? `&status=${encodeURIComponent(status)}` : ""}`)
export const runHealthSweep = (token: string) =>
  healthCall<{ organizationsEvaluated: number; itemsUpserted: number; itemsAutoResolved: number }>(token, "evaluate", "POST")
export const attentionAssign = (token: string, id: number, userId?: string, name?: string) =>
  healthCall<AttentionItem>(token, `items/${id}/assign`, "POST", { userId, name })
export const attentionContacted = (token: string, id: number) =>
  healthCall<AttentionItem>(token, `items/${id}/contacted`, "POST")
export const attentionNote = (token: string, id: number, note: string) =>
  healthCall<AttentionItem>(token, `items/${id}/notes`, "POST", { note })
export const attentionFollowUp = (token: string, id: number, followUpAtUtc: string | null) =>
  healthCall<AttentionItem>(token, `items/${id}/follow-up`, "POST", { followUpAtUtc })
export const attentionResolve = (token: string, id: number, note?: string) =>
  healthCall<AttentionItem>(token, `items/${id}/resolve`, "POST", { note })
export const attentionDismiss = (token: string, id: number, note: string) =>
  healthCall<AttentionItem>(token, `items/${id}/dismiss`, "POST", { note })

export const HEALTH_LEVELS = ["Healthy", "Needs Attention", "At Risk", "Inactive", "New"] as const

export function healthTone(h?: string | null): "green" | "amber" | "red" | "slate" | "teal" {
  switch (h) {
    case "Healthy": return "green"
    case "Needs Attention": return "amber"
    case "At Risk": return "red"
    case "Inactive": return "red"
    case "New": return "teal"
    default: return "slate"
  }
}

// ---- Prompt 4: onboarding / adoption / retention ----

export type Milestone = { code: string; title: string; weight: number; required: boolean; sortOrder: number; complete: boolean }
export type FunnelStage = { key: string; label: string; count: number; percentOfPrevious: number | null; percentOfTop: number }
export type FeatureAdoptionRow = { feature: string; companyFamily: string; companiesUsed: number; companiesTotal: number; percent: number }
export type FeatureUsageRow = {
  feature: string; companyId?: string | null; companyName?: string | null
  firstUsedAtUtc?: string | null; lastUsedAtUtc?: string | null; usageCount: number; activeDaysUsingFeature: number
}
export type RetentionCohort = { cohort: string; subjects: number; retained: number[]; percent: (number | null)[] }

async function analyticsGet<T>(token: string, path: string): Promise<T> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformAnalytics/${path}`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 401 || res.status === 403) throw new Error("Farm API denied this token (needs SystemAdmin or PlatformOwner).")
  if (!res.ok) throw new Error((await res.text()) || `Analytics request failed (${res.status})`)
  return (await res.json()) as T
}

export const fetchOnboarding = (token: string, family?: string, template?: string, country?: string) =>
  analyticsGet<CompanySummary[]>(token, `onboarding?x=1${family ? `&companyFamily=${encodeURIComponent(family)}` : ""}${template ? `&template=${encodeURIComponent(template)}` : ""}${country ? `&country=${encodeURIComponent(country)}` : ""}`)
export const fetchMilestones = (token: string, companyId: string) =>
  analyticsGet<Milestone[]>(token, `milestones/${encodeURIComponent(companyId)}`)
export const fetchFunnel = (token: string, month?: string, family?: string, template?: string, country?: string) =>
  analyticsGet<FunnelStage[]>(token, `funnel?x=1${month ? `&month=${encodeURIComponent(month)}` : ""}${family ? `&companyFamily=${encodeURIComponent(family)}` : ""}${template ? `&template=${encodeURIComponent(template)}` : ""}${country ? `&country=${encodeURIComponent(country)}` : ""}`)
export const fetchFeatureAdoption = (token: string, days = 90) =>
  analyticsGet<FeatureAdoptionRow[]>(token, `feature-adoption?days=${days}`)
export const fetchFeatureUsage = (token: string, companyId?: string) =>
  analyticsGet<FeatureUsageRow[]>(token, `feature-usage${companyId ? `?companyId=${encodeURIComponent(companyId)}` : ""}`)
export const fetchRetention = (token: string, scope: "org" | "company", cohortBy: string, family?: string) =>
  analyticsGet<RetentionCohort[]>(token, `retention?scope=${scope}&cohortBy=${cohortBy}${family ? `&companyFamily=${encodeURIComponent(family)}` : ""}`)

// ---- Prompt 5: Customer Success CRM / 360 ----

export type TimelineEvent = {
  atUtc: string; kind: string; title: string; detail?: string | null
  companyId?: string | null; companyName?: string | null; actor?: string | null
}
export type CrmNote = {
  id: number; organizationId: string; companyId?: string | null; companyName?: string | null
  category: string; contactType?: string | null; note: string
  followUpAtUtc?: string | null; assignedToName?: string | null; outcome?: string | null
  attentionItemId?: number | null; createdBy: string; createdAtUtc: string
}
export type ProductFeedback = {
  id: number; organizationId: string; companyId?: string | null; companyName?: string | null
  companyFamily?: string | null; category: string; module?: string | null; severity: string
  title: string; detail?: string | null; status: string; createdBy: string; createdAtUtc: string
}
export type CancellationReason = {
  id: number; organizationId: string; reasonCode: string; note?: string | null
  createdBy: string; createdAtUtc: string
}
export type VerticalSummary = { companyId: string; companyFamily?: string | null; items: { label: string; value: string }[] }
export type OrgActivitySummary = {
  windows: { days: number; meaningfulCount: number; activeDays: number; activeUsers: number }[]
  topCategories: CategoryCount[]
  nextBillingUtc?: string | null
}

async function crmCall<T>(token: string, path: string, method = "GET", body?: unknown): Promise<T> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformCrm/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 401 || res.status === 403) throw new Error("Farm API denied this token (needs SystemAdmin or PlatformOwner).")
  const data = (await res.json().catch(() => ({}))) as T & { message?: string }
  if (!res.ok) throw new Error((data as { message?: string }).message || `CRM request failed (${res.status})`)
  return data
}

export const fetchTimeline = (token: string, organizationId: string, companyId?: string) =>
  crmCall<TimelineEvent[]>(token, `timeline?organizationId=${encodeURIComponent(organizationId)}${companyId ? `&companyId=${encodeURIComponent(companyId)}` : ""}`)
export const fetchCrmNotes = (token: string, organizationId?: string, companyId?: string) =>
  crmCall<CrmNote[]>(token, `notes?x=1${organizationId ? `&organizationId=${encodeURIComponent(organizationId)}` : ""}${companyId ? `&companyId=${encodeURIComponent(companyId)}` : ""}`)
export const addCrmNote = (token: string, req: {
  organizationId: string; companyId?: string; category: string; contactType?: string
  note: string; followUpAtUtc?: string | null; assignedToName?: string; attentionItemId?: number
}) => crmCall<CrmNote>(token, "notes", "POST", req)
export const setCrmNoteOutcome = (token: string, id: number, outcome: string) =>
  crmCall<CrmNote>(token, `notes/${id}/outcome`, "POST", { note: outcome })
export const fetchCrmFeedback = (token: string, organizationId?: string) =>
  crmCall<ProductFeedback[]>(token, `feedback${organizationId ? `?organizationId=${encodeURIComponent(organizationId)}` : ""}`)
export const addCrmFeedback = (token: string, req: {
  organizationId: string; companyId?: string; companyFamily?: string
  category: string; module?: string; severity: string; title: string; detail?: string
}) => crmCall<ProductFeedback>(token, "feedback", "POST", req)
export const fetchCancellationReasons = (token: string, organizationId?: string) =>
  crmCall<CancellationReason[]>(token, `cancellation-reasons${organizationId ? `?organizationId=${encodeURIComponent(organizationId)}` : ""}`)
export const addCancellationReason = (token: string, req: { organizationId: string; reasonCode: string; note?: string }) =>
  crmCall<CancellationReason>(token, "cancellation-reasons", "POST", req)
export const fetchVerticalSummary = (token: string, companyId: string) =>
  crmCall<VerticalSummary>(token, `vertical-summary/${encodeURIComponent(companyId)}`)
export const fetchOrgActivitySummary = (token: string, organizationId: string) =>
  crmCall<OrgActivitySummary>(token, `organization-activity/${encodeURIComponent(organizationId)}`)

export const NOTE_CATEGORIES = ["Support", "Sales", "Onboarding", "Billing", "Product Feedback", "General"] as const
export const CONTACT_TYPES = ["Called", "Emailed", "WhatsApp", "Meeting", "Demo", "Training"] as const
export const CANCELLATION_REASONS = ["TooExpensive", "MissingFeature", "HardToUse", "BusinessClosed", "TemporaryPause", "Competitor", "SupportIssue", "Other"] as const

// ---- Prompt 6: revenue intelligence ----

export type MoneyByCurrency = { currencyCode: string; amount: number }
export type RevenueCurrencyBlock = {
  currencyCode: string; marketCode: string
  mrr: number; grossMrr: number; arr: number
  payingOrganizations: number; payingCompanies: number
  arpo: number | null; arpc: number | null
  newMrr: number; expansionMrr: number; contractionMrr: number; churnedMrr: number
  pastDueAmount: number; failedPaymentsAmount30d: number; failedPaymentsCount30d: number
  discountsGrantedThisMonth: number; creditsIssuedOutstanding: number; trialPotentialMrr: number
}
export type OrgRevenueRow = {
  organizationId: string; organizationName?: string | null
  currencyCode: string; marketCode: string; accountStatus: string; billingCycle: string
  grossMrr: number; netMrr: number; payingCompanies: number
  health?: string | null; lastMeaningfulActivityAtUtc?: string | null
  activityTrendPercent?: number | null; revenueAtRisk: number; riskReasons: string[]
  nextRenewalUtc?: string | null
}
export type VerticalRevenueRow = {
  companyFamily: string; businessTemplate?: string | null; currencyCode: string
  mrr: number; companies: number; averagePrice: number | null; shareOfCurrencyMrr: number
}
export type TrialIntelligence = {
  organizationsInTrial: number; trialEnding7d: number; trialEnding30d: number
  convertedThisMonth: number; trialToPaidConversionRate: number | null; averageDaysToConversion: number | null
  highEngagementTrialsNotPaid: OrgRevenueRow[]; lowEngagementTrialsEndingSoon: OrgRevenueRow[]
}
export type RenewalRow = {
  organizationId: string; organizationName?: string | null; renewalAtUtc: string
  billingCycle: string; amount: number; currencyCode: string; health?: string | null; paymentState: string
}
export type AccountDiscountRow = {
  organizationId: string; organizationName?: string | null; name: string; discountType: string
  value: number; lastInvoicePercent: number | null; endDate?: string | null
}
export type DiscountIntelligence = {
  grantedThisMonth: MoneyByCurrency[]; grantedLast90d: MoneyByCurrency[]
  activeAutomaticMultiCompany: number; activePromotionalDiscounts: number; activeCustomerSpecificDiscounts: number
  largestDiscountAccounts: AccountDiscountRow[]; expiringDiscounts: AccountDiscountRow[]
}
export type CreditIntelligence = {
  issued: MoneyByCurrency[]; consumed: MoneyByCurrency[]; outstanding: MoneyByCurrency[]
  byReason: { reason: string; currencyCode: string; amount: number; count: number }[]
}
export type BillingExceptionRow = {
  kind: string; organizationId: string; organizationName?: string | null
  companyId?: string | null; companyName?: string | null; detail: string
}
export type RevenueDashboard = {
  mrrDefinition: string
  byCurrency: RevenueCurrencyBlock[]
  byVertical: VerticalRevenueRow[]
  organizations: OrgRevenueRow[]
  revenueAtRisk: OrgRevenueRow[]
  trials: TrialIntelligence
  renewals30d: RenewalRow[]
  discounts: DiscountIntelligence
  credits: CreditIntelligence
  exceptions: BillingExceptionRow[]
  recoveredPayments30d: MoneyByCurrency[]
  generatedAtUtc: string
}

export async function fetchRevenueDashboard(token: string): Promise<RevenueDashboard> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformRevenue/dashboard`, {
    headers: { Authorization: `Bearer ${token}`, Accept: "application/json" },
  })
  if (res.status === 401 || res.status === 403) throw new Error("Farm API denied this token (needs SystemAdmin or PlatformOwner).")
  if (!res.ok) throw new Error((await res.text()) || `Revenue request failed (${res.status})`)
  return (await res.json()) as RevenueDashboard
}

export const money = (currency: string, amount: number) =>
  `${currency} ${amount.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`

// ---- Prompt 7: platform operations ----

export type ErrorGroup = { resource: string; operation: string; module: string; count: number; affectedCompanies: number; isCriticalOperation: boolean }
export type ErrorDashboard = {
  windowHours: number; totalErrors: number; affectedOrganizations: number; affectedCompanies: number
  failedBusinessOperations: number; topErrorTypes: ErrorGroup[]
  topModules: CategoryCount[]; byRelease: CategoryCount[]
  dailyTrend: { businessDate: string; meaningfulCount: number; totalCount: number }[]
}
export type CompanyErrors = {
  companyId: string; errors24h: number; errors7d: number; failedOperations7d: number
  recent: { correlationId: string; resource: string; operation: string; summary: string; occurredAtUtc: string }[]
  deepLogsHint: string
}
export type SecurityEvent = {
  id: number; eventType: string; severity: "Info" | "Warning" | "Critical"
  organizationId?: string | null; companyId?: string | null; userId?: string | null
  title: string; detail?: string | null; occurrences: number
  firstSeenAtUtc: string; lastSeenAtUtc: string; status: string
}
export type FlagRule = { scopeType: string; scopeValue: string; enabled: boolean; createdBy: string; createdAtUtc: string }
export type FeatureFlag = {
  id: number; flagKey: string; name: string; description?: string | null
  enabled: boolean; defaultOn: boolean; createdBy: string; createdAtUtc: string; rules: FlagRule[]
}
export type FlagAudit = {
  flagKey: string; action: string; scopeType?: string | null; scopeValue?: string | null
  oldValue?: string | null; newValue?: string | null; changedBy: string; reason?: string | null; atUtc: string
}
export type Release = {
  service: string; version: string; firstSeenAtUtc: string
  totalOpsBefore?: number | null; failedOpsBefore?: number | null
  totalOpsAfter?: number | null; failedOpsAfter?: number | null; affectedCompaniesAfter?: number | null
}
export type SystemHealth = {
  databaseOk: boolean; failedRequests24h: number; totalRequests24h: number
  failedPayments24h: number; lastWebhookAtUtc?: string | null; notes: string[]
}
export type BriefEntry = { label: string; value: string; linkKind: string; linkParam?: string | null }
export type BriefSection = { title: string; entries: BriefEntry[] }
export type ManagementBrief = {
  briefType: string; briefDate: string; generatedAtUtc: string; generatedBy: string
  sections: BriefSection[]; aiSummary?: string | null
}

async function opsCall<T>(token: string, path: string, method = "GET", body?: unknown): Promise<T> {
  const base = farmApiBase()
  if (!base) throw new Error("VITE_FARM_API_URL is not set")
  const res = await fetch(`${base}/api/PlatformOps/${path}`, {
    method,
    headers: {
      Authorization: `Bearer ${token}`,
      Accept: "application/json",
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  })
  if (res.status === 401 || res.status === 403) throw new Error("This token's role is not allowed on this operations surface.")
  const data = (await res.json().catch(() => ({}))) as T & { message?: string }
  if (!res.ok) throw new Error((data as { message?: string }).message || `Ops request failed (${res.status})`)
  return data
}

export const fetchErrorDashboard = (token: string, hours = 24) => opsCall<ErrorDashboard>(token, `errors?hours=${hours}`)
export const fetchCompanyErrors = (token: string, companyId: string) =>
  opsCall<CompanyErrors>(token, `errors/company/${encodeURIComponent(companyId)}`)
export const fetchSecurityEvents = (token: string, refresh = true) =>
  opsCall<SecurityEvent[]>(token, `security-events?refresh=${refresh}`)
export const fetchFlags = (token: string) => opsCall<FeatureFlag[]>(token, "flags")
export const createFlag = (token: string, req: { flagKey: string; name: string; description?: string; defaultOn: boolean; reason?: string }) =>
  opsCall<FeatureFlag>(token, "flags", "POST", req)
export const setFlagEnabled = (token: string, flagKey: string, enabled: boolean, reason?: string) =>
  opsCall<FeatureFlag>(token, `flags/${encodeURIComponent(flagKey)}/enabled`, "POST", { enabled, reason })
export const setFlagRule = (token: string, flagKey: string, req: { scopeType: string; scopeValue?: string; enabled: boolean; reason?: string }) =>
  opsCall<FeatureFlag>(token, `flags/${encodeURIComponent(flagKey)}/rules`, "POST", req)
export const removeFlagRule = (token: string, flagKey: string, scopeType: string, scopeValue: string) =>
  opsCall<FeatureFlag>(token, `flags/${encodeURIComponent(flagKey)}/rules?scopeType=${encodeURIComponent(scopeType)}&scopeValue=${encodeURIComponent(scopeValue)}`, "DELETE")
export const fetchFlagAudit = (token: string, flagKey?: string) =>
  opsCall<FlagAudit[]>(token, `flags/audit${flagKey ? `?flagKey=${encodeURIComponent(flagKey)}` : ""}`)
export const fetchReleases = (token: string) => opsCall<Release[]>(token, "releases")
export const fetchSystemHealth = (token: string) => opsCall<SystemHealth>(token, "system-health")
export const fetchBrief = (token: string, type: "Daily" | "Weekly") => opsCall<ManagementBrief>(token, `briefs/${type}`)
export const generateBrief = (token: string, type: "Daily" | "Weekly") => opsCall<ManagementBrief>(token, `briefs/${type}/generate`, "POST")
export const exportUrl = (dataset: string) => `${farmApiBase()}/api/PlatformOps/export?dataset=${encodeURIComponent(dataset)}`

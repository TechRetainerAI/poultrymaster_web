// Shared employee permission constants used by the Add-Employee dialog
// (components/employees/add-employee-dialog.tsx) and the /employees page's
// edit flow. Keep a single source so the admin/staff option lists stay in sync.

export type AdminPermissionKey =
  | "changeGroupInfo"
  | "deleteMessages"
  | "banUsers"
  | "inviteUsers"
  | "pinMessages"
  | "manageStories"
  | "manageVideoChats"
  | "remainAnonymous"
  | "addNewAdmins"

export const DEFAULT_ADMIN_PERMISSIONS: Record<AdminPermissionKey, boolean> = {
  changeGroupInfo: true,
  deleteMessages: true,
  banUsers: true,
  inviteUsers: true,
  pinMessages: true,
  manageStories: false,
  manageVideoChats: true,
  remainAnonymous: false,
  addNewAdmins: false,
}

export const ADMIN_PERMISSION_OPTIONS: Array<{ key: AdminPermissionKey; label: string; hint?: string }> = [
  { key: "changeGroupInfo", label: "Change group info" },
  { key: "deleteMessages", label: "Delete messages" },
  { key: "banUsers", label: "Ban users" },
  { key: "inviteUsers", label: "Invite users via link" },
  { key: "pinMessages", label: "Pin messages" },
  { key: "manageStories", label: "Manage stories", hint: "0/3 by default" },
  { key: "manageVideoChats", label: "Manage video chats" },
  { key: "remainAnonymous", label: "Remain anonymous" },
  { key: "addNewAdmins", label: "Add new admins" },
]

export type StaffFeaturePermissionKey =
  | "canEnterSales"
  | "canEnterExpenses"
  | "canViewCashLedger"
  | "canSeeEmployees"
  | "canViewReports"
  | "canViewFinancial"
  | "canViewCustomers"
  | "canViewActivityLog"
  | "canViewSettings"
  | "canViewFeedProduction"
  | "canManageFeedProduction"
  | "canViewFeedProductionCost"

export const DEFAULT_STAFF_FEATURE_PERMISSIONS: Record<StaffFeaturePermissionKey, boolean> = {
  canEnterSales: true,
  canEnterExpenses: true,
  canViewCashLedger: true,
  canSeeEmployees: false,
  canViewReports: true,
  canViewFinancial: true,
  canViewCustomers: true,
  canViewActivityLog: true,
  canViewSettings: true,
  canViewFeedProduction: true,
  canManageFeedProduction: true,
  canViewFeedProductionCost: true,
}

export const STAFF_FEATURE_PERMISSION_OPTIONS: Array<{ key: StaffFeaturePermissionKey; label: string }> = [
  { key: "canEnterSales", label: "Enter Sales" },
  { key: "canEnterExpenses", label: "Enter Expenses" },
  { key: "canViewCashLedger", label: "View Cash Ledger" },
  { key: "canSeeEmployees", label: "See Employees" },
  { key: "canViewReports", label: "View reports" },
  { key: "canViewFinancial", label: "View Financial (Cash, Payments umbrella)" },
  { key: "canViewCustomers", label: "View Customers" },
  { key: "canViewActivityLog", label: "View Activity Log" },
  { key: "canViewSettings", label: "View Settings" },
  { key: "canViewFeedProduction", label: "View Feed Production" },
  { key: "canManageFeedProduction", label: "Manage Feed Production (produce, post, reverse)" },
  { key: "canViewFeedProductionCost", label: "View Feed Production Costs" },
]

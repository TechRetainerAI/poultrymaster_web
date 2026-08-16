// Shared vocabulary for the Access Management views. Kept in one place so the
// roles list, the matrix and the people view label the same thing identically.

import type { IamPermission } from "@/lib/api/iam"

/** Matrix columns, in the order an admin reads them: least to most destructive. */
export const ACTIONS = ["view", "create", "edit", "delete", "approve", "export"] as const
export type Action = (typeof ACTIONS)[number]

export const ACTION_LABEL: Record<string, string> = {
  view: "View", create: "Create", edit: "Edit", delete: "Delete", approve: "Approve", export: "Export",
}

export const MODULE_LABEL: Record<string, string> = {
  poultry: "Poultry", water: "Water", generic: "Company", office: "Business Office",
}

export const MODULE_FOR_COMPANY_TYPE: Record<string, string> = {
  Poultry: "poultry", Water: "water", Generic: "generic",
}

export function moduleForCompanyType(type: string | null | undefined): string {
  return MODULE_FOR_COMPANY_TYPE[type ?? ""] ?? "poultry"
}

/** One matrix row: a resource, and the catalog entry for each action it supports. */
export type MatrixRow = {
  group: string
  resource: string
  label: string
  description: string | null
  actions: Map<string, IamPermission>
}

/**
 * Fold the catalog for one module into group → resource → actions.
 *
 * Resources deliberately do not all support every action — a report cannot be
 * approved — so a missing entry means "not applicable", which the matrix renders
 * differently from "not granted".
 */
export function buildMatrix(catalog: IamPermission[], module: string): { group: string; rows: MatrixRow[] }[] {
  const byResource = new Map<string, MatrixRow>()
  for (const p of catalog) {
    if (p.module !== module) continue
    const existing = byResource.get(p.resource)
    if (existing) { existing.actions.set(p.action, p); continue }
    byResource.set(p.resource, {
      group: p.permissionGroup, resource: p.resource, label: p.resourceLabel,
      description: p.description, actions: new Map([[p.action, p]]),
    })
  }

  const groups = new Map<string, MatrixRow[]>()
  for (const row of byResource.values()) {
    const list = groups.get(row.group) ?? []
    list.push(row)
    groups.set(row.group, list)
  }
  return Array.from(groups.entries()).map(([group, rows]) => ({ group, rows }))
}

/** "2026-08-14" from a date input → an ISO instant the API can store. */
export function dateInputToIso(value: string): string | null {
  if (!value) return null
  const d = new Date(`${value}T23:59:59`)
  return Number.isNaN(d.getTime()) ? null : d.toISOString()
}

export function formatDate(value: string | null | undefined): string {
  if (!value) return ""
  const d = new Date(value)
  return Number.isNaN(d.getTime()) ? "" : d.toLocaleDateString()
}

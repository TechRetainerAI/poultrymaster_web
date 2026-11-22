// Who can be an animal's mother or father.
//
// A mother is a female, or an animal whose sex was never recorded (so a dam
// can still be picked before her sex is fixed). A father must be a male. That
// keeps one animal out of both lists. A parent must also have been born at
// least one pregnancy (the species' gestation) before the young one; with no
// gestation known, simply before it. Animals no longer on the farm stay
// pickable: a dead ewe is still the mother.

import type { AnimalSex, AnimalStatus } from "@/lib/api/livestock"

export type ParentRole = "mother" | "father"

export interface ParentCandidate {
  animalId: number
  sex: AnimalSex
  birthDate: string | null
  status: AnimalStatus
  groupId: number
}

export function fitsRole(a: Pick<ParentCandidate, "sex">, role: ParentRole): boolean {
  return role === "mother" ? a.sex !== "Male" : a.sex === "Male"
}

const day = (iso: string) => Math.floor(Date.parse(`${iso.slice(0, 10)}T00:00:00Z`) / 86_400_000)

/** Why this animal cannot be the parent of a young one born on childBirth, or null when it can. */
export function parentProblem(
  parent: Pick<ParentCandidate, "sex" | "birthDate">,
  role: ParentRole,
  childBirth: string | null | undefined,
  gestationDays: number | null | undefined,
): string | null {
  if (!fitsRole(parent, role)) return role === "mother" ? "is recorded as male" : "is not recorded as male"
  if (!childBirth || !parent.birthDate) return null
  const gap = day(childBirth) - day(parent.birthDate)
  if (Number.isNaN(gap)) return null
  if (gap === 0) return "has the same birth date as this animal"
  if (gap < 0) return "was born after this animal"
  if (gestationDays && gap < gestationDays) return "is too young to be its parent"
  return null
}

/** Order for the picker: on the farm in the young one's group, on the farm elsewhere, then gone. */
export function parentRank(a: Pick<ParentCandidate, "status" | "groupId">, groupId: number | null | undefined): number {
  if (a.status !== "Active") return 2
  return groupId != null && a.groupId === groupId ? 0 : 1
}

import type { BreedingEvent, CashAccountType, LossReason, MovementType, Purchase, SaleLine, Treatment } from "@/lib/api/livestock"
import { fmtNum } from "./livestock-page"

/** How a head-ledger movement reads on a page. */
export const MOVEMENT_LABEL: Record<MovementType, string> = {
  Opening: "Already on farm", Intake: "Came in", Birth: "Born", TransferIn: "Moved in",
  Death: "Died", Cull: "Culled", Sale: "Sold", TransferOut: "Moved out", Correction: "Count correction",
}

/** One line for a breeding event, in the species' own words. */
export function breedingSummary(e: BreedingEvent): { what: string; details: string } {
  const young = (e.youngTerm ?? "young").toLowerCase()
  switch (e.eventType) {
    case "Mating":
      return { what: "Mated", details: [e.sireTag && `with ${e.sireTag}`, e.method === "AI" && "AI",
        e.expectedBirth && `due ${new Date(e.expectedBirth + "T00:00:00").toLocaleDateString()}`].filter(Boolean).join(" · ") }
    case "PregnancyCheck":
      return { what: "Pregnancy check", details: e.result === "Pregnant" ? "Pregnant" : "Not pregnant" }
    case "Birth":
      return { what: e.birthTerm ?? "Birth", details: `${e.bornAlive ?? 0} ${young} alive${e.bornDead ? `, ${e.bornDead} dead` : ""}${e.groupName ? ` · into ${e.groupName}` : ""}` }
    case "Weaning":
      return { what: "Weaning", details: `${e.weanedCount ?? 0} ${young}${e.toGroupName ? ` · moved to ${e.toGroupName}` : ""}` }
    case "Loss":
      return { what: "Lost pregnancy", details: e.notes ?? "" }
  }
}

/** A treatment campaign's status badge. */
export const TREATMENT_STATUS: Record<Treatment["status"], { label: string; cls: string }> = {
  Scheduled: { label: "Not started", cls: "bg-stone-400" },
  InProgress: { label: "In progress", cls: "bg-amber-600" },
  Completed: { label: "Completed", cls: "bg-emerald-600" },
  Cancelled: { label: "Cancelled", cls: "bg-rose-600" },
}

export const ACCOUNT_TYPE_LABEL: Record<CashAccountType, string> = {
  Cash: "Cash", Bank: "Bank", MobileMoney: "Mobile money", Other: "Other",
}

export const LOSS_REASON_LABEL: Record<LossReason, string> = {
  Spoiled: "Spoiled", Expired: "Expired", Spilled: "Spilled", Stolen: "Stolen", Damaged: "Damaged", Other: "Other",
}

export const PURCHASE_STATUS: Record<Purchase["status"], { label: string; cls: string }> = {
  Unpaid: { label: "Unpaid", cls: "bg-rose-600" },
  PartPaid: { label: "Part paid", cls: "bg-amber-600" },
  Paid: { label: "Paid", cls: "bg-emerald-600" },
  Reversed: { label: "Reversed", cls: "bg-stone-400" },
}

/** One line of a sale, in words. */
export function saleLineText(l: SaleLine): string {
  if (l.lineType === "Product") return `${fmtNum(l.quantity)} ${l.unit} ${l.itemName}`
  if (l.lineType === "Tagged") return `${l.speciesName ?? "Animal"} tag ${l.tagNumber}`
  return `${fmtNum(l.quantity)} ${l.speciesName?.toLowerCase() ?? "animals"} from ${l.groupName}`
}

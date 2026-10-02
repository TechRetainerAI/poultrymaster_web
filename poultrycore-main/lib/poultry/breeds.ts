// The breeds a farm can pick from.
//
// Breed was free text everywhere until now, which meant "Isa Brown", "ISA
// brown" and "Isa-Brown" were three different breeds to every report that
// grouped by it. A list fixes that.
//
// TWO THINGS THE LIST MUST NOT DO, because breed data already exists:
//
//   1. Lose a value it does not recognise. Farms have been typing this field
//      for months. Whatever is already stored is offered as a choice and stays
//      selected, even if it is nowhere in the curated list.
//   2. Refuse a breed nobody thought of. Poultry breeds vary by region and by
//      supplier, and a fixed list would make the next one unenterable. The
//      picker always keeps a way to type a new one.
//
// Pure: no React. The control is components/poultry/breed-select.tsx.

export interface BreedOption {
  value: string
  label: string
  /** The heading it sits under in the picker. */
  group: string
}

export const FARM_BREEDS_GROUP = "Used on this farm"

/**
 * Commercial breeds common in the markets this application serves. A starting
 * point, not a closed set — see the rules at the top of this file.
 */
export const BREED_CATALOG: { group: string; breeds: string[] }[] = [
  {
    group: "Layers",
    breeds: [
      "Isa Brown", "Lohmann Brown", "Bovan Brown", "Hy-Line Brown",
      "Shaver Brown", "Dekalb Brown", "Nera Black",
    ],
  },
  {
    group: "Broilers",
    breeds: ["Cobb 500", "Ross 308", "Arbor Acres", "Hubbard"],
  },
  {
    group: "Dual purpose",
    breeds: [
      "Sasso", "Kuroiler", "Noiler", "Rhode Island Red",
      "Plymouth Rock", "Light Sussex",
    ],
  },
  {
    group: "Local",
    breeds: ["Local / Indigenous"],
  },
]

/** Case- and spacing-insensitive, so "ISA brown" and "Isa Brown" are one breed. */
export const breedKey = (raw: string | null | undefined): string =>
  (raw ?? "").trim().replace(/\s+/g, " ").toLowerCase()

/**
 * Everything the picker should offer.
 *
 * What the farm already uses comes FIRST: on a farm running Isa Brown and Cobb
 * 500, those two should be a glance away rather than buried under breeds it has
 * never bought. The catalog follows, minus anything already listed above it.
 *
 * `current` is included even when it matches nothing at all — that is the rule
 * that stops opening an old record from silently clearing its breed.
 */
export function breedOptions(known: readonly string[] = [], current = ""): BreedOption[] {
  const seen = new Set<string>()
  const options: BreedOption[] = []

  const add = (raw: string, group: string) => {
    const value = (raw ?? "").trim()
    const key = breedKey(value)
    if (!key || seen.has(key)) return
    seen.add(key)
    options.push({ value, label: value, group })
  }

  // The farm's own, current value first so it is never the odd one out.
  add(current, FARM_BREEDS_GROUP)
  for (const breed of [...known].sort((a, b) => a.localeCompare(b))) add(breed, FARM_BREEDS_GROUP)
  for (const { group, breeds } of BREED_CATALOG) for (const breed of breeds) add(breed, group)

  return options
}

/** The picker's groups, in order, each with its options. */
export function groupedBreedOptions(
  known: readonly string[] = [],
  current = "",
): { group: string; options: BreedOption[] }[] {
  const options = breedOptions(known, current)
  const order: string[] = []
  const byGroup = new Map<string, BreedOption[]>()

  for (const option of options) {
    if (!byGroup.has(option.group)) {
      byGroup.set(option.group, [])
      order.push(option.group)
    }
    byGroup.get(option.group)!.push(option)
  }

  return order.map((group) => ({ group, options: byGroup.get(group)! }))
}

/** Whether a typed breed is one the picker already offers. */
export function isKnownBreed(value: string, known: readonly string[] = []): boolean {
  const key = breedKey(value)
  if (!key) return false
  return breedOptions(known).some((o) => breedKey(o.value) === key)
}

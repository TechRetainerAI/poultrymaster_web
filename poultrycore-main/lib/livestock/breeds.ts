// Breeds offered in the livestock breed dropdowns, per kind of animal
// (livestockspecies.speciescode). West African breeds first where they exist,
// then the common breeds worldwide, A-Z. Every list also offers "Local /
// indigenous", "Cross / mixed" and "Other" (typed) -- see BreedSelect -- so a
// breed missing here never blocks anyone. Stored as plain text, as before.

export const BREEDS: Record<string, string[]> = {
  duck: [
    "Muscovy", "Pekin", "Khaki Campbell", "Indian Runner", "Rouen", "Aylesbury", "Cayuga", "Swedish", "Welsh Harlequin", "Magpie",
    "Buff Orpington", "Saxony", "Silver Appleyard", "Call", "Crested", "Mallard", "Mulard (Moulard)", "Cherry Valley", "Grimaud hybrid",
    "Black East Indian", "Ancona", "Silver Bantam", "Abacot Ranger", "Golden 300 Hybrid",
  ],
  guinea_fowl: [
    "Helmeted (local)", "Pearl (grey)", "White", "Lavender", "Royal Purple", "Coral Blue", "Buff Dundotte", "Chocolate", "Pied",
    "Porcelain", "Slate", "Bronze", "French (Galor)", "Vulturine",
  ],
  turkey: [
    "Broad Breasted White", "Broad Breasted Bronze", "Bronze", "Narragansett", "Bourbon Red", "Royal Palm", "Black (Norfolk / Spanish)",
    "Blue Slate", "White Holland", "Beltsville Small White", "Midget White", "Jersey Buff", "Chocolate", "Nicholas", "B.U.T. Big 6",
    "Hybrid Converter", "Hybrid Grade Maker", "Auburn", "Buff", "Cröllwitzer",
  ],
  quail: [
    "Japanese (Coturnix)", "Jumbo Coturnix", "Pharaoh", "Texas A&M (white)", "English White", "Tuxedo", "Italian (golden)",
    "Manchurian Golden", "Tibetan", "Rosetta", "Bobwhite", "Button (King / Chinese Painted)", "California", "Gambel's",
  ],
  goose: [
    "African", "Chinese", "Embden", "Toulouse", "Pilgrim", "Sebastopol", "Pomeranian", "American Buff", "Roman", "Shetland",
    "Steinbacher", "Cotton Patch", "Egyptian", "Landes", "Legarth", "Lingnan", "Tufted Buff", "Canada",
  ],
  rabbit: [
    "New Zealand White", "New Zealand Red", "New Zealand Black", "Californian", "Flemish Giant", "Chinchilla (standard)",
    "American Chinchilla", "Giant Chinchilla", "Rex", "Mini Rex", "Dutch", "Hyla (Hyplus)", "Hycole", "Palomino", "Champagne d'Argent",
    "Crème d'Argent", "Silver Fox", "Satin", "Checkered Giant", "Belgian Hare", "Harlequin", "Angora (English)", "Angora (French)",
    "Lionhead", "Netherland Dwarf", "Holland Lop", "Mini Lop", "French Lop", "English Lop", "Havana", "Burgundy Fawn", "Vienna",
    "Blanc de Hotot", "Florida White", "Thrianta", "Polish", "Himalayan", "American Sable", "Cinnamon", "Beveren", "Continental Giant",
  ],
  grasscutter: [
    "Greater cane rat (Thryonomys swinderianus)", "Lesser cane rat (Thryonomys gregorianus)", "Improved / domesticated line",
    "Wild-caught",
  ],
  goat: [
    "West African Dwarf", "Sahelian", "Red Sokoto (Maradi)", "Borno White", "Kano Brown", "Boer", "Kalahari Red", "Savanna",
    "Saanen", "Alpine (French Alpine)", "Anglo-Nubian", "Nubian", "Toggenburg", "LaMancha", "Oberhasli", "Nigerian Dwarf", "Pygmy",
    "Kiko", "Spanish", "Angora", "Cashmere", "Jamnapari", "Beetal", "Black Bengal", "Barbari", "Damascus (Shami)", "Galla",
    "Small East African", "Matebele", "Myotonic (Tennessee fainting)", "Sable", "Golden Guernsey", "British Alpine", "Murciana-Granadina",
  ],
  sheep: [
    "West African Dwarf (Djallonké)", "Sahelian", "Uda (Ouda)", "Balami", "Yankasa", "Dorper", "White Dorper", "Merino", "Rambouillet",
    "Suffolk", "Hampshire Down", "Dorset", "Texel", "Romney", "Corriedale", "Border Leicester", "Bluefaced Leicester", "Cheviot",
    "Lincoln", "Romanov", "East Friesian", "Awassi", "Assaf", "Katahdin", "St. Croix", "Barbados Blackbelly", "Pelibuey", "Red Maasai",
    "Blackhead Persian", "Damara", "Karakul", "Jacob", "Shropshire", "Southdown", "Charollais", "Ile de France", "Finnsheep", "Van Rooy",
  ],
  pig: [
    "Ashanti Black (local)", "Large White (Yorkshire)", "Landrace", "Large White × Landrace (F1)", "Duroc", "Hampshire", "Pietrain",
    "Berkshire", "Chester White", "Tamworth", "Large Black", "Hereford", "Spotted", "Poland China", "Gloucestershire Old Spot",
    "Saddleback (Wessex / Essex)", "Middle White", "British Lop", "Welsh", "Mangalica", "Meishan", "Camborough (PIC)", "Kunekune",
    "Vietnamese Pot-bellied", "Red Wattle", "Mulefoot", "Ossabaw",
  ],
  cattle: [
    "West African Shorthorn (Muturu)", "Ghana Shorthorn", "Sanga (Ghana)", "N'Dama", "White Fulani (Bunaji)", "Sokoto Gudali",
    "Red Bororo (Rahaji)", "Kuri", "Zebu", "Brahman", "Boran", "Ankole", "Nguni", "Bonsmara", "Afrikaner", "Tuli", "Gir", "Sahiwal",
    "Red Sindhi", "Holstein Friesian", "Jersey", "Guernsey", "Ayrshire", "Brown Swiss", "Montbéliarde", "Normande", "Girolando",
    "Simmental", "Hereford", "Angus (Aberdeen Angus)", "Red Angus", "Charolais", "Limousin", "Shorthorn", "Belgian Blue", "Galloway",
    "Highland", "Dexter", "Wagyu", "Droughtmaster", "Santa Gertrudis", "Beefmaster", "Brangus",
  ],
}

/** Offered for every kind of animal, after its own breeds. */
export const GENERAL_BREEDS = ["Local / indigenous", "Cross / mixed", "Not sure"] as const

export function breedsFor(speciesCode: string | null | undefined): string[] {
  const own = (speciesCode && BREEDS[speciesCode]) || []
  return [...own, ...GENERAL_BREEDS]
}

// ---------------------------------------------------------------------------
// Age: people know an age in days, weeks, months or years. Groups keep days
// (the vaccination plan runs on day of age); intake batches keep the words
// ("8 weeks").
// ---------------------------------------------------------------------------
export type AgeUnit = "days" | "weeks" | "months" | "years"
export const AGE_UNIT_DAYS: Record<AgeUnit, number> = { days: 1, weeks: 7, months: 30, years: 365 }

export const ageToDays = (n: number, unit: AgeUnit) => Math.round(n * AGE_UNIT_DAYS[unit])

/** The largest unit a day count divides into evenly, so 56 reads as 8 weeks. */
export function daysToAge(days: number): { n: number; unit: AgeUnit } {
  for (const unit of ["years", "months", "weeks"] as AgeUnit[]) {
    const per = AGE_UNIT_DAYS[unit]
    if (days >= per && days % per === 0) return { n: days / per, unit }
  }
  return { n: days, unit: "days" }
}

/** "8 weeks" / "1 year" -- singular for 1. */
export function ageText(n: number, unit: AgeUnit) {
  return `${n} ${n === 1 ? unit.slice(0, -1) : unit}`
}

/** Reads "8 weeks", "1 yr", "3 months" back; null for text like "Point of lay". */
export function parseAgeText(text: string | null | undefined): { n: number; unit: AgeUnit } | null {
  const m = /^\s*(\d+(?:\.\d+)?)\s*(d|day|days|w|wk|wks|week|weeks|m|mo|mos|month|months|y|yr|yrs|year|years)\s*$/i.exec(text ?? "")
  if (!m) return null
  const u = m[2].toLowerCase()
  const unit: AgeUnit = u.startsWith("d") ? "days" : u.startsWith("w") ? "weeks" : u.startsWith("y") ? "years" : "months"
  return { n: Number(m[1]), unit }
}

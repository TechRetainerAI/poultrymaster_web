import { describe, it, expect } from "vitest"
import { readFileSync } from "node:fs"
import { join } from "node:path"

// The expenses table is `table-fixed`, so Description — the one auto-width
// column — receives (table min-width − every fixed width). If the fixed widths
// grow and the min-width does not, Description silently shrinks until it runs
// into Category.
//
// That has now happened THREE times:
//
//   1. comment claimed 720   while the columns said otherwise
//   2. comment claimed 1300  against columns totalling 1460 and a 1500 min-width
//                            -> Description 40px
//   3. comment claimed 1120  after Cost type (140) and Source (130) were added
//      / min-width 1400      for migrations 269/270 and never counted
//                            -> Description 10px
//
// Each time the file carried a comment reading "KEEP THIS SUM TRUE", and each
// time the person adding a column did not. So this asserts it instead.
//
// It reads the page source rather than rendering: the widths are Tailwind
// literals in the markup, and the bug is arithmetic between them and one other
// literal. Rendering would need jsdom, a viewport, and layout — none of which
// would catch this any more reliably than counting does.

const PAGE = join(process.cwd(), "app", "expenses", "page.tsx")

/** Width the layout reserves for Description before it starts to crush. */
const DESCRIPTION_FLOOR = 280

function readPage(): string {
  return readFileSync(PAGE, "utf8")
}

function headerBlock(src: string): string {
  const start = src.indexOf("<TableHeader>")
  const end = src.indexOf("</TableHeader>", start)
  expect(start, "no <TableHeader> in the expenses page").toBeGreaterThan(-1)
  expect(end, "unterminated <TableHeader>").toBeGreaterThan(start)
  return src.slice(start, end)
}

/** Every `w-[Npx]` declared on a header cell, in document order. */
function fixedWidths(headers: string): number[] {
  // No `s` flag: [^>] already spans newlines, and dotAll requires an
  // es2018 target this project does not set.
  const tags = headers.match(/<(?:SortableHeader|TableHead)\b[^>]*?\/?>/g) ?? []
  return tags
    .map((t) => t.match(/\bw-\[(\d+)px\]/)?.[1])
    .filter((w): w is string => Boolean(w))
    .map(Number)
}

function declaredMinWidth(src: string): number {
  // Anchored to the <Table> tag specifically — `min-w-[…]` appears on inner
  // elements too, and matching the first one in the file is how a check like
  // this quietly starts testing nothing.
  const tag = src.match(/<Table className="[^"]*table-fixed[^"]*"/)?.[0]
  expect(tag, "no table-fixed <Table> found on the expenses page").toBeTruthy()
  const w = tag!.match(/\bmin-w-\[(\d+)px\]/)?.[1]
  expect(w, "the expenses <Table> has no min-w-[…px]").toBeTruthy()
  return Number(w)
}

describe("expenses table column widths", () => {
  it("declares a min-width that leaves Description room to breathe", () => {
    const src = readPage()
    const fixed = fixedWidths(headerBlock(src))
    const total = fixed.reduce((a, b) => a + b, 0)
    const declared = declaredMinWidth(src)

    // The failure message carries the arithmetic, so whoever trips this can fix
    // it from the test output without opening the page.
    expect(
      declared,
      `Fixed columns total ${total}px and the table declares min-w-[${declared}px], ` +
        `which leaves Description ${declared - total}px. Set min-w-[${total + DESCRIPTION_FLOOR}px] ` +
        `(= ${total} fixed + ${DESCRIPTION_FLOOR} floor) and update the comment above the <Table>.`,
    ).toBe(total + DESCRIPTION_FLOOR)
  })

  it("finds every column, so the sum cannot pass by counting too few", () => {
    // The guard on the guard. If a refactor changed the markup so the regex
    // matched nothing, the sum would be 0 and the assertion above could be
    // satisfied by a small min-width while the real table was broken.
    // A LOOSE floor on purpose. The point is only to catch a refactor that made
    // the regex match nothing -- the sum would then be 0 and a small min-width
    // would satisfy the assertion above while the real table was broken. Tying
    // it to the exact column count would mean editing this test every time a
    // column is added or removed, which is the fragility it exists to avoid.
    const fixed = fixedWidths(headerBlock(readPage()))
    expect(fixed.length).toBeGreaterThanOrEqual(5)
    expect(Math.min(...fixed)).toBeGreaterThan(0)
  })
})

import { NextRequest, NextResponse } from 'next/server'

// Reuse the module-scoped store from parent route by importing mutable reference
// In Next.js route modules, each file is isolated; for simplicity in dev, maintain a local store here too
let houses: any[] = (global as any).__HOUSES__ || []
if (!(global as any).__HOUSES__) (global as any).__HOUSES__ = houses

export async function GET(_req: NextRequest, { params }: { params: { id: string } }) {
  const id = Number(params.id)
  const item = houses.find((h) => h.houseId === id)
  if (!item) return NextResponse.json({ success: false, message: 'Not found' }, { status: 404 })
  return NextResponse.json(item)
}

export async function PUT(req: NextRequest, { params }: { params: { id: string } }) {
  const id = Number(params.id)
  const body = await req.json()
  const idx = houses.findIndex((h) => h.houseId === id)
  if (idx === -1) return NextResponse.json({ success: false, message: 'Not found' }, { status: 404 })
  houses[idx] = { ...houses[idx], ...body }
  return NextResponse.json(houses[idx])
}

export async function DELETE(_req: NextRequest, { params }: { params: { id: string } }) {
  const id = Number(params.id)
  const before = houses.length
  houses = houses.filter((h) => h.houseId !== id)
  ;(global as any).__HOUSES__ = houses
  if (houses.length === before) return NextResponse.json({ success: false, message: 'Not found' }, { status: 404 })
  return NextResponse.json({ success: true })
}

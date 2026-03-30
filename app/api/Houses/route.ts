import { NextRequest, NextResponse } from 'next/server'

let houses: any[] = []
let idCounter = 1

export async function GET(req: NextRequest) {
  const { searchParams } = new URL(req.url)
  const farmId = searchParams.get('farmId')
  if (!farmId) return NextResponse.json({ success: false, message: 'farmId is required' }, { status: 400 })
  const data = houses.filter((h) => h.farmId === farmId)
  return NextResponse.json(data)
}

export async function POST(req: NextRequest) {
  const body = await req.json()
  if (!body?.farmId || !body?.name) {
    return NextResponse.json({ success: false, message: 'farmId and name are required' }, { status: 400 })
  }
  const now = new Date().toISOString()
  const item = { houseId: idCounter++, farmId: body.farmId, name: body.name, capacity: body.capacity ?? null, createdDate: now }
  houses.push(item)
  return NextResponse.json(item, { status: 201 })
}

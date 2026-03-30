import { buildApiUrl, getAuthHeaders } from './config'

function normalizeApiBase(raw?: string, fallback = 'farmapi.techretainer.com') {
  const val = raw || fallback
  return val.startsWith('http://') || val.startsWith('https://') ? val : `https://${val}`
}

// For server-side use
const DIRECT_API_BASE_URL = normalizeApiBase(process.env.NEXT_PUBLIC_API_BASE_URL)

// Check if we should use proxy (browser) or direct URL (server)
const IS_BROWSER = typeof window !== 'undefined'

export interface Supply {
  id: number
  userId: string
  farmId: string
  name: string
  type: string
  quantity: number
  unit: string
  cost: number
  supplier?: string | null
  purchaseDate?: string | null
  notes?: string | null
}

export interface SupplyInput {
  userId: string
  farmId: string
  name: string
  type: string
  quantity: number
  unit: string
  cost: number
  supplier?: string | null
  purchaseDate?: string | null
  notes?: string | null
}

export interface ApiResponse<T = any> {
  success: boolean
  data?: T
  message?: string
  errors?: string[]
}

function mapSupply(raw: any): Supply {
  return {
    id: Number(raw.itemId ?? raw.ItemId ?? raw.id ?? raw.Id ?? 0),
    userId: raw.userId ?? raw.UserId ?? "",
    farmId: raw.farmId ?? raw.FarmId ?? "",
    name: raw.name ?? raw.Name ?? raw.itemName ?? raw.ItemName ?? "",
    type: raw.type ?? raw.Type ?? raw.category ?? raw.Category ?? "",
    quantity: Number(
      raw.quantity ?? raw.Quantity ?? raw.quantityInStock ?? raw.QuantityInStock ?? 0
    ),
    unit: raw.unit ?? raw.Unit ?? raw.unitOfMeasure ?? raw.UnitOfMeasure ?? "",
    cost: Number(raw.cost ?? raw.Cost ?? 0),
    supplier: raw.supplier ?? raw.Supplier ?? null,
    purchaseDate: raw.purchaseDate ?? raw.PurchaseDate ?? null,
    notes: raw.notes ?? raw.Notes ?? null,
  }
}

export async function getSupplies(userId: string, farmId: string): Promise<ApiResponse<Supply[]>> {
  try {
    // Reuse InventoryItem as the backing entity for Supplies
    const endpoint = `/InventoryItem?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log('[v0] Fetching supplies:', url)

    const response = await fetch(url, {
      method: 'GET',
      headers: getAuthHeaders(),
    })

    console.log('[v0] Supplies response status:', response.status)

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to fetch supplies (${response.status})`,
      }
    }

    const data = await response.json()
    const supplies = Array.isArray(data) ? data.map(mapSupply) : []

    return {
      success: true,
      data: supplies,
    }
  } catch (error: any) {
    console.error('[v0] Supplies fetch error:', error)
    return {
      success: false,
      message: error?.message || 'Network error while fetching supplies',
    }
  }
}

export async function createSupply(input: SupplyInput): Promise<ApiResponse<Supply>> {
  try {
    // Create an InventoryItem record behind the scenes
    const endpoint = `/InventoryItem`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log('[v0] Creating supply:', url)

    const response = await fetch(url, {
      method: 'POST',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        UserId: input.userId,
        FarmId: input.farmId,
        ItemName: input.name,
        Category: input.type,
        QuantityInStock: input.quantity,
        UnitOfMeasure: input.unit,
        // ReorderLevel/IsActive can be extended later as needed
        ReorderLevel: null,
        IsActive: true,
      }),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to create supply (${response.status})`,
      }
    }

    const data = await response.json().catch(() => null)
    return {
      success: true,
      data: data ? mapSupply(data) : undefined,
    }
  } catch (error: any) {
    console.error('[v0] Supply create error:', error)
    return {
      success: false,
      message: error?.message || 'Network error while creating supply',
    }
  }
}

export async function updateSupply(id: number, input: SupplyInput): Promise<ApiResponse<void>> {
  try {
    const endpoint = `/InventoryItem/${id}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log('[v0] Updating supply:', url)

    const response = await fetch(url, {
      method: 'PUT',
      headers: getAuthHeaders(),
      body: JSON.stringify({
        ItemId: id,
        UserId: input.userId,
        FarmId: input.farmId,
        ItemName: input.name,
        Category: input.type,
        QuantityInStock: input.quantity,
        UnitOfMeasure: input.unit,
        ReorderLevel: null,
        IsActive: true,
      }),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to update supply (${response.status})`,
      }
    }

    return { success: true }
  } catch (error: any) {
    console.error('[v0] Supply update error:', error)
    return {
      success: false,
      message: error?.message || 'Network error while updating supply',
    }
  }
}

export async function deleteSupply(id: number, userId: string, farmId: string): Promise<ApiResponse<void>> {
  try {
    // SECURITY: Validate required parameters before proceeding
    if (!userId || !farmId) {
      console.error('[v0] Security: Missing userId or farmId for supply deletion');
      return {
        success: false,
        message: 'Authorization required. Please log in again.',
      };
    }
    
    if (!id || !Number.isFinite(id) || id <= 0) {
      console.error('[v0] Security: Invalid supply ID');
      return {
        success: false,
        message: 'Invalid supply ID',
      };
    }
    
    const endpoint = `/InventoryItem/${id}?userId=${encodeURIComponent(userId)}&farmId=${encodeURIComponent(farmId)}`
    const url = IS_BROWSER ? buildApiUrl(endpoint) : `${DIRECT_API_BASE_URL}/api${endpoint}`
    console.log('[v0] Deleting supply:', url)

    const response = await fetch(url, {
      method: 'DELETE',
      headers: getAuthHeaders(),
    })

    if (!response.ok) {
      const text = await response.text()
      return {
        success: false,
        message: text || `Failed to delete supply (${response.status})`,
      }
    }

    return { success: true }
  } catch (error: any) {
    console.error('[v0] Supply delete error:', error)
    return {
      success: false,
      message: error?.message || 'Network error while deleting supply',
    }
  }
}



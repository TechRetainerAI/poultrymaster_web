import { apiClient } from '@/lib/api/client'

export interface Flock {
  flockId: number
  farmId: string
  flockName: string
  breed: string
  quantity: number
  startDate: string
  expectedMaturityDate?: string
  currentAge: number
  status: 'Active' | 'Sold' | 'Depleted' | 'Transferred'
  notes?: string
  createdAt: string
  updatedAt: string
}

export interface FlockInput {
  farmId: string
  flockName: string
  breed: string
  quantity: number
  startDate: string
  expectedMaturityDate?: string
  notes?: string
}

export class FlocksService {
  /**
   * Get all flocks
   */
  static async getAll(): Promise<Flock[]> {
    return apiClient.get<Flock[]>('/api/Flocks')
  }

  /**
   * Get a single flock by ID
   */
  static async getById(id: number): Promise<Flock> {
    return apiClient.get<Flock>(`/api/Flocks/${id}`)
  }

  /**
   * Create a new flock
   */
  static async create(data: FlockInput): Promise<Flock> {
    return apiClient.post<Flock>('/api/Flocks', data)
  }

  /**
   * Update an existing flock
   */
  static async update(id: number, data: Partial<FlockInput>): Promise<Flock> {
    return apiClient.put<Flock>(`/api/Flocks/${id}`, data)
  }

  /**
   * Delete a flock
   */
  static async delete(id: number): Promise<void> {
    return apiClient.delete<void>(`/api/Flock/${id}`)
  }

  /**
   * Get active flocks
   */
  static async getActive(): Promise<Flock[]> {
    return apiClient.get<Flock[]>('/api/Flocks/active')
  }

  /**
   * Update flock quantity (for mortality tracking)
   */
  static async updateQuantity(id: number, quantity: number): Promise<Flock> {
    return apiClient.patch<Flock>(`/api/Flocks/${id}/quantity`, { quantity })
  }
}

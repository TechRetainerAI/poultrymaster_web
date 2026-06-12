import { apiClient } from '@/lib/api/client'

export interface Customer {
  customerId: number
  farmId: string
  customerName: string
  contactPerson?: string
  email?: string
  phone?: string
  address?: string
  city?: string
  state?: string
  country?: string
  postalCode?: string
  notes?: string
  createdAt: string
  updatedAt: string
}

export interface CustomerInput {
  farmId: string
  customerName: string
  contactPerson?: string
  email?: string
  phone?: string
  address?: string
  city?: string
  state?: string
  country?: string
  postalCode?: string
  notes?: string
}

export class CustomersService {
  /**
   * Get all customers
   */
  static async getAll(): Promise<Customer[]> {
    return apiClient.get<Customer[]>('/api/Customers')
  }

  /**
   * Get a single customer by ID
   */
  static async getById(id: number): Promise<Customer> {
    return apiClient.get<Customer>(`/api/Customers/${id}`)
  }

  /**
   * Create a new customer
   */
  static async create(data: CustomerInput): Promise<Customer> {
    return apiClient.post<Customer>('/api/Customers', data)
  }

  /**
   * Update an existing customer
   */
  static async update(id: number, data: Partial<CustomerInput>): Promise<Customer> {
    return apiClient.put<Customer>(`/api/Customers/${id}`, data)
  }

  /**
   * Delete a customer
   */
  static async delete(id: number): Promise<void> {
    return apiClient.delete<void>(`/api/Customers/${id}`)
  }

  /**
   * Search customers by name
   */
  static async search(query: string): Promise<Customer[]> {
    return apiClient.get<Customer[]>('/api/Customers/search', { query })
  }
}

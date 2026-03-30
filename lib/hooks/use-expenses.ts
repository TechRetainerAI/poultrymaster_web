import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { ExpensesService } from '@/lib/services/expenses.service'
import type { Expense, ExpenseInput } from '@/lib/api/types'

export function useExpenses(filters?: { farmId?: string; category?: string; startDate?: string; endDate?: string }) {
  return useQuery({
    queryKey: ['expenses', filters],
    queryFn: () => ExpensesService.getAll(filters),
  })
}

export function useExpense(id: number) {
  return useQuery({
    queryKey: ['expense', id],
    queryFn: () => ExpensesService.getById(id),
    enabled: !!id,
  })
}

export function useCreateExpense() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (data: ExpenseInput) => ExpensesService.create(data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] })
    },
  })
}

export function useUpdateExpense() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: ({ id, data }: { id: number; data: Partial<ExpenseInput> }) =>
      ExpensesService.update(id, data),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] })
    },
  })
}

export function useDeleteExpense() {
  const queryClient = useQueryClient()

  return useMutation({
    mutationFn: (id: number) => ExpensesService.delete(id),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['expenses'] })
    },
  })
}

import { useState, useEffect, useCallback } from 'react'

interface FetchState<T> {
  data: T | null
  loading: boolean
  error: Error | null
}

interface UseFetchReturn<T> extends FetchState<T> {
  refetch: () => Promise<void>
}

export function useFetch<T>(
  url: string,
  options?: RequestInit,
  dependencies: any[] = []
): UseFetchReturn<T> {
  const [state, setState] = useState<FetchState<T>>({
    data: null,
    loading: true,
    error: null,
  })

  const fetchData = useCallback(async () => {
    try {
      setState(prev => ({ ...prev, loading: true, error: null }))
      
      const response = await fetch(url, options)
      
      if (!response.ok) {
        throw new Error(`HTTP error! status: ${response.status}`)
      }
      
      const data = await response.json()
      setState({ data, loading: false, error: null })
    } catch (error) {
      setState({
        data: null,
        loading: false,
        error: error instanceof Error ? error : new Error('Unknown error'),
      })
    }
  }, [url, JSON.stringify(options)])

  useEffect(() => {
    fetchData()
  }, [fetchData, ...dependencies])

  return {
    ...state,
    refetch: fetchData,
  }
}

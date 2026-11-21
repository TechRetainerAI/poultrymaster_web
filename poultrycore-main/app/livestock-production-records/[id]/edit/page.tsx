"use client"

// The record page is the edit page now (like poultry's /production-records/[id]),
// so old /edit links land there.

import { useEffect } from "react"
import { useParams, useRouter } from "next/navigation"
import { LivestockPage, Loading } from "@/components/livestock/livestock-page"

export default function EditLivestockProductionRecordRedirect() {
  const { id } = useParams<{ id: string }>()
  const router = useRouter()
  useEffect(() => { router.replace(`/livestock-production-records/${id}`) }, [id, router])
  return <LivestockPage title="Edit Production Record"><Loading /></LivestockPage>
}

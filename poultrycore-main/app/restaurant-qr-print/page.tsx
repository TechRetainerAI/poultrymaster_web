"use client"

/**
 * Printable sheet of table QR codes.
 *
 * A dedicated route rather than a print stylesheet on the settings page, because
 * the dashboard shell (sidebar, header, sticky bars) fights any attempt to lay
 * out an A4 page inside it. Here there is nothing to hide.
 *
 * `?table=<qrCodeId>` prints one card; no parameter prints every active code.
 */

import { Suspense, useCallback, useEffect, useState } from "react"
import { useRouter, useSearchParams } from "next/navigation"
import { Button } from "@/components/ui/button"
import { Printer, ArrowLeft } from "lucide-react"
import { useAuthStore } from "@/lib/store/auth-store"
import { QrTableCard } from "@/components/restaurant/qr-table-card"
import {
  listQrCodes, getOnlineSettings, getRestaurantProfile,
  type QrCode as QrCodeType,
} from "@/lib/api/restaurant"

function QrPrintContent() {
  const router = useRouter()
  const params = useSearchParams()
  const activeFarmType = useAuthStore((s) => s.activeFarmType)
  const only = params.get("table")

  const [codes, setCodes] = useState<QrCodeType[]>([])
  const [publicBaseUrl, setPublicBaseUrl] = useState<string | null>(null)
  const [restaurantName, setRestaurantName] = useState<string | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  const load = useCallback(async () => {
    setLoading(true)
    try {
      const [qr, settings, profile] = await Promise.all([
        listQrCodes(),
        getOnlineSettings().catch(() => null),
        getRestaurantProfile().catch(() => null),
      ])
      const active = qr.filter(q => q.isActive)
      setCodes(only ? active.filter(q => String(q.qrCodeId) === only) : active)
      setPublicBaseUrl(settings?.publicBaseUrl ?? null)
      setRestaurantName(profile?.restaurantName ?? null)
    } catch (e: any) {
      setError(e?.message ?? "Could not load the QR codes.")
    } finally {
      setLoading(false)
    }
  }, [only])

  useEffect(() => {
    if (activeFarmType === null || activeFarmType === undefined) return
    if (activeFarmType !== "Restaurant") { router.replace("/dashboard"); return }
    load()
  }, [activeFarmType, router, load])

  // Open the print dialog once the cards are actually on screen. Printing before
  // the QR SVGs render would produce a sheet of empty boxes.
  useEffect(() => {
    if (loading || error || codes.length === 0) return
    const t = setTimeout(() => window.print(), 400)
    return () => clearTimeout(t)
  }, [loading, error, codes.length])

  return (
    <div className="min-h-screen bg-white p-6 print:p-0">
      <style>{`
        @page { size: A4; margin: 10mm; }
        @media print {
          .no-print { display: none !important; }
          .qr-table-card { break-inside: avoid; page-break-inside: avoid; }
        }
      `}</style>

      <div className="no-print mb-6 flex items-center justify-between gap-3">
        <Button variant="ghost" size="sm" onClick={() => router.back()}>
          <ArrowLeft className="h-4 w-4 mr-1.5" /> Back
        </Button>
        <div className="text-sm text-muted-foreground">
          {loading ? "Loading…" : `${codes.length} card${codes.length === 1 ? "" : "s"} ready. Cut along the borders and fold or stand on each table.`}
        </div>
        <Button size="sm" onClick={() => window.print()} disabled={loading || codes.length === 0}>
          <Printer className="h-4 w-4 mr-1.5" /> Print
        </Button>
      </div>

      {error && <p className="no-print text-sm text-red-600">{error}</p>}

      {!loading && !error && codes.length === 0 && (
        <p className="no-print text-sm text-muted-foreground">
          No active QR codes yet. Generate them under Online Settings → QR Codes.
        </p>
      )}

      <div className="flex flex-wrap justify-center gap-4 print:gap-2">
        {codes.map(q => (
          <QrTableCard
            key={q.qrCodeId}
            token={q.qrToken}
            tableNumber={q.tableNumber}
            restaurantName={restaurantName}
            publicBaseUrl={publicBaseUrl}
          />
        ))}
      </div>
    </div>
  )
}

export default function RestaurantQrPrintPage() {
  return (
    <Suspense fallback={<div className="p-6 text-sm text-muted-foreground">Loading…</div>}>
      <QrPrintContent />
    </Suspense>
  )
}

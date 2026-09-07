"use client"

import { QRCodeSVG } from "qrcode.react"
import { buildQrOrderUrl } from "@/lib/utils/qr-order-url"

/**
 * A printable table tent carrying one table's ordering QR code.
 *
 * Rendered as SVG rather than a raster image on purpose: these get printed, and
 * a bitmap that looks fine at 128px on screen prints soft enough to hurt scan
 * reliability. SVG stays sharp at whatever size the printer runs at.
 *
 * Sizes are in millimetres so a printed card is a predictable physical object
 * rather than whatever the browser's pixel guess happens to be that day.
 *
 * Error correction is "M" (~15% recoverable). Higher levels survive more coffee
 * rings but pack the modules tighter, which hurts more than it helps at the size
 * a phone camera sees across a table.
 */

export interface QrTableCardProps {
  /** The `qrToken` from restaurantqrcodes. */
  token: string
  /** Shown large for a table code — how staff match a card to a table when printing a stack. */
  tableNumber?: string | null
  /** "Restaurant" prints one counter poster for the venue; "Table" prints a table tent. */
  codeType?: "Restaurant" | "Table"
  /** Printed small at the top so a card found loose can be put back. */
  restaurantName?: string | null
  /** The farm's `publicBaseUrl` setting; falls back to the current origin. */
  publicBaseUrl?: string | null
  /** Width of the QR itself in mm. 45mm scans reliably from across a table. */
  sizeMm?: number
  className?: string
}

export function QrTableCard({
  token,
  tableNumber,
  codeType = "Table",
  restaurantName,
  publicBaseUrl,
  sizeMm = 45,
  className = "",
}: QrTableCardProps) {
  const url = buildQrOrderUrl(token, publicBaseUrl)
  const isVenue = codeType === "Restaurant"

  // Server-side there is no origin, so the URL would be relative and the printed
  // code would be useless. Reserve the space and let it fill in on the client.
  if (!url) {
    return (
      <div
        className={`qr-table-card flex flex-col items-center justify-center rounded-xl border bg-white text-center ${className}`}
        style={{ width: "70mm", minHeight: "95mm" }}
        aria-hidden
      />
    )
  }

  return (
    <div
      className={`qr-table-card flex flex-col items-center rounded-xl border bg-white px-4 py-5 text-center ${className}`}
      style={{ width: "70mm", minHeight: "95mm" }}
    >
      {isVenue ? (
        /* Counter poster: the restaurant's name is the heading, because there is
           no table to identify and the guest needs to know they scanned the right
           place. */
        <>
          <div className="mt-1 text-[9pt] uppercase tracking-widest text-gray-400">Order here</div>
          <div className="w-full break-words px-1 text-[18pt] font-bold leading-tight text-gray-900">
            {restaurantName || "Our Menu"}
          </div>
        </>
      ) : (
        <>
          {restaurantName && (
            <div className="w-full truncate text-[10pt] font-semibold text-gray-700">{restaurantName}</div>
          )}
          <div className="mt-1 text-[9pt] uppercase tracking-widest text-gray-400">Table</div>
          <div className="text-[26pt] font-bold leading-none text-gray-900">{tableNumber}</div>
        </>
      )}

      <div className="my-3">
        <QRCodeSVG
          value={url}
          size={Math.round(sizeMm * 3.7795)}   /* mm -> css px at 96dpi */
          level="M"
          marginSize={2}
          style={{ width: `${sizeMm}mm`, height: `${sizeMm}mm` }}
        />
      </div>

      <div className="text-[11pt] font-semibold leading-snug text-gray-900">
        {isVenue ? "Skip the queue — order from your phone" : "Scan to order from your phone"}
      </div>
      <div className="mt-1 px-1 text-[8.5pt] leading-snug text-gray-500">
        Point your camera here to see the menu, choose your food and order.
      </div>
    </div>
  )
}

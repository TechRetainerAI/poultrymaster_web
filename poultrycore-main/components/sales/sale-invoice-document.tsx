"use client"

import type { Sale } from "@/lib/api"

export type SaleInvoiceFarmInfo = {
  name: string
  address?: string
  phone?: string
  email?: string
}

export function saleInvoiceNumber(saleId: number) {
  return `INV-${saleId.toString().padStart(6, "0")}`
}

export function formatSaleInvoiceDate(date: string) {
  return new Date(date).toLocaleDateString(undefined, {
    year: "numeric",
    month: "short",
    day: "numeric",
  })
}

/**
 * Every rule the document itself needs, scoped to `.inv-*`.
 *
 * This is injected TWICE, on purpose: the component renders it inline so the
 * on-screen preview is styled, and the print window injects it again around the
 * copied markup. (Before, it only ever reached the print window — which is why
 * the preview in the dialog rendered as bare unstyled HTML.) Duplicating an
 * identical stylesheet is harmless; leaving the preview unstyled was not.
 *
 * Nothing here may target `body` or bare element selectors: on screen these
 * rules live in the app's own document and would leak out of the invoice.
 * Page-level setup belongs in SALE_INVOICE_PRINT_STYLES below.
 */
export const SALE_INVOICE_DOC_STYLES = `
  .inv-shell {
    --inv-ink:#0c1222; --inv-muted:#5c6578; --inv-line:#e8ecf2;
    --inv-accent:#0d4a42; --inv-accent-soft:#e9f5f2;
    max-width: 820px; margin: 0 auto; background:#fff; color: var(--inv-ink);
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 14px; line-height: 1.5; text-align: left;
    border: 1px solid var(--inv-line); border-radius: 14px; overflow: hidden;
    box-shadow: 0 1px 2px rgba(12,18,34,.04), 0 14px 34px -14px rgba(12,18,34,.20);
  }
  .inv-shell p, .inv-shell h1, .inv-shell h2, .inv-shell h3 { margin: 0; }

  /* Header band — the farm on the left, the document's identity on the right. */
  .inv-head {
    background: linear-gradient(135deg, #0d4a42 0%, #14655a 55%, #1c8574 100%);
    color: #fff; padding: 26px 32px;
    display: flex; flex-wrap: wrap; gap: 20px; justify-content: space-between; align-items: flex-start;
  }
  .inv-head .inv-brand-name { font-size: 1.4rem; font-weight: 700; letter-spacing: -0.02em; margin-bottom: 6px; }
  .inv-head .inv-brand-meta { font-size: 0.8125rem; color: rgba(255,255,255,.80); margin: 1px 0; }
  .inv-head-doc { text-align: right; margin-left: auto; }
  .inv-doc-type { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.22em; text-transform: uppercase; color: rgba(255,255,255,.72); margin-bottom: 5px; }
  .inv-no { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 1.15rem; font-weight: 700; letter-spacing: 0.01em; }

  .inv-badge { display: inline-block; margin-top: 12px; padding: 4px 12px; border-radius: 999px; font-size: 0.6875rem; font-weight: 700; letter-spacing: 0.06em; text-transform: uppercase; }
  .inv-badge-paid    { background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; }
  .inv-badge-partial { background: #eff6ff; color: #1d4ed8; border: 1px solid #bfdbfe; }
  .inv-badge-unpaid  { background: #fffbeb; color: #b45309; border: 1px solid #fde68a; }

  /* Meta strip: billed-to, dates, payment method — divided cells, no boxes. */
  .inv-meta { display: grid; grid-template-columns: 1.6fr 1fr 1fr; border-bottom: 1px solid var(--inv-line); }
  .inv-meta > div { padding: 18px 24px; border-left: 1px solid var(--inv-line); min-width: 0; }
  .inv-meta > div:first-child { border-left: 0; padding-left: 32px; }
  .inv-label { font-size: 0.65rem; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--inv-muted); margin-bottom: 6px; }
  .inv-strong { font-size: 1rem; font-weight: 600; }
  .inv-sub { font-size: 0.8125rem; color: var(--inv-muted); margin-top: 4px; line-height: 1.45; }

  .inv-body { padding: 24px 32px 28px; }

  .inv-table-wrap { border: 1px solid var(--inv-line); border-radius: 10px; overflow: hidden; }
  table.inv-table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  .inv-table thead th { background: var(--inv-accent-soft); color: var(--inv-accent); text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.65rem; font-weight: 700; padding: 11px 16px; text-align: left; }
  .inv-table td { padding: 14px 16px; border-top: 1px solid var(--inv-line); vertical-align: top; }
  .inv-table .num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .inv-table .strong { font-weight: 600; }
  .inv-line-note { margin-top: 5px; font-size: 0.75rem; color: var(--inv-muted); }

  .inv-foot { display: grid; grid-template-columns: 1fr 300px; gap: 24px; align-items: start; margin-top: 22px; }
  .inv-notes { font-size: 0.8125rem; color: var(--inv-muted); line-height: 1.55; }
  .inv-totals-row { display: flex; justify-content: space-between; gap: 16px; font-size: 0.875rem; padding: 7px 0; color: var(--inv-muted); }
  .inv-totals-row strong { color: var(--inv-ink); font-weight: 600; font-variant-numeric: tabular-nums; }
  .inv-totals-row.credit strong { color: #047857; }
  .inv-total-big { margin-top: 8px; padding: 14px 16px; border-radius: 10px; background: var(--inv-accent-soft); display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  .inv-total-big .label { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--inv-accent); }
  .inv-total-big .amt { font-size: 1.35rem; font-weight: 800; color: var(--inv-accent); font-variant-numeric: tabular-nums; }
  .inv-total-big.settled { background: #ecfdf5; }
  .inv-total-big.settled .label, .inv-total-big.settled .amt { color: #047857; }

  .inv-footer-line { margin-top: 26px; padding-top: 16px; border-top: 1px dashed var(--inv-line); font-size: 0.75rem; color: var(--inv-muted); text-align: center; }

  /* Phones. Four money columns cannot fit ~300px of usable width, so the line
     items stop being a table and stack into labelled rows; the header row is
     dropped because each cell carries its own label. Chrome shrinks throughout —
     nested dialog + mat + sheet padding ate most of a small screen.

     The "screen and" prefix is load-bearing: when printing, the viewport
     becomes the paper width, and A4 minus margins lands near enough to 640px
     that a wider margin would flip a printed invoice into the phone layout. */
  @media screen and (max-width: 640px) {
    .inv-shell { border-radius: 10px; font-size: 13px; }
    /* Stack rather than wrap: a long farm name would otherwise leave the
       invoice number stranded in a narrow column beside it. */
    .inv-head { padding: 18px; gap: 12px; flex-direction: column; }
    .inv-head .inv-brand-name { font-size: 1.15rem; }
    .inv-head-doc { text-align: left; margin-left: 0; }
    .inv-badge { margin-top: 8px; }
    .inv-meta { grid-template-columns: 1fr; }
    .inv-meta > div { border-left: 0; border-top: 1px solid var(--inv-line); padding: 12px 18px; }
    .inv-meta > div:first-child { border-top: 0; padding-left: 18px; }
    .inv-body { padding: 16px 18px 20px; }

    .inv-table thead { display: none; }
    .inv-table, .inv-table tbody, .inv-table tr, .inv-table td { display: block; width: 100%; }
    .inv-table td { border-top: 0; padding: 10px 14px; }
    .inv-table td:first-child { padding-bottom: 4px; }
    /* Label on the left, figure on the right — reads like a receipt line. */
    .inv-table td.num {
      display: flex; justify-content: space-between; align-items: baseline; gap: 12px;
      border-top: 1px solid var(--inv-line); padding: 8px 14px;
    }
    .inv-table td.num::before {
      content: attr(data-label);
      font-size: 0.65rem; font-weight: 700; letter-spacing: 0.1em;
      text-transform: uppercase; color: var(--inv-muted);
    }

    .inv-foot { grid-template-columns: 1fr; gap: 16px; margin-top: 18px; }
    /* What's owed matters more than the thank-you note, so it goes first. */
    .inv-totals { order: -1; }
    .inv-total-big .amt { font-size: 1.2rem; }
    .inv-footer-line { margin-top: 20px; }
  }
`

/**
 * The print window's full stylesheet: page setup + the document rules above.
 * Kept under the original name so the print handler needs no change.
 */
export const SALE_INVOICE_PRINT_STYLES = `
  @page { size: A4; margin: 14mm; }
  body { margin: 0; padding: 0; background: #fff; }
  ${SALE_INVOICE_DOC_STYLES}
  /* Paper already has the border; the browser drops backgrounds unless told
     otherwise, which would print the teal header as blank white. */
  .inv-shell { box-shadow: none; border: 0; border-radius: 0; max-width: none; }
  .inv-shell, .inv-shell * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
`

type Props = {
  sale: Sale
  farm: SaleInvoiceFarmInfo
  currencyCode: string
  formatMoney: (amount: number, code: string) => string
  flockLabel: string
}

export function SaleInvoiceDocument({ sale, farm, currencyCode, formatMoney, flockLabel }: Props) {
  const invNo = saleInvoiceNumber(sale.saleId)
  const money = (n: number) => formatMoney(n, currencyCode)

  // Mirrors `saleOwed` on the Sales page: fall back to the paid flag when
  // amountPaid is absent (older backend). The old invoice always printed the
  // full total as the balance due, so a customer who had already part-paid was
  // billed the whole amount again.
  const total = Number(sale.totalAmount) || 0
  const paidAmt = sale.amountPaid != null ? Number(sale.amountPaid) : sale.paid === false ? 0 : total
  const owed = Math.max(0, total - paidAmt)
  const status = owed <= 0 ? "Paid" : paidAmt > 0 ? "Part paid" : "Unpaid"
  const statusClass = owed <= 0 ? "inv-badge-paid" : paidAmt > 0 ? "inv-badge-partial" : "inv-badge-unpaid"

  const isEggs = sale.product?.toLowerCase().includes("egg")

  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: SALE_INVOICE_DOC_STYLES }} />
      <div className="inv-shell">
        <div className="inv-head">
          <div>
            <h1 className="inv-brand-name">{farm.name}</h1>
            {farm.address ? <p className="inv-brand-meta">{farm.address}</p> : null}
            {farm.phone ? <p className="inv-brand-meta">Tel {farm.phone}</p> : null}
            {farm.email ? <p className="inv-brand-meta">{farm.email}</p> : null}
          </div>
          <div className="inv-head-doc">
            <p className="inv-doc-type">Tax invoice</p>
            <p className="inv-no">{invNo}</p>
            <span className={`inv-badge ${statusClass}`}>{status}</span>
          </div>
        </div>

        <div className="inv-meta">
          <div>
            <p className="inv-label">Billed to</p>
            <p className="inv-strong">{sale.customerName}</p>
            {sale.saleDescription ? <p className="inv-sub">{sale.saleDescription}</p> : null}
          </div>
          <div>
            <p className="inv-label">Invoice date</p>
            <p className="inv-strong">{formatSaleInvoiceDate(sale.saleDate)}</p>
            <p className="inv-sub">Recorded {formatSaleInvoiceDate(sale.createdDate)}</p>
          </div>
          <div>
            <p className="inv-label">Payment</p>
            <p className="inv-strong">{sale.paymentMethod}</p>
            <p className="inv-sub">Flock: {flockLabel}</p>
          </div>
        </div>

        <div className="inv-body">
          <div className="inv-table-wrap">
            <table className="inv-table">
              <thead>
                <tr>
                  <th>Description</th>
                  <th className="num">Qty</th>
                  <th className="num">Unit price</th>
                  <th className="num">Amount</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <span className="strong">{sale.product}</span>
                    {isEggs && sale.quantity > 0 ? (
                      <div className="inv-line-note">
                        {Math.floor(sale.quantity / 30)} crates + {sale.quantity % 30} loose
                      </div>
                    ) : null}
                  </td>
                  {/* data-label feeds the stacked phone layout, where the
                      table header is hidden and each cell labels itself. */}
                  <td className="num" data-label="Qty">{sale.quantity}</td>
                  <td className="num" data-label="Unit price">{money(sale.unitPrice)}</td>
                  <td className="num strong" data-label="Amount">{money(total)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div className="inv-foot">
            <p className="inv-notes">
              Thank you for your business. If you have questions about this invoice, quote invoice number{" "}
              <strong style={{ color: "var(--inv-ink)" }}>{invNo}</strong>.
            </p>
            <div className="inv-totals">
              <div className="inv-totals-row">
                <span>Subtotal</span>
                <strong>{money(total)}</strong>
              </div>
              {paidAmt > 0 ? (
                <div className="inv-totals-row credit">
                  <span>Amount paid</span>
                  <strong>-{money(paidAmt)}</strong>
                </div>
              ) : null}
              <div className={`inv-total-big${owed <= 0 ? " settled" : ""}`}>
                <span className="label">{owed <= 0 ? "Paid in full" : "Balance due"}</span>
                <span className="amt">{money(owed)}</span>
              </div>
            </div>
          </div>

          <p className="inv-footer-line">This document was generated electronically and is valid without a signature.</p>
        </div>
      </div>
    </>
  )
}

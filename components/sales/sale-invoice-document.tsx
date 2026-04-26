"use client"

import type { Sale } from "@/lib/api"
import { cn } from "@/lib/utils"

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

/** Inline + print window: keep in sync with document markup classes */
export const SALE_INVOICE_PRINT_STYLES = `
  :root { --inv-ink:#0c1222; --inv-muted:#5c6578; --inv-line:#e8ecf2; --inv-accent:#0d4a42; --inv-accent-soft:#e6f4f1; }
  body { font-family: ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Helvetica, Arial, sans-serif; padding: 28px 32px; color: var(--inv-ink); background: #fff; }
  .inv-shell { max-width: 800px; margin: 0 auto; border: 1px solid var(--inv-line); border-radius: 2px; overflow: hidden; }
  .inv-accent-bar { height: 6px; background: linear-gradient(90deg, var(--inv-accent) 0%, #1a7a6c 45%, #2ea88f 100%); }
  .inv-body { padding: 28px 32px 32px; }
  .inv-top { display: flex; flex-wrap: wrap; justify-content: space-between; gap: 20px; margin-bottom: 28px; }
  .inv-brand-name { font-size: 1.35rem; font-weight: 700; letter-spacing: -0.02em; margin: 0 0 6px; }
  .inv-brand-meta { font-size: 0.8125rem; color: var(--inv-muted); line-height: 1.5; margin: 0; }
  .inv-meta-block { text-align: right; min-width: 200px; }
  .inv-label { font-size: 0.65rem; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--inv-muted); margin: 0 0 4px; }
  .inv-inv-no { font-family: ui-monospace, SFMono-Regular, Menlo, Monaco, Consolas, monospace; font-size: 1.125rem; font-weight: 700; color: var(--inv-accent); margin: 0 0 8px; }
  .inv-date-line { font-size: 0.8125rem; color: var(--inv-muted); margin: 2px 0; }
  .inv-badge { display: inline-block; margin-top: 10px; padding: 4px 12px; border-radius: 999px; font-size: 0.6875rem; font-weight: 700; letter-spacing: 0.04em; text-transform: uppercase; }
  .inv-badge-paid { background: #ecfdf5; color: #047857; border: 1px solid #a7f3d0; }
  .inv-badge-unpaid { background: #fffbeb; color: #b45309; border: 1px solid #fde68a; }
  .inv-columns { display: grid; grid-template-columns: 1.4fr 1fr; gap: 20px; margin-bottom: 24px; }
  @media (max-width: 640px) { .inv-columns { grid-template-columns: 1fr; } }
  .inv-panel { border: 1px solid var(--inv-line); border-radius: 2px; padding: 16px 18px; background: #fafbfc; }
  .inv-panel h3 { margin: 0 0 10px; font-size: 0.65rem; font-weight: 700; letter-spacing: 0.12em; text-transform: uppercase; color: var(--inv-muted); }
  .inv-panel .primary { margin: 0; font-size: 1.05rem; font-weight: 600; }
  .inv-panel .secondary { margin: 6px 0 0; font-size: 0.8125rem; color: var(--inv-muted); line-height: 1.45; }
  .inv-table-wrap { border: 1px solid var(--inv-line); border-radius: 2px; overflow: hidden; margin-bottom: 22px; }
  table.inv-table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  .inv-table thead { background: var(--inv-accent-soft); color: var(--inv-accent); text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.65rem; font-weight: 700; }
  .inv-table th { padding: 11px 16px; text-align: left; border-bottom: 1px solid var(--inv-line); }
  .inv-table td { padding: 14px 16px; border-bottom: 1px solid var(--inv-line); vertical-align: top; }
  .inv-table tbody tr:last-child td { border-bottom: none; }
  .inv-table .num { text-align: right; white-space: nowrap; }
  .inv-table .strong { font-weight: 600; }
  .inv-foot { display: grid; grid-template-columns: 1fr 260px; gap: 20px; align-items: start; }
  @media (max-width: 640px) { .inv-foot { grid-template-columns: 1fr; } }
  .inv-notes { font-size: 0.8125rem; color: var(--inv-muted); line-height: 1.55; }
  .inv-totals { border: 1px solid var(--inv-line); border-radius: 2px; padding: 16px 18px; background: #fafbfc; }
  .inv-totals-row { display: flex; justify-content: space-between; font-size: 0.8125rem; margin-bottom: 8px; color: var(--inv-muted); }
  .inv-totals-row strong { color: var(--inv-ink); font-weight: 600; }
  .inv-total-big { margin-top: 12px; padding-top: 12px; border-top: 2px solid var(--inv-accent); }
  .inv-total-big .label { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--inv-muted); }
  .inv-total-big .amt { font-size: 1.5rem; font-weight: 800; color: var(--inv-accent); margin-top: 4px; }
  .inv-footer-line { margin-top: 28px; padding-top: 16px; border-top: 1px dashed var(--inv-line); font-size: 0.75rem; color: var(--inv-muted); text-align: center; }
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
  const paid = sale.paid !== false

  return (
      <div className="inv-shell">
        <div className="inv-accent-bar" aria-hidden />
        <div className="inv-body">
          <div className="inv-top">
            <div>
              <p className="inv-label">From</p>
              <h1 className="inv-brand-name">{farm.name}</h1>
              {farm.address ? <p className="inv-brand-meta">{farm.address}</p> : null}
              {farm.phone ? <p className="inv-brand-meta">Tel {farm.phone}</p> : null}
              {farm.email ? <p className="inv-brand-meta">{farm.email}</p> : null}
            </div>
            <div className="inv-meta-block">
              <p className="inv-label">Tax invoice</p>
              <p className="inv-inv-no">{invNo}</p>
              <p className="inv-date-line">
                <strong style={{ color: "var(--inv-ink)" }}>Date:</strong> {formatSaleInvoiceDate(sale.saleDate)}
              </p>
              <p className="inv-date-line">
                <strong style={{ color: "var(--inv-ink)" }}>Recorded:</strong> {formatSaleInvoiceDate(sale.createdDate)}
              </p>
              <span className={cn("inv-badge", paid ? "inv-badge-paid" : "inv-badge-unpaid")}>
                {paid ? "Paid" : "Unpaid"}
              </span>
            </div>
          </div>

          <div className="inv-columns">
            <div className="inv-panel">
              <h3>Bill to</h3>
              <p className="primary">{sale.customerName}</p>
              <p className="secondary">{sale.saleDescription || "—"}</p>
            </div>
            <div className="inv-panel">
              <h3>Reference</h3>
              <p className="secondary">
                <strong style={{ color: "var(--inv-ink)" }}>Product:</strong> {sale.product}
              </p>
              <p className="secondary">
                <strong style={{ color: "var(--inv-ink)" }}>Flock:</strong> {flockLabel}
              </p>
              <p className="secondary">
                <strong style={{ color: "var(--inv-ink)" }}>Payment:</strong> {sale.paymentMethod}
              </p>
            </div>
          </div>

          <div className="inv-table-wrap">
            <table className="inv-table">
              <thead>
                <tr>
                  <th>Description</th>
                  <th className="num">Qty</th>
                  <th className="num">Unit</th>
                  <th className="num">Amount</th>
                </tr>
              </thead>
              <tbody>
                <tr>
                  <td>
                    <span className="strong">{sale.product}</span>
                    {sale.saleDescription ? (
                      <div style={{ marginTop: 6, fontSize: "0.8125rem", color: "var(--inv-muted)" }}>
                        {sale.saleDescription}
                      </div>
                    ) : null}
                    {sale.product?.toLowerCase().includes("egg") ? (
                      <div style={{ marginTop: 6, fontSize: "0.75rem", color: "var(--inv-muted)" }}>
                        {Math.floor(sale.quantity / 30)} crates + {sale.quantity % 30} loose
                      </div>
                    ) : null}
                  </td>
                  <td className="num">{sale.quantity}</td>
                  <td className="num">{formatMoney(sale.unitPrice, currencyCode)}</td>
                  <td className="num strong">{formatMoney(sale.totalAmount, currencyCode)}</td>
                </tr>
              </tbody>
            </table>
          </div>

          <div className="inv-foot">
            <p className="inv-notes">
              Thank you for your business. If you have questions about this invoice, reply with your invoice number{" "}
              <strong style={{ color: "var(--inv-ink)" }}>{invNo}</strong>.
            </p>
            <div className="inv-totals">
              <div className="inv-totals-row">
                <span>Subtotal</span>
                <strong>{formatMoney(sale.totalAmount, currencyCode)}</strong>
              </div>
              <div className="inv-totals-row">
                <span>Discount</span>
                <strong>{formatMoney(0, currencyCode)}</strong>
              </div>
              <div className="inv-total-big">
                <div className="label">Balance due</div>
                <div className="amt">{formatMoney(sale.totalAmount, currencyCode)}</div>
              </div>
            </div>
          </div>

          <p className="inv-footer-line">This document was generated electronically and is valid without a signature.</p>
        </div>
      </div>
  )
}

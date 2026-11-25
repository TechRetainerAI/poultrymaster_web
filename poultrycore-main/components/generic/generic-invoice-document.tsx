"use client"

// Professional invoice document for Generic companies.
//
// Renders a complete A4-printable invoice with company branding, customer
// details, line items, totals, payment instructions, and footer. Adapted
// from the Poultry SaleInvoiceDocument pattern with the same CSS approach:
// scoped `.inv-*` classes, inline styles for screen preview, and a separate
// print stylesheet that the print handler injects.

import type { InvoiceDocumentDetail, InvoiceSaleLineRow } from "@/lib/api/generic-invoice-documents"

export type InvoiceCompanyInfo = {
  name: string
  address?: string | null
  phone?: string | null
  email?: string | null
}

// =============================================================================
// Styles — scoped to .inv-shell, same approach as SaleInvoiceDocument
// =============================================================================

export const GENERIC_INVOICE_DOC_STYLES = `
  .inv-shell {
    --inv-ink:#0c1222; --inv-muted:#5c6578; --inv-line:#e8ecf2;
    --inv-accent:#3730a3; --inv-accent-soft:#eef2ff;
    max-width: 820px; margin: 0 auto; background:#fff; color: var(--inv-ink);
    font-family: ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, Helvetica, Arial, sans-serif;
    font-size: 14px; line-height: 1.5; text-align: left;
    border: 1px solid var(--inv-line); border-radius: 14px; overflow: hidden;
    box-shadow: 0 1px 2px rgba(12,18,34,.04), 0 14px 34px -14px rgba(12,18,34,.20);
  }
  .inv-shell p, .inv-shell h1, .inv-shell h2, .inv-shell h3 { margin: 0; }

  .inv-head {
    background: linear-gradient(135deg, #312e81 0%, #4338ca 55%, #6366f1 100%);
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
  .inv-badge-draft   { background: #f1f5f9; color: #475569; border: 1px solid #cbd5e1; }
  .inv-badge-voided  { background: #fef2f2; color: #991b1b; border: 1px solid #fecaca; }

  .inv-meta { display: grid; grid-template-columns: 1.6fr 1fr 1fr; border-bottom: 1px solid var(--inv-line); }
  .inv-meta > div { padding: 18px 24px; border-left: 1px solid var(--inv-line); min-width: 0; }
  .inv-meta > div:first-child { border-left: 0; padding-left: 32px; }
  .inv-label { font-size: 0.65rem; font-weight: 700; letter-spacing: 0.14em; text-transform: uppercase; color: var(--inv-muted); margin-bottom: 6px; }
  .inv-strong { font-size: 1rem; font-weight: 600; }
  .inv-sub { font-size: 0.8125rem; color: var(--inv-muted); margin-top: 4px; line-height: 1.45; }

  .inv-refs { padding: 12px 32px; border-bottom: 1px solid var(--inv-line); display: flex; flex-wrap: wrap; gap: 24px; }
  .inv-ref { font-size: 0.8125rem; }
  .inv-ref-label { font-size: 0.65rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--inv-muted); }

  .inv-body { padding: 24px 32px 28px; }

  .inv-table-wrap { border: 1px solid var(--inv-line); border-radius: 10px; overflow: hidden; }
  table.inv-table { width: 100%; border-collapse: collapse; font-size: 0.875rem; }
  .inv-table thead th { background: var(--inv-accent-soft); color: var(--inv-accent); text-transform: uppercase; letter-spacing: 0.08em; font-size: 0.65rem; font-weight: 700; padding: 11px 16px; text-align: left; }
  .inv-table td { padding: 14px 16px; border-top: 1px solid var(--inv-line); vertical-align: top; }
  .inv-table .num { text-align: right; white-space: nowrap; font-variant-numeric: tabular-nums; }
  .inv-table .strong { font-weight: 600; }

  .inv-foot { display: grid; grid-template-columns: 1fr 300px; gap: 24px; align-items: start; margin-top: 22px; }
  .inv-notes { font-size: 0.8125rem; color: var(--inv-muted); line-height: 1.55; }
  .inv-notes p { margin-bottom: 8px; }
  .inv-notes strong { color: var(--inv-ink); }
  .inv-totals-row { display: flex; justify-content: space-between; gap: 16px; font-size: 0.875rem; padding: 7px 0; color: var(--inv-muted); }
  .inv-totals-row strong { color: var(--inv-ink); font-weight: 600; font-variant-numeric: tabular-nums; }
  .inv-totals-row.credit strong { color: #047857; }
  .inv-total-big { margin-top: 8px; padding: 14px 16px; border-radius: 10px; background: var(--inv-accent-soft); display: flex; justify-content: space-between; align-items: center; gap: 12px; }
  .inv-total-big .label { font-size: 0.7rem; font-weight: 700; letter-spacing: 0.1em; text-transform: uppercase; color: var(--inv-accent); }
  .inv-total-big .amt { font-size: 1.35rem; font-weight: 800; color: var(--inv-accent); font-variant-numeric: tabular-nums; }
  .inv-total-big.settled { background: #ecfdf5; }
  .inv-total-big.settled .label, .inv-total-big.settled .amt { color: #047857; }

  .inv-payment-box { margin-top: 16px; padding: 14px 16px; border-radius: 10px; border: 1px solid var(--inv-line); background: #fafbfc; }
  .inv-payment-box .inv-label { margin-bottom: 4px; }
  .inv-payment-box p { font-size: 0.8125rem; color: var(--inv-ink); margin: 2px 0; white-space: pre-line; }

  .inv-terms { margin-top: 16px; padding: 12px 16px; border-radius: 8px; background: #f8fafc; font-size: 0.75rem; color: var(--inv-muted); line-height: 1.5; }

  .inv-footer-line { margin-top: 26px; padding-top: 16px; border-top: 1px dashed var(--inv-line); font-size: 0.75rem; color: var(--inv-muted); text-align: center; }

  @media screen and (max-width: 640px) {
    .inv-shell { border-radius: 10px; font-size: 13px; }
    .inv-head { padding: 18px; gap: 12px; flex-direction: column; }
    .inv-head .inv-brand-name { font-size: 1.15rem; }
    .inv-head-doc { text-align: left; margin-left: 0; }
    .inv-badge { margin-top: 8px; }
    .inv-meta { grid-template-columns: 1fr; }
    .inv-meta > div { border-left: 0; border-top: 1px solid var(--inv-line); padding: 12px 18px; }
    .inv-meta > div:first-child { border-top: 0; padding-left: 18px; }
    .inv-refs { padding: 10px 18px; }
    .inv-body { padding: 16px 18px 20px; }
    .inv-table thead { display: none; }
    .inv-table, .inv-table tbody, .inv-table tr, .inv-table td { display: block; width: 100%; }
    .inv-table td { border-top: 0; padding: 10px 14px; }
    .inv-table td:first-child { padding-bottom: 4px; }
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
    .inv-totals { order: -1; }
    .inv-total-big .amt { font-size: 1.2rem; }
    .inv-footer-line { margin-top: 20px; }
  }
`

export const GENERIC_INVOICE_PRINT_STYLES = `
  @page { size: A4; margin: 14mm; }
  body { margin: 0; padding: 0; background: #fff; }
  ${GENERIC_INVOICE_DOC_STYLES}
  .inv-shell { box-shadow: none; border: 0; border-radius: 0; max-width: none; }
  .inv-shell, .inv-shell * { -webkit-print-color-adjust: exact; print-color-adjust: exact; }
`

// =============================================================================
// Helpers
// =============================================================================

function fmtDate(d: string | null | undefined): string {
  if (!d) return "—"
  return new Date(d).toLocaleDateString(undefined, { year: "numeric", month: "short", day: "numeric" })
}

function paymentTermsLabel(terms: string): string {
  const map: Record<string, string> = {
    DueImmediately: "Due immediately",
    Net7: "Net 7 days", Net14: "Net 14 days", Net30: "Net 30 days",
    Net45: "Net 45 days", Net60: "Net 60 days", Custom: "Custom",
  }
  return map[terms] ?? terms
}

// =============================================================================
// Component
// =============================================================================

type Props = {
  invoice: InvoiceDocumentDetail
  lines: InvoiceSaleLineRow[]
  company: InvoiceCompanyInfo
  formatMoney: (n: number) => string
}

export function GenericInvoiceDocument({ invoice, lines, company, formatMoney }: Props) {
  const money = (n: number) => formatMoney(n)
  const total = invoice.totalAmount
  const paid = invoice.amountPaid
  const balance = invoice.balance
  const isVoided = invoice.documentStatus === "Voided"
  const isDraft = invoice.documentStatus === "Draft"

  const paymentStatus = balance <= 0 ? "Paid" : paid > 0 ? "Partially paid" : "Unpaid"
  const statusClass = isVoided ? "inv-badge-voided"
    : isDraft ? "inv-badge-draft"
    : balance <= 0 ? "inv-badge-paid"
    : paid > 0 ? "inv-badge-partial"
    : "inv-badge-unpaid"
  const statusLabel = isVoided ? "Voided" : isDraft ? "Draft" : paymentStatus

  const hasRefs = invoice.saleReceiptNumber || invoice.purchaseOrderReference
    || invoice.deliveryReference || invoice.projectName

  return (
    <>
      <style dangerouslySetInnerHTML={{ __html: GENERIC_INVOICE_DOC_STYLES }} />
      <div className="inv-shell">
        {/* Header */}
        <div className="inv-head">
          <div>
            <h1 className="inv-brand-name">{company.name}</h1>
            {company.address && <p className="inv-brand-meta">{company.address}</p>}
            {company.phone && <p className="inv-brand-meta">Tel {company.phone}</p>}
            {company.email && <p className="inv-brand-meta">{company.email}</p>}
          </div>
          <div className="inv-head-doc">
            <p className="inv-doc-type">Invoice</p>
            <p className="inv-no">{invoice.invoiceNumber}</p>
            <span className={`inv-badge ${statusClass}`}>{statusLabel}</span>
          </div>
        </div>

        {/* Meta strip */}
        <div className="inv-meta">
          <div>
            <p className="inv-label">Billed to</p>
            <p className="inv-strong">{invoice.customerBillingName || "—"}</p>
            {invoice.customerBillingAddress && <p className="inv-sub">{invoice.customerBillingAddress}</p>}
            {invoice.customerBillingPhone && <p className="inv-sub">Tel {invoice.customerBillingPhone}</p>}
            {invoice.customerBillingEmail && <p className="inv-sub">{invoice.customerBillingEmail}</p>}
          </div>
          <div>
            <p className="inv-label">Invoice date</p>
            <p className="inv-strong">{fmtDate(invoice.issueDate)}</p>
            <p className="inv-sub">Terms: {paymentTermsLabel(invoice.paymentTerms)}</p>
          </div>
          <div>
            <p className="inv-label">Due date</p>
            <p className="inv-strong">{fmtDate(invoice.dueDate)}</p>
            {invoice.daysUntilDue !== null && invoice.daysUntilDue !== undefined && !isVoided && balance > 0 && (
              <p className="inv-sub" style={invoice.daysUntilDue < 0 ? { color: "#dc2626", fontWeight: 600 } : undefined}>
                {invoice.daysUntilDue < 0
                  ? `${Math.abs(invoice.daysUntilDue)} days overdue`
                  : invoice.daysUntilDue === 0 ? "Due today"
                  : `${invoice.daysUntilDue} days remaining`}
              </p>
            )}
          </div>
        </div>

        {/* Reference strip */}
        {hasRefs && (
          <div className="inv-refs">
            {invoice.saleReceiptNumber && (
              <div className="inv-ref">
                <div className="inv-ref-label">Sale ref</div>
                <div>{invoice.saleReceiptNumber}</div>
              </div>
            )}
            {invoice.purchaseOrderReference && (
              <div className="inv-ref">
                <div className="inv-ref-label">PO ref</div>
                <div>{invoice.purchaseOrderReference}</div>
              </div>
            )}
            {invoice.deliveryReference && (
              <div className="inv-ref">
                <div className="inv-ref-label">Delivery ref</div>
                <div>{invoice.deliveryReference}</div>
              </div>
            )}
            {invoice.projectName && (
              <div className="inv-ref">
                <div className="inv-ref-label">Project</div>
                <div>{invoice.projectName}</div>
              </div>
            )}
          </div>
        )}

        {/* Body */}
        <div className="inv-body">
          {/* Line items */}
          <div className="inv-table-wrap">
            <table className="inv-table">
              <thead>
                <tr>
                  <th>Description</th>
                  <th className="num">Qty</th>
                  <th className="num">Unit</th>
                  <th className="num">Unit price</th>
                  <th className="num">Discount</th>
                  <th className="num">Amount</th>
                </tr>
              </thead>
              <tbody>
                {lines.map((ln) => (
                  <tr key={ln.genericSaleItemId}>
                    <td>
                      <span className="strong">
                        {ln.description || ln.productName || ln.serviceName || "Item"}
                      </span>
                      {ln.itemType && (
                        <span style={{ fontSize: "0.75rem", color: "var(--inv-muted)", marginLeft: 6 }}>
                          ({ln.itemType})
                        </span>
                      )}
                    </td>
                    <td className="num" data-label="Qty">{ln.quantity}</td>
                    <td className="num" data-label="Unit">{ln.unitName || "—"}</td>
                    <td className="num" data-label="Unit price">{money(ln.unitPrice)}</td>
                    <td className="num" data-label="Discount">{ln.discountAmount > 0 ? money(ln.discountAmount) : "—"}</td>
                    <td className="num strong" data-label="Amount">{money(ln.lineTotal)}</td>
                  </tr>
                ))}
                {lines.length === 0 && (
                  <tr>
                    <td colSpan={6} style={{ textAlign: "center", color: "var(--inv-muted)" }}>
                      No line items
                    </td>
                  </tr>
                )}
              </tbody>
            </table>
          </div>

          {/* Footer: notes + totals */}
          <div className="inv-foot">
            <div className="inv-notes-section">
              {/* Payment instructions */}
              {invoice.paymentInstructions && (
                <div className="inv-payment-box">
                  <p className="inv-label">Payment instructions</p>
                  <p>{invoice.paymentInstructions}</p>
                </div>
              )}
              {/* Footer notes */}
              {invoice.footerNotes && (
                <p className="inv-notes" style={{ marginTop: 12 }}>{invoice.footerNotes}</p>
              )}
              {/* T&C */}
              {invoice.termsAndConditions && (
                <div className="inv-terms">{invoice.termsAndConditions}</div>
              )}
              {!invoice.paymentInstructions && !invoice.footerNotes && (
                <p className="inv-notes">
                  Thank you for your business. If you have questions about this invoice,
                  quote invoice number <strong>{invoice.invoiceNumber}</strong>.
                </p>
              )}
            </div>

            <div className="inv-totals">
              <div className="inv-totals-row">
                <span>Subtotal</span>
                <strong>{money(invoice.subtotalAmount)}</strong>
              </div>
              {invoice.discountAmount > 0 && (
                <div className="inv-totals-row">
                  <span>Discount</span>
                  <strong>-{money(invoice.discountAmount)}</strong>
                </div>
              )}
              {invoice.taxAmount > 0 && (
                <div className="inv-totals-row">
                  <span>Tax</span>
                  <strong>{money(invoice.taxAmount)}</strong>
                </div>
              )}
              <div className="inv-totals-row" style={{ borderTop: "1px solid var(--inv-line)", paddingTop: 10 }}>
                <span style={{ fontWeight: 600 }}>Invoice total</span>
                <strong>{money(total)}</strong>
              </div>
              {paid > 0 && (
                <div className="inv-totals-row credit">
                  <span>Payments received</span>
                  <strong>-{money(paid)}</strong>
                </div>
              )}
              <div className={`inv-total-big${balance <= 0 && !isVoided ? " settled" : ""}`}>
                <span className="label">
                  {isVoided ? "Voided" : balance <= 0 ? "Paid in full" : "Balance due"}
                </span>
                <span className="amt">{isVoided ? "—" : money(balance)}</span>
              </div>
            </div>
          </div>

          <p className="inv-footer-line">
            This document was generated electronically and is valid without a signature.
          </p>
        </div>
      </div>
    </>
  )
}

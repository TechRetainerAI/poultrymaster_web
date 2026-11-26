import { describe, expect, it } from "vitest"
import {
  PAYMENT_TERMS_OPTIONS,
  DOCUMENT_STATUS_OPTIONS,
  PAYMENT_STATUS_OPTIONS,
} from "./generic-invoice-documents"

describe("generic-invoice-documents constants", () => {
  describe("PAYMENT_TERMS_OPTIONS", () => {
    it("contains 7 payment terms", () => {
      expect(PAYMENT_TERMS_OPTIONS).toHaveLength(7)
    })

    it("includes DueImmediately as the first option", () => {
      expect(PAYMENT_TERMS_OPTIONS[0].value).toBe("DueImmediately")
      expect(PAYMENT_TERMS_OPTIONS[0].label).toBe("Due Immediately")
    })

    it("includes all Net terms", () => {
      const values = PAYMENT_TERMS_OPTIONS.map((o) => o.value)
      expect(values).toContain("Net7")
      expect(values).toContain("Net14")
      expect(values).toContain("Net30")
      expect(values).toContain("Net45")
      expect(values).toContain("Net60")
    })

    it("includes Custom as the last option", () => {
      const last = PAYMENT_TERMS_OPTIONS[PAYMENT_TERMS_OPTIONS.length - 1]
      expect(last.value).toBe("Custom")
      expect(last.label).toBe("Custom date")
    })

    it("every option has both value and label", () => {
      for (const opt of PAYMENT_TERMS_OPTIONS) {
        expect(opt.value).toBeTruthy()
        expect(opt.label).toBeTruthy()
      }
    })
  })

  describe("DOCUMENT_STATUS_OPTIONS", () => {
    it("contains 4 statuses including All", () => {
      expect(DOCUMENT_STATUS_OPTIONS).toHaveLength(4)
      expect(DOCUMENT_STATUS_OPTIONS).toContain("All")
      expect(DOCUMENT_STATUS_OPTIONS).toContain("Draft")
      expect(DOCUMENT_STATUS_OPTIONS).toContain("Issued")
      expect(DOCUMENT_STATUS_OPTIONS).toContain("Voided")
    })
  })

  describe("PAYMENT_STATUS_OPTIONS", () => {
    it("contains 4 statuses including All", () => {
      expect(PAYMENT_STATUS_OPTIONS).toHaveLength(4)
      expect(PAYMENT_STATUS_OPTIONS).toContain("All")
      expect(PAYMENT_STATUS_OPTIONS).toContain("Unpaid")
      expect(PAYMENT_STATUS_OPTIONS).toContain("PartiallyPaid")
      expect(PAYMENT_STATUS_OPTIONS).toContain("Paid")
    })
  })
})

describe("generic-invoice-documents types", () => {
  it("InvoiceDocumentRow has required fields", () => {
    // Type-level test: this compiles only if the type has the expected shape
    const row: import("./generic-invoice-documents").InvoiceDocumentRow = {
      genericInvoiceDocumentId: 1,
      genericSaleId: 100,
      invoiceNumber: "INV-2026-000001",
      issueDate: "2026-01-15",
      dueDate: "2026-02-15",
      paymentTerms: "Net30",
      documentStatus: "Issued",
      customerBillingName: "ABC Corp",
      genericProjectId: null,
      projectName: null,
      saleReceiptNumber: "SAL-001",
      totalAmount: 10000,
      amountPaid: 4000,
      balance: 6000,
      paymentStatus: "PartiallyPaid",
      isOverdue: false,
      daysUntilDue: 15,
      createdAt: "2026-01-15T10:00:00Z",
    }
    expect(row.invoiceNumber).toBe("INV-2026-000001")
    expect(row.balance).toBe(6000)
    expect(row.totalAmount - row.amountPaid).toBe(row.balance)
  })

  it("InvoiceDocumentDetail extends row with full data", () => {
    const detail: import("./generic-invoice-documents").InvoiceDocumentDetail = {
      genericInvoiceDocumentId: 1,
      farmId: "farm-123",
      genericSaleId: 100,
      invoiceNumber: "INV-2026-000001",
      issueDate: "2026-01-15",
      dueDate: "2026-02-15",
      paymentTerms: "Net30",
      documentStatus: "Issued",
      customerBillingName: "ABC Corp",
      customerBillingAddress: "123 Main St",
      customerBillingEmail: "abc@example.com",
      customerBillingPhone: "0201234567",
      paymentInstructions: "Pay to MoMo 0201234567",
      footerNotes: "Thank you",
      termsAndConditions: null,
      purchaseOrderReference: "PO-100",
      deliveryReference: null,
      genericProjectId: 5,
      projectName: "Highway Contract",
      version: 1,
      voidedBy: null, voidedAt: null, voidReason: null,
      issuedBy: "admin", issuedAt: "2026-01-15T10:30:00Z",
      createdBy: "admin", createdAt: "2026-01-15T10:00:00Z",
      saleReceiptNumber: "SAL-001",
      saleDate: "2026-01-14T08:00:00Z",
      salesType: "CreditSale",
      subtotalAmount: 10000,
      discountAmount: 0,
      taxAmount: 0,
      totalAmount: 10000,
      amountPaid: 4000,
      balance: 6000,
      paymentStatus: "PartiallyPaid",
      saleStatus: "Approved",
      isOverdue: false,
      daysUntilDue: 15,
      lines: [],
      history: [],
    }
    expect(detail.customerBillingAddress).toBe("123 Main St")
    expect(detail.projectName).toBe("Highway Contract")
    expect(detail.lines).toEqual([])
  })

  it("GenerateInvoiceInput has correct shape", () => {
    const input: import("./generic-invoice-documents").GenerateInvoiceInput = {
      saleId: 100,
      paymentTerms: "Net30",
    }
    expect(input.saleId).toBe(100)
    // Optional fields should be undefined
    expect(input.dueDate).toBeUndefined()
    expect(input.purchaseOrderReference).toBeUndefined()
  })

  it("InvoiceSettingsDto has correct defaults shape", () => {
    const settings: import("./generic-invoice-documents").InvoiceSettingsDto = {
      farmId: "farm-1",
      invoicePrefix: "INV",
      nextNumber: 1,
      defaultPaymentTerms: "DueImmediately",
      paymentInstructions: null,
      footerNotes: null,
      termsAndConditions: null,
      autoGenerateInvoiceAfterSale: false,
      autoSendInvoiceAfterIssuance: false,
    }
    expect(settings.invoicePrefix).toBe("INV")
    expect(settings.autoGenerateInvoiceAfterSale).toBe(false)
  })
})

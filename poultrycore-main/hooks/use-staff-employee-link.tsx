"use client"

// Staff page side of the Staff <-> Employee link (migration 362). One hook so
// the five Staff pages (poultry, water, generic, hotel, restaurant) behave the
// same:
//
//   isEmployee(staffId)   the row has a login -> badge it.
//   ?fromEmployee=<id>    the Employees page sent a login here to be made a
//                         staff member: onFromEmployee gets the person's details
//                         to open the page's own New staff form with, and
//                         linkCreated(newStaffId) links the saved row to it.
//   makeEmployee(...)     opens Add Employee prefilled from a staff row; the new
//                         login is linked back to that row. Render `dialog`.

import { useCallback, useEffect, useRef, useState } from "react"
import { AddEmployeeDialog, type EmployeePrefill } from "@/components/employees/add-employee-dialog"
import { getEmployee } from "@/lib/api/admin"
import { FROM_EMPLOYEE_PARAM, getStaffUserLinks, setStaffUserLink } from "@/lib/api/staff-user-link"
import { useToast } from "@/hooks/use-toast"

export function useStaffEmployeeLink({ onFromEmployee }: { onFromEmployee: (person: EmployeePrefill) => void }) {
  const { toast } = useToast()
  const [links, setLinks] = useState<Map<number, string>>(new Map())
  // The login a New staff form was opened for. A ref, not state: it is read in
  // the page's save handler right after an await.
  const pendingUserId = useRef<string | null>(null)
  const [makeTarget, setMakeTarget] = useState<{ staffId: number; prefill: EmployeePrefill } | null>(null)

  const reloadLinks = useCallback(async () => {
    // The badges are a nicety: if the link API is down the page still works.
    try { setLinks(new Map((await getStaffUserLinks()).map((l) => [l.staffId, l.userId]))) } catch { /* keep the last known */ }
  }, [])

  useEffect(() => { void reloadLinks() }, [reloadLinks])

  useEffect(() => {
    const userId = new URLSearchParams(window.location.search).get(FROM_EMPLOYEE_PARAM)
    if (!userId) return
    // A refresh must not reopen the form for the same person.
    window.history.replaceState(null, "", window.location.pathname)
    void getEmployee(userId).then((r) => {
      if (!r.success || !r.data) {
        toast({ title: "Could not load that employee", description: r.message, variant: "destructive" })
        return
      }
      pendingUserId.current = userId
      onFromEmployee({ firstName: r.data.firstName, lastName: r.data.lastName, phoneNumber: r.data.phoneNumber, email: r.data.email })
    })
    // eslint-disable-next-line react-hooks/exhaustive-deps -- once, on arrival
  }, [])

  /** Call when New staff is opened by hand, so an abandoned prefill can't link it. */
  const clearPending = useCallback(() => { pendingUserId.current = null }, [])

  /** True while the New staff form is for an employee who already has a login
   *  (Hotel's create makes a login from the email unless told not to). */
  const isFromEmployee = useCallback(() => pendingUserId.current != null, [])

  /** Call after creating a staff row. Links it when the form came from an employee. */
  const linkCreated = useCallback(async (staffId: number | null | undefined) => {
    const userId = pendingUserId.current
    pendingUserId.current = null
    if (!userId || !staffId) return
    try {
      await setStaffUserLink(staffId, userId)
      toast({ title: "Linked to employee", description: "They now show on both Employees and Staff." })
    } catch (e: any) {
      toast({ title: "Staff added, but not linked to the employee", description: e?.message, variant: "destructive" })
    }
    await reloadLinks()
  }, [reloadLinks, toast])

  const isEmployee = useCallback((staffId: number) => links.has(staffId), [links])

  const makeEmployee = useCallback((staffId: number, prefill: EmployeePrefill) => setMakeTarget({ staffId, prefill }), [])

  const dialog = (
    <AddEmployeeDialog
      open={makeTarget != null}
      onOpenChange={(o) => { if (!o) setMakeTarget(null) }}
      prefill={makeTarget?.prefill}
      onCreated={async (employee) => {
        const staffId = makeTarget?.staffId
        if (!staffId || !employee?.id) return
        try {
          await setStaffUserLink(staffId, employee.id)
        } catch (e: any) {
          toast({ title: "Employee created, but not linked to this staff member", description: e?.message, variant: "destructive" })
        }
        await reloadLinks()
      }}
    />
  )

  return { isEmployee, isFromEmployee, clearPending, linkCreated, makeEmployee, dialog }
}

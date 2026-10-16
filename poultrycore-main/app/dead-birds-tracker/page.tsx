"use client"

/**
 * Dead birds tracker -- Dead Birds byproduct stock (372-381): deaths recorded on
 * production records, then sold, disposed or held. Never live birds.
 * Same component as the Broken eggs tracker.
 */

import { ByproductTracker } from "@/components/poultry/byproduct-tracker"

export default function DeadBirdsTrackerPage() {
  return <ByproductTracker role="DeadBirds" />
}

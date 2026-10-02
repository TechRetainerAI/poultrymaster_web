# Existing farms whose first production record already carries their history

Companion note to `319_PoultryFarmSetupOpeningPosition.postgres.sql`.
**Nothing described here is implemented, and migration 319 rewrites no
production history.** This is the analysis and the procedure, written down so
the decision is made deliberately rather than by a script that guessed.

## The shape of the problem

Before 319 the only place to put an established farm's historical losses was the
first production record's `mortality` column, because current birds are read as
`noofbirdsleft` on the latest production record and fall back to the flock's
placed quantity when there is none. A farm onboarded with eight flocks that had
lost 682 birds over previous months therefore has, somewhere, a day showing
`Deaths = 682` — a day on which nothing died.

That record is wrong in one specific way and right in another: the **mortality
figure is real** (those birds are genuinely gone) but the **date is a fiction**.
Any correction has to preserve the first and fix the second.

## Why this is not done automatically

An automatic migration would have to identify "a production record whose
mortality is actually accumulated history". There is no field that says so. The
available signals are all circumstantial:

| Signal | Why it is not sufficient on its own |
|---|---|
| It is the flock's **first** production record | Plenty of farms do start on a day when birds really did die. |
| Its mortality is **large** relative to the flock | A disease outbreak or a heat event looks identical. Farms lose hundreds of birds in a day. |
| Its mortality is large relative to **neighbouring days** | Same problem, and a farm with only one record has no neighbours. |
| `noofbirds` on it equals the flock's placed quantity | Expected on any genuine first record too. |
| It is dated at or near the company's **created date** | A farm can legitimately record its first real day on its first day. |

Combining them narrows it, but every combination still has a true-positive case
that is a real mortality event, and **silently deleting a real mortality event is
worse than leaving a wrong date in place**: the first is invisible data loss, the
second is at least visible in the chart. There is no threshold at which guessing
becomes safe, so the migration does not guess.

## What 319 does instead

Nothing, to existing data. New onboardings through Initial Farm Setup write an
opening position and **no production record at all**, so the problem stops being
created. Farms already carrying a bad first record keep it until someone decides,
per farm, what it actually was.

## The correction procedure, when a farm asks for it

Run per flock, with the farm confirming each number. All of it is ordinary
application work plus one SQL statement; none of it needs new code.

1. **Identify the candidate.** The earliest production record for the flock,
   where its mortality is implausible as a single day. Show it to the farm and
   ask directly: *"did these N birds die on this date?"* If yes, stop — there is
   nothing to correct.

2. **Establish what the opening position should have been.**
   - `originallyplaced` = the flock's placed quantity (`flocks.quantity` as it
     stands today, which pre-319 is the originally-placed figure).
   - `openinglivebirds` = `originallyplaced` − the historical portion the farm
     confirms.
   - The breakdown: whatever the farm can state. **If they cannot break it down,
     it is an unknown adjustment, not mortality** — the same rule the wizard
     applies, and the whole reason the column exists.

3. **Write the opening position**, dated to the day tracking really began (the
   day before that first production record is usually right, and it must be the
   company's business date, not UTC):

   ```sql
   SELECT public.sppoultryopeningposition_insert(
       p_farmid                => '<farmid>',
       p_flockid               => <flockid>,
       p_effectivebusinessdate => DATE '<the day tracking began>',
       p_originallyplaced      => <placed>,
       p_openinglivebirds      => <live on that day>,
       p_historicalmortality   => <confirmed, or 0>,
       p_historicalsold        => 0,
       p_historicalculled      => 0,
       p_historicaltransferred => 0,
       p_otheradjustment       => <the unconfirmed remainder>,
       p_historyknown          => <true only if the farm stated the breakdown>,
       p_startdateestimated    => false,
       p_source                => 'HistoricalCorrection',
       p_notes                 => 'Moved from production record #<id>, confirmed with the farm on <date>',
       p_createdby             => '<who did this>');
   ```

   Note the `source` — `'HistoricalCorrection'`, not `'InitialFarmSetup'`. A
   report should be able to tell a reconstructed opening position from one the
   farm entered itself.

4. **Reduce the production record** through the ordinary Production Records edit
   screen, not by SQL. Set its mortality to whatever really died that day
   (usually 0) and let the existing update path recompute `noofbirdsleft` and
   everything that hangs off it. Editing through the application is what keeps
   the audit trail, the stock movements and the derived figures consistent —
   `UPDATE productionrecords SET mortality = 0` does not, and will leave
   `noofbirdsleft` disagreeing with its own row.

5. **Set the flock's quantity to the opening live birds** through the Flock
   Groups edit form, so the flock and its opening position agree about day one.
   After 319 that is what a flock's quantity means.

6. **Verify.** `sppoultryopeningposition_getall` should show the historical
   figure, the production record should show the real day's mortality, and
   current birds should be unchanged from before the correction. If current
   birds moved, something in steps 4–5 was inconsistent — stop and re-check
   rather than adjusting a third number to make the first two agree.

## Ordering

Do step 3 before step 4. Between them the flock is briefly double-counted (the
opening position and the production record both hold the history), which
overstates losses; between 4 and 3 it is briefly under-counted, which
**overstates live birds** and is the direction someone may act on. Overstating
losses for a few minutes is the safer window.

## What would make automation viable later

A reliable marker. If the correction procedure above is run by hand for the first
few farms and each one is stamped with `source = 'HistoricalCorrection'`, the
resulting rows become a labelled data set: real first-day mortality on one side,
reconstructed history on the other. That is the point at which a rule could be
proposed and tested against known answers — and not before.

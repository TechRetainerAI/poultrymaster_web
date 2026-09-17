-- Seed for the 300 dry run. Runs INSIDE the rolled-back transaction, BEFORE the
-- migration body.
--
-- WHY THIS EXISTS
-- ---------------
-- On dev every hotelprofiles.timezone and restaurantprofiles.timezone is blank,
-- so running 300 as-is promotes nothing and the dry run proves only that the
-- migration does not crash. That is not a test. These rows manufacture the three
-- cases that actually matter, so the checks have something to assert against.
--
-- Nothing here is committed -- the runner rolls the whole transaction back.

-- A place for the checks to find out which company got which case, without
-- hard-coding ids that differ between databases.
CREATE TEMP TABLE seed299(scenario text PRIMARY KEY, farmid text, planted text);

DO $seed$
DECLARE
    v_valid     text;
    v_invalid   text;
    v_confirmed text;
BEGIN
    -- Three distinct hotel companies THAT ACTUALLY EXIST IN farms.
    --
    -- The join is not decoration: dev has 3 hotelprofiles rows but only 2 Hotel
    -- companies -- one profile points at a farmid with no farms row at all. The
    -- first version of this seed picked that orphan for the third scenario, so
    -- the UPDATE matched nothing, the check compared against a row that was
    -- never there, and the "already confirmed is never overwritten" case was
    -- silently not tested.
    SELECT h.farmid INTO v_valid FROM hotelprofiles h
      JOIN farms f ON lower(f.farmid::text) = lower(h.farmid::text)
      ORDER BY h.farmid OFFSET 0 LIMIT 1;
    SELECT h.farmid INTO v_invalid FROM hotelprofiles h
      JOIN farms f ON lower(f.farmid::text) = lower(h.farmid::text)
      ORDER BY h.farmid OFFSET 1 LIMIT 1;
    -- Only 2 hotel companies exist, so the third scenario borrows any other
    -- company: nothing about "a confirmed zone must not be overwritten" is
    -- specific to hotels, and it needs a profile row to conflict with.
    SELECT f.farmid INTO v_confirmed FROM farms f
      WHERE COALESCE(f.isdeleted,false) = false
        AND lower(f.farmid::text) NOT IN (lower(v_valid), lower(v_invalid))
      ORDER BY f.farmid LIMIT 1;

    IF v_valid IS NULL OR v_invalid IS NULL OR v_confirmed IS NULL THEN
        RAISE EXCEPTION
          'Need 2 hotel companies present in farms plus one other company to seed '
          'the 300 dry run; found valid=% invalid=% other=%',
          v_valid, v_invalid, v_confirmed;
    END IF;

    -- CASE 1: a valid IANA id somebody typed in Setup. Must be promoted, and
    -- must land as CONFIRMED -- a human chose it, unlike 298's currency guess.
    UPDATE hotelprofiles SET timezone = 'Africa/Nairobi' WHERE farmid = v_valid;
    INSERT INTO seed299 VALUES ('valid', v_valid, 'Africa/Nairobi');

    -- CASE 2: free text that is NOT an IANA id -- exactly what a free-text
    -- column collects. Must be LEFT ALONE and reported, never guessed at.
    UPDATE hotelprofiles SET timezone = 'EST' WHERE farmid = v_invalid;
    INSERT INTO seed299 VALUES ('invalid', v_invalid, 'EST');

    -- CASE 3: a company whose zone was already CONFIRMED by a human after 298.
    -- The profile column disagrees. The confirmed decision is the more recent
    -- and more deliberate one, so 299 must NOT overwrite it.
    UPDATE farms SET timezoneid = 'Europe/London', timezoneconfirmed = true
    WHERE  lower(farmid::text) = lower(v_confirmed);
    -- Give it a conflicting profile row to be promoted FROM, so the test is that
    -- 300 declined to overwrite rather than that it found nothing to do.
    --
    -- Deliberately a RESTAURANT profile: 300 has two near-identical promotion
    -- blocks and the hotel one is already covered by cases 1 and 2. Without this
    -- the restaurant block would report "promoted: 0" on every run and never be
    -- executed at all.
    INSERT INTO restaurantprofiles(farmid, restaurantname, timezone)
    VALUES (v_confirmed, 'Seed 300 conflicting profile', 'Asia/Dubai');
    INSERT INTO seed299 VALUES ('already_confirmed', v_confirmed, 'Europe/London');

    RAISE NOTICE 'seeded: valid=% invalid=% confirmed=%', v_valid, v_invalid, v_confirmed;
END
$seed$;

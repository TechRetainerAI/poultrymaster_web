-- Onboarding_SmokeTest.sql — database-side assertions for migration 349.
-- PASS = raised 'SMOKETEST_PASS ...' (everything rolls back); anything else fails.

DO $t$
DECLARE
    v_pct   int;
    v_reqc  int;
    v_reqt  int;
    v_missing text[];
    v_cnt   bigint;
    v_flockid int;
BEGIN
    -- Poultry company progressing through real milestones.
    INSERT INTO farms (id, farmid, name, email, type, owneruserid, isdeleted)
    VALUES (2000000349, 'smoke-349-poultry', 'Smoke Poultry', 's349p@test.local', 'Poultry', 'smoke-349-owner', false),
           (2000000350, 'smoke-349-school',  'Smoke School',  's349s@test.local', 'Generic', 'smoke-349-owner', false),
           (2000000351, 'smoke-349-newtpl',  'Smoke NewTpl',  's349n@test.local', 'Generic', 'smoke-349-owner', false);

    ---------------------------------------------------------------
    -- 1. Fresh poultry company: only CompanyCreated complete
    ---------------------------------------------------------------
    SELECT setuppercent, requiredcomplete, requiredtotal, missingtitles
      INTO v_pct, v_reqc, v_reqt, v_missing
      FROM platform_setup_summary() WHERE companyid = 'smoke-349-poultry';
    IF v_pct IS NULL OR v_pct <= 0 OR v_pct >= 50 THEN
        RAISE EXCEPTION 'FAIL 1: fresh poultry setup%% = % (expected small, > 0)', v_pct;
    END IF;
    IF v_reqc <> 1 OR v_reqt <> 2 THEN
        RAISE EXCEPTION 'FAIL 1b: required %/% (expected 1/2: CompanyCreated yes, FlockCreated no)', v_reqc, v_reqt;
    END IF;
    IF NOT ('Flock created' = ANY (v_missing)) THEN
        RAISE EXCEPTION 'FAIL 1c: missing list should name "Flock created": %', v_missing;
    END IF;

    ---------------------------------------------------------------
    -- 2. Milestone progression: flock + production move the needle
    ---------------------------------------------------------------
    INSERT INTO flock (farmid, userid, name, startdate, breed, quantity, active, batchid, hasarrived, isdeleted, datecreated, createdat)
    VALUES ('smoke-349-poultry', 'smoke-user', 'Smoke Flock', current_date, 'Layer', 100, true, 0, true, false, now(), now())
    RETURNING flockid INTO v_flockid;
    INSERT INTO eggproduction (farmid, flockid, productiondate, eggcount, userid)
    VALUES ('smoke-349-poultry', v_flockid, current_date, 10, 'smoke-user');

    SELECT setuppercent, requiredcomplete INTO v_pct, v_reqc
      FROM platform_setup_summary() WHERE companyid = 'smoke-349-poultry';
    IF v_reqc <> 2 THEN RAISE EXCEPTION 'FAIL 2: required complete = % (expected 2 after flock)', v_reqc; END IF;
    -- weights: CompanyCreated(1) + FlockCreated(2) + FirstProduction(2) of 15 total = 33%
    IF v_pct <> 33 THEN RAISE EXCEPTION 'FAIL 2b: setup%% = % (expected 33)', v_pct; END IF;

    ---------------------------------------------------------------
    -- 3. Generic template override: School set replaces family default
    ---------------------------------------------------------------
    INSERT INTO genericcompanyprofiles (farmid, genericbusinesstemplate, createdat)
    VALUES ('smoke-349-school', 'School', now());
    SELECT count(*) INTO v_cnt FROM platform_company_milestones
     WHERE companyid = 'smoke-349-school';
    IF v_cnt <> 5 THEN RAISE EXCEPTION 'FAIL 3: School override should give 5 milestones, got %', v_cnt; END IF;
    SELECT count(*) INTO v_cnt FROM platform_company_milestones
     WHERE companyid = 'smoke-349-school' AND title = 'First student setup';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 3b: School milestone titles not applied'; END IF;

    ---------------------------------------------------------------
    -- 4. Unknown/new template falls back to the Generic family default
    ---------------------------------------------------------------
    INSERT INTO genericcompanyprofiles (farmid, genericbusinesstemplate, createdat)
    VALUES ('smoke-349-newtpl', 'Pharmacy', now());
    SELECT count(*) INTO v_cnt FROM platform_company_milestones
     WHERE companyid = 'smoke-349-newtpl' AND milestonecode = 'ProfileSetup';
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 4: unknown template must fall back to family defaults'; END IF;
    SELECT count(*) INTO v_cnt FROM platform_company_milestones
     WHERE companyid = 'smoke-349-newtpl';
    IF v_cnt <> 7 THEN RAISE EXCEPTION 'FAIL 4b: fallback should give the 7 Generic defaults, got %', v_cnt; END IF;

    ---------------------------------------------------------------
    -- 5. ProfileSetup fact detected from genericcompanyprofiles
    ---------------------------------------------------------------
    SELECT count(*) INTO v_cnt FROM platform_company_milestones
     WHERE companyid = 'smoke-349-newtpl' AND milestonecode = 'ProfileSetup' AND complete;
    IF v_cnt <> 1 THEN RAISE EXCEPTION 'FAIL 5: ProfileSetup should be complete once the profile exists'; END IF;

    RAISE EXCEPTION 'SMOKETEST_PASS: all 5 onboarding assertions passed (rolled back on purpose)';
END
$t$;

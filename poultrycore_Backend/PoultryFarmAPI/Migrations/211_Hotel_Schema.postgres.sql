-- =============================================================================
-- Migration 211: Hotel Management System - Schema  (PostgreSQL)
-- =============================================================================
-- GENERATED FROM DEV'S LIVE SCHEMA, not from the SQL Server originals.
--
-- Why: the Hotel module's committed migrations (001_Hotel_*.sql) are SQL Server
-- and cannot run now that both databases are PostgreSQL. They were also numbered
-- 001-007, colliding with the existing 001_UnifyProductionTables ...
-- 007_AddAuditLogsFarmId. Meanwhile the schema HAD been applied to the dev
-- Postgres database by hand -- 31 tables, 40 functions, live data -- but never
-- committed, so nothing in git could reproduce it on production.
--
-- This file is that missing reproduction, dumped from dev on 2026-08-26 and
-- renumbered to continue the real sequence after 210. The SQL Server originals
-- are superseded and should be deleted once this is confirmed on prod.
--
-- Statement order is pg_dump's own (sequences -> tables -> defaults -> indexes
-- -> constraints), which is already dependency-safe.
--
-- Idempotent: CREATE ... IF NOT EXISTS where PostgreSQL supports it; catalog
-- guards for ADD CONSTRAINT and ALTER COLUMN SET DEFAULT, which have no such form.
--
-- KNOWN GAP -- room numbers are not unique per hotel.
-- The SQL Server original declared UX_HotelRooms_Number UNIQUE (FarmId, RoomNumber),
-- but no such index exists in dev, so this file (which mirrors dev) does not create
-- one either. Dev currently has two rooms sharing
-- (farmid, roomnumber) = (7c37f02c-0920-4a2b-81f9-5138ee282332, '001'), which is
-- why the constraint could not have survived. Nothing enforces distinct room
-- numbers today. To close it, de-duplicate first and then:
--
--   CREATE UNIQUE INDEX ux_hotelrooms_number ON public.hotelrooms (farmid, roomnumber);
--
-- Left out deliberately rather than silently: adding it would fail on real data.
-- =============================================================================

CREATE TABLE IF NOT EXISTS public.hotelamenities (
    hotelamenityid integer NOT NULL,
    farmid text NOT NULL,
    name character varying(100) NOT NULL,
    category character varying(50),
    icon character varying(50),
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.hotelfloors (
    hotelfloorid integer NOT NULL,
    farmid text NOT NULL,
    floornumber integer NOT NULL,
    name character varying(100) NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.hotelguests (
    hotelguestid integer NOT NULL,
    farmid text NOT NULL,
    firstname character varying(100) NOT NULL,
    lastname character varying(100) NOT NULL,
    email character varying(200),
    phone character varying(50),
    idtype character varying(50),
    idnumber character varying(100),
    nationality character varying(100),
    address character varying(500),
    dateofbirth date,
    notes text,
    isvip boolean DEFAULT false NOT NULL,
    totalstays integer DEFAULT 0 NOT NULL,
    laststaydate date,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.hotelprofiles (
    hotelprofileid integer NOT NULL,
    farmid text NOT NULL,
    hotelname character varying(200) NOT NULL,
    address character varying(500),
    city character varying(100),
    country character varying(100),
    phone character varying(50),
    email character varying(200),
    starrating integer,
    checkintime character varying(10) DEFAULT '14:00'::character varying NOT NULL,
    checkouttime character varying(10) DEFAULT '12:00'::character varying NOT NULL,
    defaultcurrency character varying(10) DEFAULT 'GHS'::character varying NOT NULL,
    taxrate numeric(5,2) DEFAULT 0 NOT NULL,
    servicechargerate numeric(5,2) DEFAULT 0 NOT NULL,
    timezone character varying(50),
    logourl character varying(500),
    description text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE TABLE IF NOT EXISTS public.hotelroomtypes (
    hotelroomtypeid integer NOT NULL,
    farmid text NOT NULL,
    name character varying(100) NOT NULL,
    description character varying(500),
    baserate numeric(12,2) DEFAULT 0 NOT NULL,
    maxoccupancy integer DEFAULT 2 NOT NULL,
    bedtype character varying(50),
    imageurl character varying(500),
    isactive boolean DEFAULT true NOT NULL,
    sortorder integer DEFAULT 0 NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelamenities_hotelamenityid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelamenities_hotelamenityid_seq OWNED BY public.hotelamenities.hotelamenityid;

CREATE TABLE IF NOT EXISTS public.hotelbookings (
    hotelbookingid integer NOT NULL,
    farmid text NOT NULL,
    bookingref character varying(30) NOT NULL,
    hotelguestid integer NOT NULL,
    hotelroomid integer,
    hotelroomtypeid integer NOT NULL,
    checkindate date NOT NULL,
    checkoutdate date NOT NULL,
    numberofguests integer DEFAULT 1 NOT NULL,
    adults integer DEFAULT 1 NOT NULL,
    children integer DEFAULT 0 NOT NULL,
    nightlyrate numeric(12,2) NOT NULL,
    totalamount numeric(12,2) NOT NULL,
    status character varying(30) DEFAULT 'Confirmed'::character varying NOT NULL,
    source character varying(30) DEFAULT 'WalkIn'::character varying NOT NULL,
    specialrequests text,
    createdby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelbookings_hotelbookingid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelbookings_hotelbookingid_seq OWNED BY public.hotelbookings.hotelbookingid;

CREATE TABLE IF NOT EXISTS public.hotelcashaccounts (
    hotelcashaccountid integer NOT NULL,
    farmid text NOT NULL,
    accountname character varying(100) NOT NULL,
    accounttype character varying(30) DEFAULT 'Cash'::character varying NOT NULL,
    openingbalance numeric(12,2) DEFAULT 0 NOT NULL,
    currentbalance numeric(12,2) DEFAULT 0 NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelcashaccounts_hotelcashaccountid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelcashaccounts_hotelcashaccountid_seq OWNED BY public.hotelcashaccounts.hotelcashaccountid;

CREATE TABLE IF NOT EXISTS public.hotelcheckins (
    hotelcheckinid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer NOT NULL,
    hotelroomid integer NOT NULL,
    hotelguestid integer NOT NULL,
    checkintime timestamp with time zone DEFAULT now() NOT NULL,
    keycardnumber character varying(50),
    depositamount numeric(12,2) DEFAULT 0 NOT NULL,
    depositmethod character varying(30),
    notes text,
    checkedinby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelcheckins_hotelcheckinid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelcheckins_hotelcheckinid_seq OWNED BY public.hotelcheckins.hotelcheckinid;

CREATE TABLE IF NOT EXISTS public.hotelcheckouts (
    hotelcheckoutid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer NOT NULL,
    hotelroomid integer NOT NULL,
    checkouttime timestamp with time zone DEFAULT now() NOT NULL,
    finalbillamount numeric(12,2) DEFAULT 0 NOT NULL,
    latefee numeric(12,2) DEFAULT 0 NOT NULL,
    damagecharges numeric(12,2) DEFAULT 0 NOT NULL,
    keyreturned boolean DEFAULT true NOT NULL,
    notes text,
    checkedoutby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelcheckouts_hotelcheckoutid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelcheckouts_hotelcheckoutid_seq OWNED BY public.hotelcheckouts.hotelcheckoutid;

CREATE TABLE IF NOT EXISTS public.hoteldailyclosings (
    hoteldailyclosingid integer NOT NULL,
    farmid text NOT NULL,
    closingdate date NOT NULL,
    totalrevenue numeric(12,2) DEFAULT 0 NOT NULL,
    roomrevenue numeric(12,2) DEFAULT 0 NOT NULL,
    fnbrevenue numeric(12,2) DEFAULT 0 NOT NULL,
    otherrevenue numeric(12,2) DEFAULT 0 NOT NULL,
    totalexpenses numeric(12,2) DEFAULT 0 NOT NULL,
    occupancyrate numeric(5,2) DEFAULT 0 NOT NULL,
    roomsoccupied integer DEFAULT 0 NOT NULL,
    totalrooms integer DEFAULT 0 NOT NULL,
    adr numeric(12,2) DEFAULT 0 NOT NULL,
    revpar numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    closedby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hoteldailyclosings_hoteldailyclosingid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hoteldailyclosings_hoteldailyclosingid_seq OWNED BY public.hoteldailyclosings.hoteldailyclosingid;

CREATE TABLE IF NOT EXISTS public.hotelexpenses (
    hotelexpenseid integer NOT NULL,
    farmid text NOT NULL,
    category character varying(100) NOT NULL,
    description character varying(500) NOT NULL,
    amount numeric(12,2) NOT NULL,
    expensedate date DEFAULT CURRENT_DATE NOT NULL,
    vendor character varying(200),
    receiptref character varying(100),
    status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    approvedby text,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelexpenses_hotelexpenseid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelexpenses_hotelexpenseid_seq OWNED BY public.hotelexpenses.hotelexpenseid;

CREATE SEQUENCE IF NOT EXISTS public.hotelfloors_hotelfloorid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelfloors_hotelfloorid_seq OWNED BY public.hotelfloors.hotelfloorid;

CREATE SEQUENCE IF NOT EXISTS public.hotelguests_hotelguestid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelguests_hotelguestid_seq OWNED BY public.hotelguests.hotelguestid;

CREATE TABLE IF NOT EXISTS public.hotelhousekeepingtasks (
    hotelhousekeepingtaskid integer NOT NULL,
    farmid text NOT NULL,
    hotelroomid integer NOT NULL,
    tasktype character varying(30) DEFAULT 'Cleaning'::character varying NOT NULL,
    priority character varying(20) DEFAULT 'Normal'::character varying NOT NULL,
    status character varying(20) DEFAULT 'Pending'::character varying NOT NULL,
    assignedto character varying(200),
    scheduleddate date DEFAULT CURRENT_DATE NOT NULL,
    startedat timestamp with time zone,
    completedat timestamp with time zone,
    inspectedby character varying(200),
    inspectionnotes text,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelhousekeepingtasks_hotelhousekeepingtaskid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelhousekeepingtasks_hotelhousekeepingtaskid_seq OWNED BY public.hotelhousekeepingtasks.hotelhousekeepingtaskid;

CREATE TABLE IF NOT EXISTS public.hotelinventoryitems (
    hotelinventoryitemid integer NOT NULL,
    farmid text NOT NULL,
    name character varying(150) NOT NULL,
    category character varying(50) NOT NULL,
    unit character varying(30) NOT NULL,
    stockonhand integer DEFAULT 0 NOT NULL,
    reorderlevel integer DEFAULT 0 NOT NULL,
    unitcost numeric(12,2) DEFAULT 0 NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelinventoryitems_hotelinventoryitemid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelinventoryitems_hotelinventoryitemid_seq OWNED BY public.hotelinventoryitems.hotelinventoryitemid;

CREATE TABLE IF NOT EXISTS public.hotelinvoices (
    hotelinvoiceid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer NOT NULL,
    hotelguestid integer NOT NULL,
    invoicenumber character varying(30) NOT NULL,
    subtotal numeric(12,2) DEFAULT 0 NOT NULL,
    taxamount numeric(12,2) DEFAULT 0 NOT NULL,
    taxrate numeric(5,2) DEFAULT 0 NOT NULL,
    discountamount numeric(12,2) DEFAULT 0 NOT NULL,
    totalamount numeric(12,2) DEFAULT 0 NOT NULL,
    amountpaid numeric(12,2) DEFAULT 0 NOT NULL,
    balance numeric(12,2) DEFAULT 0 NOT NULL,
    status character varying(20) DEFAULT 'Draft'::character varying NOT NULL,
    issueddate date DEFAULT CURRENT_DATE NOT NULL,
    duedate date,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelinvoices_hotelinvoiceid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelinvoices_hotelinvoiceid_seq OWNED BY public.hotelinvoices.hotelinvoiceid;

CREATE TABLE IF NOT EXISTS public.hotelloyaltymembers (
    hotelloyaltymemberid integer NOT NULL,
    farmid character varying(450) NOT NULL,
    hotelguestid integer NOT NULL,
    membershipnumber character varying(50) NOT NULL,
    tier character varying(20) DEFAULT 'Bronze'::character varying NOT NULL,
    totalpoints integer DEFAULT 0 NOT NULL,
    lifetimepoints integer DEFAULT 0 NOT NULL,
    joinedat timestamp without time zone DEFAULT now() NOT NULL,
    lasttierupdate timestamp without time zone,
    notes text,
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp without time zone DEFAULT now() NOT NULL,
    updatedat timestamp without time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelloyaltymembers_hotelloyaltymemberid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelloyaltymembers_hotelloyaltymemberid_seq OWNED BY public.hotelloyaltymembers.hotelloyaltymemberid;

CREATE TABLE IF NOT EXISTS public.hotelloyaltytransactions (
    hotelloyaltytransactionid integer NOT NULL,
    farmid character varying(450) NOT NULL,
    hotelloyaltymemberid integer NOT NULL,
    hotelbookingid integer,
    transactiontype character varying(20) NOT NULL,
    points integer NOT NULL,
    description text,
    createdat timestamp without time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelloyaltytransactions_hotelloyaltytransactionid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelloyaltytransactions_hotelloyaltytransactionid_seq OWNED BY public.hotelloyaltytransactions.hotelloyaltytransactionid;

CREATE TABLE IF NOT EXISTS public.hotelmaintenancerequests (
    hotelmaintenancerequestid integer NOT NULL,
    farmid text NOT NULL,
    hotelroomid integer,
    assetdescription character varying(200) NOT NULL,
    issuedescription text NOT NULL,
    priority character varying(20) DEFAULT 'Normal'::character varying NOT NULL,
    status character varying(20) DEFAULT 'Open'::character varying NOT NULL,
    assignedto character varying(200),
    estimatedcost numeric(12,2) DEFAULT 0 NOT NULL,
    actualcost numeric(12,2) DEFAULT 0 NOT NULL,
    reportedby character varying(200),
    reportedat timestamp with time zone DEFAULT now() NOT NULL,
    completedat timestamp with time zone,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelmaintenancerequests_hotelmaintenancerequestid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelmaintenancerequests_hotelmaintenancerequestid_seq OWNED BY public.hotelmaintenancerequests.hotelmaintenancerequestid;

CREATE TABLE IF NOT EXISTS public.hotelmenuitems (
    hotelmenuitemid integer NOT NULL,
    farmid text NOT NULL,
    name character varying(150) NOT NULL,
    category character varying(100) NOT NULL,
    description character varying(500),
    price numeric(12,2) NOT NULL,
    isavailable boolean DEFAULT true NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelmenuitems_hotelmenuitemid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelmenuitems_hotelmenuitemid_seq OWNED BY public.hotelmenuitems.hotelmenuitemid;

CREATE TABLE IF NOT EXISTS public.hotelnightaudits (
    hotelnightauditid integer NOT NULL,
    farmid text NOT NULL,
    auditdate date NOT NULL,
    totalrooms integer DEFAULT 0 NOT NULL,
    occupiedrooms integer DEFAULT 0 NOT NULL,
    availablerooms integer DEFAULT 0 NOT NULL,
    occupancyrate numeric(5,2) DEFAULT 0 NOT NULL,
    totalrevenue numeric(12,2) DEFAULT 0 NOT NULL,
    totalexpenses numeric(12,2) DEFAULT 0 NOT NULL,
    outstandingbalances numeric(12,2) DEFAULT 0 NOT NULL,
    checkincount integer DEFAULT 0 NOT NULL,
    checkoutcount integer DEFAULT 0 NOT NULL,
    noshowcount integer DEFAULT 0 NOT NULL,
    pendinghousetasks integer DEFAULT 0 NOT NULL,
    openmaintenance integer DEFAULT 0 NOT NULL,
    issues text,
    status character varying(20) DEFAULT 'Completed'::character varying NOT NULL,
    auditedby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelnightaudits_hotelnightauditid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelnightaudits_hotelnightauditid_seq OWNED BY public.hotelnightaudits.hotelnightauditid;

CREATE TABLE IF NOT EXISTS public.hotelpayments (
    hotelpaymentid integer NOT NULL,
    farmid text NOT NULL,
    hotelinvoiceid integer,
    hotelbookingid integer NOT NULL,
    amount numeric(12,2) NOT NULL,
    paymentmethod character varying(30) NOT NULL,
    reference character varying(100),
    paymentdate timestamp with time zone DEFAULT now() NOT NULL,
    receivedby text,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelpayments_hotelpaymentid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelpayments_hotelpaymentid_seq OWNED BY public.hotelpayments.hotelpaymentid;

CREATE TABLE IF NOT EXISTS public.hotelpayrollitems (
    hotelpayrollitemid integer NOT NULL,
    hotelpayrollrunid integer NOT NULL,
    hotelstaffid integer NOT NULL,
    staffname text,
    staffrole text,
    basicpay numeric(12,2) DEFAULT 0 NOT NULL,
    dailywage numeric(12,2) DEFAULT 0 NOT NULL,
    commission numeric(12,2) DEFAULT 0 NOT NULL,
    bonus numeric(12,2) DEFAULT 0 NOT NULL,
    deductions numeric(12,2) DEFAULT 0 NOT NULL,
    netpay numeric(12,2) DEFAULT 0 NOT NULL,
    paymentmethod text DEFAULT 'Cash'::text,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelpayrollitems_hotelpayrollitemid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelpayrollitems_hotelpayrollitemid_seq OWNED BY public.hotelpayrollitems.hotelpayrollitemid;

CREATE TABLE IF NOT EXISTS public.hotelpayrollruns (
    hotelpayrollrunid integer NOT NULL,
    farmid text NOT NULL,
    periodstart date NOT NULL,
    periodend date NOT NULL,
    paydate date,
    totalgrosspay numeric(12,2) DEFAULT 0 NOT NULL,
    totaldeductions numeric(12,2) DEFAULT 0 NOT NULL,
    totalnetpay numeric(12,2) DEFAULT 0 NOT NULL,
    status text DEFAULT 'Draft'::text NOT NULL,
    hotelcashaccountid integer,
    cashaccountname text,
    notes text,
    createdby text,
    approvedby text,
    approvedat timestamp with time zone,
    paidby text,
    paidat timestamp with time zone,
    cancelledby text,
    cancelreason text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelpayrollruns_hotelpayrollrunid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelpayrollruns_hotelpayrollrunid_seq OWNED BY public.hotelpayrollruns.hotelpayrollrunid;

CREATE SEQUENCE IF NOT EXISTS public.hotelprofiles_hotelprofileid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelprofiles_hotelprofileid_seq OWNED BY public.hotelprofiles.hotelprofileid;

CREATE TABLE IF NOT EXISTS public.hotelrestaurantorderitems (
    hotelrestaurantorderitemid integer NOT NULL,
    farmid text NOT NULL,
    hotelrestaurantorderid integer NOT NULL,
    hotelmenuitemid integer NOT NULL,
    itemname character varying(150) NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    unitprice numeric(12,2) NOT NULL,
    linetotal numeric(12,2) NOT NULL,
    notes character varying(200),
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelrestaurantorderitems_hotelrestaurantorderitemid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelrestaurantorderitems_hotelrestaurantorderitemid_seq OWNED BY public.hotelrestaurantorderitems.hotelrestaurantorderitemid;

CREATE TABLE IF NOT EXISTS public.hotelrestaurantorders (
    hotelrestaurantorderid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer,
    hotelroomid integer,
    tablenumber character varying(20),
    servername character varying(100),
    status character varying(20) DEFAULT 'Placed'::character varying NOT NULL,
    subtotal numeric(12,2) DEFAULT 0 NOT NULL,
    taxamount numeric(12,2) DEFAULT 0 NOT NULL,
    tipamount numeric(12,2) DEFAULT 0 NOT NULL,
    totalamount numeric(12,2) DEFAULT 0 NOT NULL,
    ordertime timestamp with time zone DEFAULT now() NOT NULL,
    deliveredtime timestamp with time zone,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelrestaurantorders_hotelrestaurantorderid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelrestaurantorders_hotelrestaurantorderid_seq OWNED BY public.hotelrestaurantorders.hotelrestaurantorderid;

CREATE TABLE IF NOT EXISTS public.hotelrestauranttables (
    hotelrestauranttableid integer NOT NULL,
    farmid text NOT NULL,
    tablenumber character varying(20) NOT NULL,
    capacity integer DEFAULT 4 NOT NULL,
    location character varying(100),
    status character varying(20) DEFAULT 'Available'::character varying NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelrestauranttables_hotelrestauranttableid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelrestauranttables_hotelrestauranttableid_seq OWNED BY public.hotelrestauranttables.hotelrestauranttableid;

CREATE TABLE IF NOT EXISTS public.hotelroomamenities (
    hotelroomid integer NOT NULL,
    hotelamenityid integer NOT NULL,
    farmid text NOT NULL
);

CREATE TABLE IF NOT EXISTS public.hotelroomrates (
    hotelroomrateid integer NOT NULL,
    farmid text NOT NULL,
    hotelroomtypeid integer NOT NULL,
    ratename character varying(100) NOT NULL,
    rate numeric(12,2) NOT NULL,
    startdate date NOT NULL,
    enddate date NOT NULL,
    dayofweek character varying(20),
    isweekend boolean DEFAULT false NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelroomrates_hotelroomrateid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelroomrates_hotelroomrateid_seq OWNED BY public.hotelroomrates.hotelroomrateid;

CREATE TABLE IF NOT EXISTS public.hotelrooms (
    hotelroomid integer NOT NULL,
    farmid text NOT NULL,
    roomnumber character varying(20) NOT NULL,
    hotelroomtypeid integer NOT NULL,
    hotelfloorid integer,
    status character varying(30) DEFAULT 'Available'::character varying NOT NULL,
    description character varying(500),
    isactive boolean DEFAULT true NOT NULL,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelrooms_hotelroomid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelrooms_hotelroomid_seq OWNED BY public.hotelrooms.hotelroomid;

CREATE TABLE IF NOT EXISTS public.hotelroomserviceorders (
    hotelroomserviceorderid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer NOT NULL,
    hotelroomid integer NOT NULL,
    ordertype character varying(30) DEFAULT 'Food'::character varying NOT NULL,
    status character varying(20) DEFAULT 'Placed'::character varying NOT NULL,
    totalamount numeric(12,2) DEFAULT 0 NOT NULL,
    ordertime timestamp with time zone DEFAULT now() NOT NULL,
    deliveredtime timestamp with time zone,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelroomserviceorders_hotelroomserviceorderid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelroomserviceorders_hotelroomserviceorderid_seq OWNED BY public.hotelroomserviceorders.hotelroomserviceorderid;

CREATE SEQUENCE IF NOT EXISTS public.hotelroomtypes_hotelroomtypeid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelroomtypes_hotelroomtypeid_seq OWNED BY public.hotelroomtypes.hotelroomtypeid;

CREATE TABLE IF NOT EXISTS public.hotelstaff (
    hotelstaffid integer NOT NULL,
    farmid text NOT NULL,
    firstname character varying(100) NOT NULL,
    lastname character varying(100) NOT NULL,
    email character varying(200),
    phone character varying(50),
    role character varying(50) NOT NULL,
    department character varying(50) NOT NULL,
    hiredate date DEFAULT CURRENT_DATE NOT NULL,
    isactive boolean DEFAULT true NOT NULL,
    salaryamount numeric(12,2) DEFAULT 0 NOT NULL,
    notes text,
    createdat timestamp with time zone DEFAULT now() NOT NULL,
    updatedat timestamp with time zone
);

CREATE SEQUENCE IF NOT EXISTS public.hotelstaff_hotelstaffid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelstaff_hotelstaffid_seq OWNED BY public.hotelstaff.hotelstaffid;

CREATE TABLE IF NOT EXISTS public.hotelstaycharges (
    hotelstaychargeid integer NOT NULL,
    farmid text NOT NULL,
    hotelbookingid integer NOT NULL,
    chargetype character varying(50) NOT NULL,
    description character varying(500) NOT NULL,
    quantity integer DEFAULT 1 NOT NULL,
    unitprice numeric(12,2) NOT NULL,
    totalamount numeric(12,2) NOT NULL,
    chargedate timestamp with time zone DEFAULT now() NOT NULL,
    postedby text,
    createdat timestamp with time zone DEFAULT now() NOT NULL
);

CREATE SEQUENCE IF NOT EXISTS public.hotelstaycharges_hotelstaychargeid_seq
    AS integer
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER SEQUENCE public.hotelstaycharges_hotelstaychargeid_seq OWNED BY public.hotelstaycharges.hotelstaychargeid;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelamenities'
                     AND column_name='hotelamenityid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelamenities ALTER COLUMN hotelamenityid SET DEFAULT nextval('public.hotelamenities_hotelamenityid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelbookings'
                     AND column_name='hotelbookingid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelbookings ALTER COLUMN hotelbookingid SET DEFAULT nextval('public.hotelbookings_hotelbookingid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelcashaccounts'
                     AND column_name='hotelcashaccountid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelcashaccounts ALTER COLUMN hotelcashaccountid SET DEFAULT nextval('public.hotelcashaccounts_hotelcashaccountid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelcheckins'
                     AND column_name='hotelcheckinid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelcheckins ALTER COLUMN hotelcheckinid SET DEFAULT nextval('public.hotelcheckins_hotelcheckinid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelcheckouts'
                     AND column_name='hotelcheckoutid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelcheckouts ALTER COLUMN hotelcheckoutid SET DEFAULT nextval('public.hotelcheckouts_hotelcheckoutid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hoteldailyclosings'
                     AND column_name='hoteldailyclosingid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hoteldailyclosings ALTER COLUMN hoteldailyclosingid SET DEFAULT nextval('public.hoteldailyclosings_hoteldailyclosingid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelexpenses'
                     AND column_name='hotelexpenseid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelexpenses ALTER COLUMN hotelexpenseid SET DEFAULT nextval('public.hotelexpenses_hotelexpenseid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelfloors'
                     AND column_name='hotelfloorid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelfloors ALTER COLUMN hotelfloorid SET DEFAULT nextval('public.hotelfloors_hotelfloorid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelguests'
                     AND column_name='hotelguestid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelguests ALTER COLUMN hotelguestid SET DEFAULT nextval('public.hotelguests_hotelguestid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelhousekeepingtasks'
                     AND column_name='hotelhousekeepingtaskid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelhousekeepingtasks ALTER COLUMN hotelhousekeepingtaskid SET DEFAULT nextval('public.hotelhousekeepingtasks_hotelhousekeepingtaskid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelinventoryitems'
                     AND column_name='hotelinventoryitemid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelinventoryitems ALTER COLUMN hotelinventoryitemid SET DEFAULT nextval('public.hotelinventoryitems_hotelinventoryitemid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelinvoices'
                     AND column_name='hotelinvoiceid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelinvoices ALTER COLUMN hotelinvoiceid SET DEFAULT nextval('public.hotelinvoices_hotelinvoiceid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelloyaltymembers'
                     AND column_name='hotelloyaltymemberid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelloyaltymembers ALTER COLUMN hotelloyaltymemberid SET DEFAULT nextval('public.hotelloyaltymembers_hotelloyaltymemberid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelloyaltytransactions'
                     AND column_name='hotelloyaltytransactionid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelloyaltytransactions ALTER COLUMN hotelloyaltytransactionid SET DEFAULT nextval('public.hotelloyaltytransactions_hotelloyaltytransactionid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelmaintenancerequests'
                     AND column_name='hotelmaintenancerequestid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelmaintenancerequests ALTER COLUMN hotelmaintenancerequestid SET DEFAULT nextval('public.hotelmaintenancerequests_hotelmaintenancerequestid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelmenuitems'
                     AND column_name='hotelmenuitemid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelmenuitems ALTER COLUMN hotelmenuitemid SET DEFAULT nextval('public.hotelmenuitems_hotelmenuitemid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelnightaudits'
                     AND column_name='hotelnightauditid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelnightaudits ALTER COLUMN hotelnightauditid SET DEFAULT nextval('public.hotelnightaudits_hotelnightauditid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelpayments'
                     AND column_name='hotelpaymentid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelpayments ALTER COLUMN hotelpaymentid SET DEFAULT nextval('public.hotelpayments_hotelpaymentid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelpayrollitems'
                     AND column_name='hotelpayrollitemid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelpayrollitems ALTER COLUMN hotelpayrollitemid SET DEFAULT nextval('public.hotelpayrollitems_hotelpayrollitemid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelpayrollruns'
                     AND column_name='hotelpayrollrunid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelpayrollruns ALTER COLUMN hotelpayrollrunid SET DEFAULT nextval('public.hotelpayrollruns_hotelpayrollrunid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelprofiles'
                     AND column_name='hotelprofileid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelprofiles ALTER COLUMN hotelprofileid SET DEFAULT nextval('public.hotelprofiles_hotelprofileid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelrestaurantorderitems'
                     AND column_name='hotelrestaurantorderitemid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelrestaurantorderitems ALTER COLUMN hotelrestaurantorderitemid SET DEFAULT nextval('public.hotelrestaurantorderitems_hotelrestaurantorderitemid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelrestaurantorders'
                     AND column_name='hotelrestaurantorderid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelrestaurantorders ALTER COLUMN hotelrestaurantorderid SET DEFAULT nextval('public.hotelrestaurantorders_hotelrestaurantorderid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelrestauranttables'
                     AND column_name='hotelrestauranttableid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelrestauranttables ALTER COLUMN hotelrestauranttableid SET DEFAULT nextval('public.hotelrestauranttables_hotelrestauranttableid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelroomrates'
                     AND column_name='hotelroomrateid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelroomrates ALTER COLUMN hotelroomrateid SET DEFAULT nextval('public.hotelroomrates_hotelroomrateid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelrooms'
                     AND column_name='hotelroomid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelrooms ALTER COLUMN hotelroomid SET DEFAULT nextval('public.hotelrooms_hotelroomid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelroomserviceorders'
                     AND column_name='hotelroomserviceorderid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelroomserviceorders ALTER COLUMN hotelroomserviceorderid SET DEFAULT nextval('public.hotelroomserviceorders_hotelroomserviceorderid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelroomtypes'
                     AND column_name='hotelroomtypeid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelroomtypes ALTER COLUMN hotelroomtypeid SET DEFAULT nextval('public.hotelroomtypes_hotelroomtypeid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelstaff'
                     AND column_name='hotelstaffid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelstaff ALTER COLUMN hotelstaffid SET DEFAULT nextval('public.hotelstaff_hotelstaffid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM information_schema.columns
                   WHERE table_schema='public' AND table_name='hotelstaycharges'
                     AND column_name='hotelstaychargeid' AND column_default IS NOT NULL) THEN
        ALTER TABLE public.hotelstaycharges ALTER COLUMN hotelstaychargeid SET DEFAULT nextval('public.hotelstaycharges_hotelstaychargeid_seq'::regclass);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelamenities_pkey' AND conrelid = 'public.hotelamenities'::regclass) THEN
        ALTER TABLE public.hotelamenities
        ADD CONSTRAINT hotelamenities_pkey PRIMARY KEY (hotelamenityid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelbookings_pkey' AND conrelid = 'public.hotelbookings'::regclass) THEN
        ALTER TABLE public.hotelbookings
        ADD CONSTRAINT hotelbookings_pkey PRIMARY KEY (hotelbookingid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelcashaccounts_pkey' AND conrelid = 'public.hotelcashaccounts'::regclass) THEN
        ALTER TABLE public.hotelcashaccounts
        ADD CONSTRAINT hotelcashaccounts_pkey PRIMARY KEY (hotelcashaccountid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelcheckins_pkey' AND conrelid = 'public.hotelcheckins'::regclass) THEN
        ALTER TABLE public.hotelcheckins
        ADD CONSTRAINT hotelcheckins_pkey PRIMARY KEY (hotelcheckinid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelcheckouts_pkey' AND conrelid = 'public.hotelcheckouts'::regclass) THEN
        ALTER TABLE public.hotelcheckouts
        ADD CONSTRAINT hotelcheckouts_pkey PRIMARY KEY (hotelcheckoutid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hoteldailyclosings_pkey' AND conrelid = 'public.hoteldailyclosings'::regclass) THEN
        ALTER TABLE public.hoteldailyclosings
        ADD CONSTRAINT hoteldailyclosings_pkey PRIMARY KEY (hoteldailyclosingid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelexpenses_pkey' AND conrelid = 'public.hotelexpenses'::regclass) THEN
        ALTER TABLE public.hotelexpenses
        ADD CONSTRAINT hotelexpenses_pkey PRIMARY KEY (hotelexpenseid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelfloors_pkey' AND conrelid = 'public.hotelfloors'::regclass) THEN
        ALTER TABLE public.hotelfloors
        ADD CONSTRAINT hotelfloors_pkey PRIMARY KEY (hotelfloorid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelguests_pkey' AND conrelid = 'public.hotelguests'::regclass) THEN
        ALTER TABLE public.hotelguests
        ADD CONSTRAINT hotelguests_pkey PRIMARY KEY (hotelguestid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelhousekeepingtasks_pkey' AND conrelid = 'public.hotelhousekeepingtasks'::regclass) THEN
        ALTER TABLE public.hotelhousekeepingtasks
        ADD CONSTRAINT hotelhousekeepingtasks_pkey PRIMARY KEY (hotelhousekeepingtaskid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelinventoryitems_pkey' AND conrelid = 'public.hotelinventoryitems'::regclass) THEN
        ALTER TABLE public.hotelinventoryitems
        ADD CONSTRAINT hotelinventoryitems_pkey PRIMARY KEY (hotelinventoryitemid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelinvoices_pkey' AND conrelid = 'public.hotelinvoices'::regclass) THEN
        ALTER TABLE public.hotelinvoices
        ADD CONSTRAINT hotelinvoices_pkey PRIMARY KEY (hotelinvoiceid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltymembers_farmid_hotelguestid_key' AND conrelid = 'public.hotelloyaltymembers'::regclass) THEN
        ALTER TABLE public.hotelloyaltymembers
        ADD CONSTRAINT hotelloyaltymembers_farmid_hotelguestid_key UNIQUE (farmid, hotelguestid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltymembers_farmid_membershipnumber_key' AND conrelid = 'public.hotelloyaltymembers'::regclass) THEN
        ALTER TABLE public.hotelloyaltymembers
        ADD CONSTRAINT hotelloyaltymembers_farmid_membershipnumber_key UNIQUE (farmid, membershipnumber);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltymembers_pkey' AND conrelid = 'public.hotelloyaltymembers'::regclass) THEN
        ALTER TABLE public.hotelloyaltymembers
        ADD CONSTRAINT hotelloyaltymembers_pkey PRIMARY KEY (hotelloyaltymemberid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltytransactions_pkey' AND conrelid = 'public.hotelloyaltytransactions'::regclass) THEN
        ALTER TABLE public.hotelloyaltytransactions
        ADD CONSTRAINT hotelloyaltytransactions_pkey PRIMARY KEY (hotelloyaltytransactionid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelmaintenancerequests_pkey' AND conrelid = 'public.hotelmaintenancerequests'::regclass) THEN
        ALTER TABLE public.hotelmaintenancerequests
        ADD CONSTRAINT hotelmaintenancerequests_pkey PRIMARY KEY (hotelmaintenancerequestid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelmenuitems_pkey' AND conrelid = 'public.hotelmenuitems'::regclass) THEN
        ALTER TABLE public.hotelmenuitems
        ADD CONSTRAINT hotelmenuitems_pkey PRIMARY KEY (hotelmenuitemid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelnightaudits_pkey' AND conrelid = 'public.hotelnightaudits'::regclass) THEN
        ALTER TABLE public.hotelnightaudits
        ADD CONSTRAINT hotelnightaudits_pkey PRIMARY KEY (hotelnightauditid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelpayments_pkey' AND conrelid = 'public.hotelpayments'::regclass) THEN
        ALTER TABLE public.hotelpayments
        ADD CONSTRAINT hotelpayments_pkey PRIMARY KEY (hotelpaymentid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelpayrollitems_pkey' AND conrelid = 'public.hotelpayrollitems'::regclass) THEN
        ALTER TABLE public.hotelpayrollitems
        ADD CONSTRAINT hotelpayrollitems_pkey PRIMARY KEY (hotelpayrollitemid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelpayrollruns_pkey' AND conrelid = 'public.hotelpayrollruns'::regclass) THEN
        ALTER TABLE public.hotelpayrollruns
        ADD CONSTRAINT hotelpayrollruns_pkey PRIMARY KEY (hotelpayrollrunid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelprofiles_pkey' AND conrelid = 'public.hotelprofiles'::regclass) THEN
        ALTER TABLE public.hotelprofiles
        ADD CONSTRAINT hotelprofiles_pkey PRIMARY KEY (hotelprofileid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrestaurantorderitems_pkey' AND conrelid = 'public.hotelrestaurantorderitems'::regclass) THEN
        ALTER TABLE public.hotelrestaurantorderitems
        ADD CONSTRAINT hotelrestaurantorderitems_pkey PRIMARY KEY (hotelrestaurantorderitemid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrestaurantorders_pkey' AND conrelid = 'public.hotelrestaurantorders'::regclass) THEN
        ALTER TABLE public.hotelrestaurantorders
        ADD CONSTRAINT hotelrestaurantorders_pkey PRIMARY KEY (hotelrestaurantorderid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrestauranttables_pkey' AND conrelid = 'public.hotelrestauranttables'::regclass) THEN
        ALTER TABLE public.hotelrestauranttables
        ADD CONSTRAINT hotelrestauranttables_pkey PRIMARY KEY (hotelrestauranttableid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomamenities_pkey' AND conrelid = 'public.hotelroomamenities'::regclass) THEN
        ALTER TABLE public.hotelroomamenities
        ADD CONSTRAINT hotelroomamenities_pkey PRIMARY KEY (hotelroomid, hotelamenityid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomrates_pkey' AND conrelid = 'public.hotelroomrates'::regclass) THEN
        ALTER TABLE public.hotelroomrates
        ADD CONSTRAINT hotelroomrates_pkey PRIMARY KEY (hotelroomrateid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrooms_pkey' AND conrelid = 'public.hotelrooms'::regclass) THEN
        ALTER TABLE public.hotelrooms
        ADD CONSTRAINT hotelrooms_pkey PRIMARY KEY (hotelroomid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomserviceorders_pkey' AND conrelid = 'public.hotelroomserviceorders'::regclass) THEN
        ALTER TABLE public.hotelroomserviceorders
        ADD CONSTRAINT hotelroomserviceorders_pkey PRIMARY KEY (hotelroomserviceorderid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomtypes_pkey' AND conrelid = 'public.hotelroomtypes'::regclass) THEN
        ALTER TABLE public.hotelroomtypes
        ADD CONSTRAINT hotelroomtypes_pkey PRIMARY KEY (hotelroomtypeid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelstaff_pkey' AND conrelid = 'public.hotelstaff'::regclass) THEN
        ALTER TABLE public.hotelstaff
        ADD CONSTRAINT hotelstaff_pkey PRIMARY KEY (hotelstaffid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelstaycharges_pkey' AND conrelid = 'public.hotelstaycharges'::regclass) THEN
        ALTER TABLE public.hotelstaycharges
        ADD CONSTRAINT hotelstaycharges_pkey PRIMARY KEY (hotelstaychargeid);
    END IF;
END $$;

CREATE INDEX IF NOT EXISTS ix_hotelbookings_farmid ON public.hotelbookings USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelfloors_farmid ON public.hotelfloors USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelguests_farmid ON public.hotelguests USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelloyaltymembers_farm ON public.hotelloyaltymembers USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelloyaltymembers_guest ON public.hotelloyaltymembers USING btree (hotelguestid);

CREATE INDEX IF NOT EXISTS ix_hotelloyaltytransactions_member ON public.hotelloyaltytransactions USING btree (hotelloyaltymemberid);

CREATE INDEX IF NOT EXISTS ix_hotelpayrollitems_runid ON public.hotelpayrollitems USING btree (hotelpayrollrunid);

CREATE INDEX IF NOT EXISTS ix_hotelpayrollruns_farmid ON public.hotelpayrollruns USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelrooms_farmid ON public.hotelrooms USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hotelroomtypes_farmid ON public.hotelroomtypes USING btree (farmid);

CREATE INDEX IF NOT EXISTS ix_hroi_orderid ON public.hotelrestaurantorderitems USING btree (hotelrestaurantorderid);

CREATE INDEX IF NOT EXISTS ix_hrr_farmid ON public.hotelroomrates USING btree (farmid);

CREATE UNIQUE INDEX IF NOT EXISTS ux_hna_farmdate ON public.hotelnightaudits USING btree (farmid, auditdate);

CREATE UNIQUE INDEX IF NOT EXISTS ux_hoteldailyclosings_farmdate ON public.hoteldailyclosings USING btree (farmid, closingdate);

CREATE UNIQUE INDEX IF NOT EXISTS ux_hotelprofiles_farmid ON public.hotelprofiles USING btree (farmid);

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelbookings_hotelguestid_fkey' AND conrelid = 'public.hotelbookings'::regclass) THEN
        ALTER TABLE public.hotelbookings
        ADD CONSTRAINT hotelbookings_hotelguestid_fkey FOREIGN KEY (hotelguestid) REFERENCES public.hotelguests(hotelguestid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelbookings_hotelroomid_fkey' AND conrelid = 'public.hotelbookings'::regclass) THEN
        ALTER TABLE public.hotelbookings
        ADD CONSTRAINT hotelbookings_hotelroomid_fkey FOREIGN KEY (hotelroomid) REFERENCES public.hotelrooms(hotelroomid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelbookings_hotelroomtypeid_fkey' AND conrelid = 'public.hotelbookings'::regclass) THEN
        ALTER TABLE public.hotelbookings
        ADD CONSTRAINT hotelbookings_hotelroomtypeid_fkey FOREIGN KEY (hotelroomtypeid) REFERENCES public.hotelroomtypes(hotelroomtypeid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltymembers_hotelguestid_fkey' AND conrelid = 'public.hotelloyaltymembers'::regclass) THEN
        ALTER TABLE public.hotelloyaltymembers
        ADD CONSTRAINT hotelloyaltymembers_hotelguestid_fkey FOREIGN KEY (hotelguestid) REFERENCES public.hotelguests(hotelguestid) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltytransactions_hotelbookingid_fkey' AND conrelid = 'public.hotelloyaltytransactions'::regclass) THEN
        ALTER TABLE public.hotelloyaltytransactions
        ADD CONSTRAINT hotelloyaltytransactions_hotelbookingid_fkey FOREIGN KEY (hotelbookingid) REFERENCES public.hotelbookings(hotelbookingid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelloyaltytransactions_hotelloyaltymemberid_fkey' AND conrelid = 'public.hotelloyaltytransactions'::regclass) THEN
        ALTER TABLE public.hotelloyaltytransactions
        ADD CONSTRAINT hotelloyaltytransactions_hotelloyaltymemberid_fkey FOREIGN KEY (hotelloyaltymemberid) REFERENCES public.hotelloyaltymembers(hotelloyaltymemberid) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelpayrollitems_hotelpayrollrunid_fkey' AND conrelid = 'public.hotelpayrollitems'::regclass) THEN
        ALTER TABLE public.hotelpayrollitems
        ADD CONSTRAINT hotelpayrollitems_hotelpayrollrunid_fkey FOREIGN KEY (hotelpayrollrunid) REFERENCES public.hotelpayrollruns(hotelpayrollrunid) ON DELETE CASCADE;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrestaurantorderitems_hotelmenuitemid_fkey' AND conrelid = 'public.hotelrestaurantorderitems'::regclass) THEN
        ALTER TABLE public.hotelrestaurantorderitems
        ADD CONSTRAINT hotelrestaurantorderitems_hotelmenuitemid_fkey FOREIGN KEY (hotelmenuitemid) REFERENCES public.hotelmenuitems(hotelmenuitemid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrestaurantorderitems_hotelrestaurantorderid_fkey' AND conrelid = 'public.hotelrestaurantorderitems'::regclass) THEN
        ALTER TABLE public.hotelrestaurantorderitems
        ADD CONSTRAINT hotelrestaurantorderitems_hotelrestaurantorderid_fkey FOREIGN KEY (hotelrestaurantorderid) REFERENCES public.hotelrestaurantorders(hotelrestaurantorderid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomamenities_hotelamenityid_fkey' AND conrelid = 'public.hotelroomamenities'::regclass) THEN
        ALTER TABLE public.hotelroomamenities
        ADD CONSTRAINT hotelroomamenities_hotelamenityid_fkey FOREIGN KEY (hotelamenityid) REFERENCES public.hotelamenities(hotelamenityid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomamenities_hotelroomid_fkey' AND conrelid = 'public.hotelroomamenities'::regclass) THEN
        ALTER TABLE public.hotelroomamenities
        ADD CONSTRAINT hotelroomamenities_hotelroomid_fkey FOREIGN KEY (hotelroomid) REFERENCES public.hotelrooms(hotelroomid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelroomrates_hotelroomtypeid_fkey' AND conrelid = 'public.hotelroomrates'::regclass) THEN
        ALTER TABLE public.hotelroomrates
        ADD CONSTRAINT hotelroomrates_hotelroomtypeid_fkey FOREIGN KEY (hotelroomtypeid) REFERENCES public.hotelroomtypes(hotelroomtypeid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrooms_hotelfloorid_fkey' AND conrelid = 'public.hotelrooms'::regclass) THEN
        ALTER TABLE public.hotelrooms
        ADD CONSTRAINT hotelrooms_hotelfloorid_fkey FOREIGN KEY (hotelfloorid) REFERENCES public.hotelfloors(hotelfloorid);
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_constraint
                   WHERE conname = 'hotelrooms_hotelroomtypeid_fkey' AND conrelid = 'public.hotelrooms'::regclass) THEN
        ALTER TABLE public.hotelrooms
        ADD CONSTRAINT hotelrooms_hotelroomtypeid_fkey FOREIGN KEY (hotelroomtypeid) REFERENCES public.hotelroomtypes(hotelroomtypeid);
    END IF;
END $$;

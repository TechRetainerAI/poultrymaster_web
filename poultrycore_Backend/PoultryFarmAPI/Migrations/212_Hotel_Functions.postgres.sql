-- =============================================================================
-- Migration 212: Hotel Management System - Stored Procedures  (PostgreSQL)
-- =============================================================================
-- The 40 sphotel_* functions, dumped from dev's live schema on 2026-08-26.
-- See 211_Hotel_Schema.postgres.sql for why these are generated rather than
-- ported from the SQL Server originals.
--
-- Idempotent: every function is CREATE OR REPLACE. Run 211 first -- these
-- reference the tables it creates.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.sphotel_amenity_delete(p_hotelamenityid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelroomamenities WHERE hotelamenityid=p_hotelamenityid AND farmid=p_farmid; DELETE FROM hotelamenities WHERE hotelamenityid=p_hotelamenityid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_amenity_insert(p_farmid text, p_name text, p_category text DEFAULT NULL::text, p_icon text DEFAULT NULL::text, p_isactive boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelamenities(farmid,name,category,icon,isactive) VALUES(p_farmid,p_name,p_category,p_icon,p_isactive) RETURNING hotelamenityid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_amenity_list(p_farmid text)
 RETURNS SETOF hotelamenities
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelamenities WHERE farmid=p_farmid ORDER BY category, name; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_amenity_update(p_hotelamenityid integer, p_farmid text, p_name text, p_category text DEFAULT NULL::text, p_icon text DEFAULT NULL::text, p_isactive boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelamenities SET name=p_name,category=p_category,icon=p_icon,isactive=p_isactive,updatedat=NOW() WHERE hotelamenityid=p_hotelamenityid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_cancel(p_hotelbookingid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelbookings SET status='Cancelled',updatedat=NOW() WHERE hotelbookingid=p_hotelbookingid AND farmid=p_farmid; UPDATE hotelrooms SET status='Available',updatedat=NOW() FROM hotelbookings b WHERE hotelrooms.hotelroomid=b.hotelroomid AND b.hotelbookingid=p_hotelbookingid AND b.farmid=p_farmid AND hotelrooms.status='Reserved'; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_get(p_hotelbookingid integer, p_farmid text)
 RETURNS TABLE("HotelBookingId" integer, "FarmId" text, "BookingRef" character varying, "HotelGuestId" integer, "HotelRoomId" integer, "HotelRoomTypeId" integer, "CheckInDate" date, "CheckOutDate" date, "NumberOfGuests" integer, "Adults" integer, "Children" integer, "NightlyRate" numeric, "TotalAmount" numeric, "Status" character varying, "Source" character varying, "SpecialRequests" text, "CreatedBy" text, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "GuestFirstName" character varying, "GuestLastName" character varying, "GuestPhone" character varying, "GuestEmail" character varying, "RoomNumber" character varying, "RoomTypeName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT b.hotelbookingid, b.farmid, b.bookingref, b.hotelguestid, b.hotelroomid, b.hotelroomtypeid, b.checkindate, b.checkoutdate, b.numberofguests, b.adults, b.children, b.nightlyrate, b.totalamount, b.status, b.source, b.specialrequests, b.createdby, b.createdat, b.updatedat, g.firstname, g.lastname, g.phone, g.email, r.roomnumber, rt.name FROM hotelbookings b JOIN hotelguests g ON b.hotelguestid=g.hotelguestid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid WHERE b.hotelbookingid=p_hotelbookingid AND b.farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_insert(p_farmid text, p_bookingref text, p_hotelguestid integer, p_hotelroomid integer DEFAULT NULL::integer, p_hotelroomtypeid integer DEFAULT NULL::integer, p_checkindate date DEFAULT NULL::date, p_checkoutdate date DEFAULT NULL::date, p_numberofguests integer DEFAULT 1, p_adults integer DEFAULT 1, p_children integer DEFAULT 0, p_nightlyrate numeric DEFAULT 0, p_totalamount numeric DEFAULT 0, p_status text DEFAULT 'Confirmed'::text, p_source text DEFAULT 'WalkIn'::text, p_specialrequests text DEFAULT NULL::text, p_createdby text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelbookings(farmid,bookingref,hotelguestid,hotelroomid,hotelroomtypeid,checkindate,checkoutdate,numberofguests,adults,children,nightlyrate,totalamount,status,source,specialrequests,createdby) VALUES(p_farmid,p_bookingref,p_hotelguestid,p_hotelroomid,p_hotelroomtypeid,p_checkindate,p_checkoutdate,p_numberofguests,p_adults,p_children,p_nightlyrate,p_totalamount,p_status,p_source,p_specialrequests,p_createdby) RETURNING hotelbookingid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_list(p_farmid text)
 RETURNS TABLE("HotelBookingId" integer, "FarmId" text, "BookingRef" character varying, "HotelGuestId" integer, "HotelRoomId" integer, "HotelRoomTypeId" integer, "CheckInDate" date, "CheckOutDate" date, "NumberOfGuests" integer, "Adults" integer, "Children" integer, "NightlyRate" numeric, "TotalAmount" numeric, "Status" character varying, "Source" character varying, "SpecialRequests" text, "CreatedBy" text, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "GuestFirstName" character varying, "GuestLastName" character varying, "GuestPhone" character varying, "RoomNumber" character varying, "RoomTypeName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT b.hotelbookingid, b.farmid, b.bookingref, b.hotelguestid, b.hotelroomid, b.hotelroomtypeid, b.checkindate, b.checkoutdate, b.numberofguests, b.adults, b.children, b.nightlyrate, b.totalamount, b.status, b.source, b.specialrequests, b.createdby, b.createdat, b.updatedat, g.firstname, g.lastname, g.phone, r.roomnumber, rt.name FROM hotelbookings b JOIN hotelguests g ON b.hotelguestid=g.hotelguestid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid WHERE b.farmid=p_farmid ORDER BY b.checkindate DESC; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_todayarrivals(p_farmid text)
 RETURNS TABLE("HotelBookingId" integer, "FarmId" text, "BookingRef" character varying, "HotelGuestId" integer, "HotelRoomId" integer, "HotelRoomTypeId" integer, "CheckInDate" date, "CheckOutDate" date, "NumberOfGuests" integer, "Adults" integer, "Children" integer, "NightlyRate" numeric, "TotalAmount" numeric, "Status" character varying, "Source" character varying, "SpecialRequests" text, "CreatedBy" text, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "GuestFirstName" character varying, "GuestLastName" character varying, "GuestPhone" character varying, "RoomNumber" character varying, "RoomTypeName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT b.hotelbookingid, b.farmid, b.bookingref, b.hotelguestid, b.hotelroomid, b.hotelroomtypeid, b.checkindate, b.checkoutdate, b.numberofguests, b.adults, b.children, b.nightlyrate, b.totalamount, b.status, b.source, b.specialrequests, b.createdby, b.createdat, b.updatedat, g.firstname, g.lastname, g.phone, r.roomnumber, rt.name FROM hotelbookings b JOIN hotelguests g ON b.hotelguestid=g.hotelguestid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid WHERE b.farmid=p_farmid AND b.checkindate=CURRENT_DATE AND b.status='Confirmed'; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_todaydepartures(p_farmid text)
 RETURNS TABLE("HotelBookingId" integer, "FarmId" text, "BookingRef" character varying, "HotelGuestId" integer, "HotelRoomId" integer, "HotelRoomTypeId" integer, "CheckInDate" date, "CheckOutDate" date, "NumberOfGuests" integer, "Adults" integer, "Children" integer, "NightlyRate" numeric, "TotalAmount" numeric, "Status" character varying, "Source" character varying, "SpecialRequests" text, "CreatedBy" text, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "GuestFirstName" character varying, "GuestLastName" character varying, "GuestPhone" character varying, "RoomNumber" character varying, "RoomTypeName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT b.hotelbookingid, b.farmid, b.bookingref, b.hotelguestid, b.hotelroomid, b.hotelroomtypeid, b.checkindate, b.checkoutdate, b.numberofguests, b.adults, b.children, b.nightlyrate, b.totalamount, b.status, b.source, b.specialrequests, b.createdby, b.createdat, b.updatedat, g.firstname, g.lastname, g.phone, r.roomnumber, rt.name FROM hotelbookings b JOIN hotelguests g ON b.hotelguestid=g.hotelguestid LEFT JOIN hotelrooms r ON b.hotelroomid=r.hotelroomid JOIN hotelroomtypes rt ON b.hotelroomtypeid=rt.hotelroomtypeid WHERE b.farmid=p_farmid AND b.checkoutdate=CURRENT_DATE AND b.status='CheckedIn'; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_update(p_hotelbookingid integer, p_farmid text, p_hotelroomid integer DEFAULT NULL::integer, p_hotelroomtypeid integer DEFAULT NULL::integer, p_checkindate date DEFAULT NULL::date, p_checkoutdate date DEFAULT NULL::date, p_numberofguests integer DEFAULT 1, p_adults integer DEFAULT 1, p_children integer DEFAULT 0, p_nightlyrate numeric DEFAULT 0, p_totalamount numeric DEFAULT 0, p_source text DEFAULT 'WalkIn'::text, p_specialrequests text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelbookings SET hotelroomid=p_hotelroomid,hotelroomtypeid=p_hotelroomtypeid,checkindate=p_checkindate,checkoutdate=p_checkoutdate,numberofguests=p_numberofguests,adults=p_adults,children=p_children,nightlyrate=p_nightlyrate,totalamount=p_totalamount,source=p_source,specialrequests=p_specialrequests,updatedat=NOW() WHERE hotelbookingid=p_hotelbookingid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_booking_updatestatus(p_hotelbookingid integer, p_farmid text, p_status text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelbookings SET status=p_status,updatedat=NOW() WHERE hotelbookingid=p_hotelbookingid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_floor_delete(p_hotelfloorid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelfloors WHERE hotelfloorid=p_hotelfloorid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_floor_insert(p_farmid text, p_floornumber integer, p_name text, p_isactive boolean DEFAULT true, p_sortorder integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelfloors(farmid,floornumber,name,isactive,sortorder) VALUES(p_farmid,p_floornumber,p_name,p_isactive,p_sortorder) RETURNING hotelfloorid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_floor_list(p_farmid text)
 RETURNS SETOF hotelfloors
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelfloors WHERE farmid=p_farmid ORDER BY sortorder, floornumber; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_floor_update(p_hotelfloorid integer, p_farmid text, p_floornumber integer, p_name text, p_isactive boolean DEFAULT true, p_sortorder integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelfloors SET floornumber=p_floornumber,name=p_name,isactive=p_isactive,sortorder=p_sortorder,updatedat=NOW() WHERE hotelfloorid=p_hotelfloorid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_delete(p_hotelguestid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelguests WHERE hotelguestid=p_hotelguestid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_get(p_hotelguestid integer, p_farmid text)
 RETURNS SETOF hotelguests
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelguests WHERE hotelguestid=p_hotelguestid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_insert(p_farmid text, p_firstname text, p_lastname text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_idtype text DEFAULT NULL::text, p_idnumber text DEFAULT NULL::text, p_nationality text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_dateofbirth date DEFAULT NULL::date, p_notes text DEFAULT NULL::text, p_isvip boolean DEFAULT false)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelguests(farmid,firstname,lastname,email,phone,idtype,idnumber,nationality,address,dateofbirth,notes,isvip) VALUES(p_farmid,p_firstname,p_lastname,p_email,p_phone,p_idtype,p_idnumber,p_nationality,p_address,p_dateofbirth,p_notes,p_isvip) RETURNING hotelguestid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_list(p_farmid text)
 RETURNS SETOF hotelguests
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelguests WHERE farmid=p_farmid ORDER BY lastname, firstname; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_search(p_farmid text, p_query text)
 RETURNS SETOF hotelguests
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelguests WHERE farmid=p_farmid AND (firstname ILIKE '%'||p_query||'%' OR lastname ILIKE '%'||p_query||'%' OR email ILIKE '%'||p_query||'%' OR phone ILIKE '%'||p_query||'%') ORDER BY lastname, firstname; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_guest_update(p_hotelguestid integer, p_farmid text, p_firstname text, p_lastname text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_idtype text DEFAULT NULL::text, p_idnumber text DEFAULT NULL::text, p_nationality text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_dateofbirth date DEFAULT NULL::date, p_notes text DEFAULT NULL::text, p_isvip boolean DEFAULT false)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelguests SET firstname=p_firstname,lastname=p_lastname,email=p_email,phone=p_phone,idtype=p_idtype,idnumber=p_idnumber,nationality=p_nationality,address=p_address,dateofbirth=p_dateofbirth,notes=p_notes,isvip=p_isvip,updatedat=NOW() WHERE hotelguestid=p_hotelguestid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_housekeeping_list(p_farmid text)
 RETURNS TABLE("HotelHousekeepingTaskId" integer, "FarmId" text, "HotelRoomId" integer, "TaskType" character varying, "Priority" character varying, "Status" character varying, "AssignedTo" character varying, "ScheduledDate" date, "StartedAt" timestamp with time zone, "CompletedAt" timestamp with time zone, "InspectedBy" character varying, "InspectionNotes" text, "Notes" text, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "RoomNumber" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT t.hotelhousekeepingtaskid, t.farmid, t.hotelroomid, t.tasktype, t.priority, t.status, t.assignedto, t.scheduleddate, t.startedat, t.completedat, t.inspectedby, t.inspectionnotes, t.notes, t.createdat, t.updatedat, r.roomnumber FROM hotelhousekeepingtasks t JOIN hotelrooms r ON t.hotelroomid=r.hotelroomid WHERE t.farmid=p_farmid ORDER BY CASE t.priority WHEN 'Urgent' THEN 1 WHEN 'High' THEN 2 WHEN 'Normal' THEN 3 ELSE 4 END, t.scheduleddate; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_profile_get(p_farmid text)
 RETURNS SETOF hotelprofiles
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelprofiles WHERE farmid = p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_profile_upsert(p_farmid text, p_hotelname text, p_address text DEFAULT NULL::text, p_city text DEFAULT NULL::text, p_country text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_email text DEFAULT NULL::text, p_starrating integer DEFAULT NULL::integer, p_checkintime text DEFAULT '14:00'::text, p_checkouttime text DEFAULT '12:00'::text, p_defaultcurrency text DEFAULT 'GHS'::text, p_taxrate numeric DEFAULT 0, p_servicechargerate numeric DEFAULT 0, p_timezone text DEFAULT NULL::text, p_logourl text DEFAULT NULL::text, p_description text DEFAULT NULL::text)
 RETURNS SETOF hotelprofiles
 LANGUAGE plpgsql
AS $function$ BEGIN IF EXISTS (SELECT 1 FROM hotelprofiles WHERE farmid = p_farmid) THEN UPDATE hotelprofiles SET hotelname=p_hotelname, address=p_address, city=p_city, country=p_country, phone=p_phone, email=p_email, starrating=p_starrating, checkintime=p_checkintime, checkouttime=p_checkouttime, defaultcurrency=p_defaultcurrency, taxrate=p_taxrate, servicechargerate=p_servicechargerate, timezone=p_timezone, logourl=p_logourl, description=p_description, updatedat=NOW() WHERE farmid=p_farmid; ELSE INSERT INTO hotelprofiles(farmid,hotelname,address,city,country,phone,email,starrating,checkintime,checkouttime,defaultcurrency,taxrate,servicechargerate,timezone,logourl,description) VALUES(p_farmid,p_hotelname,p_address,p_city,p_country,p_phone,p_email,p_starrating,p_checkintime,p_checkouttime,p_defaultcurrency,p_taxrate,p_servicechargerate,p_timezone,p_logourl,p_description); END IF; RETURN QUERY SELECT * FROM hotelprofiles WHERE farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_delete(p_hotelroomid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelroomamenities WHERE hotelroomid=p_hotelroomid AND farmid=p_farmid; DELETE FROM hotelrooms WHERE hotelroomid=p_hotelroomid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_get(p_hotelroomid integer, p_farmid text)
 RETURNS TABLE("HotelRoomId" integer, "FarmId" text, "RoomNumber" character varying, "HotelRoomTypeId" integer, "HotelFloorId" integer, "Status" character varying, "Description" character varying, "IsActive" boolean, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "RoomTypeName" character varying, "BaseRate" numeric, "MaxOccupancy" integer, "BedType" character varying, "FloorNumber" integer, "FloorName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT r.hotelroomid, r.farmid, r.roomnumber, r.hotelroomtypeid, r.hotelfloorid, r.status, r.description, r.isactive, r.createdat, r.updatedat, rt.name, rt.baserate, rt.maxoccupancy, rt.bedtype, f.floornumber, f.name FROM hotelrooms r JOIN hotelroomtypes rt ON r.hotelroomtypeid=rt.hotelroomtypeid LEFT JOIN hotelfloors f ON r.hotelfloorid=f.hotelfloorid WHERE r.hotelroomid=p_hotelroomid AND r.farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_insert(p_farmid text, p_roomnumber text, p_hotelroomtypeid integer, p_hotelfloorid integer DEFAULT NULL::integer, p_status text DEFAULT 'Available'::text, p_description text DEFAULT NULL::text, p_isactive boolean DEFAULT true)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelrooms(farmid,roomnumber,hotelroomtypeid,hotelfloorid,status,description,isactive) VALUES(p_farmid,p_roomnumber,p_hotelroomtypeid,p_hotelfloorid,p_status,p_description,p_isactive) RETURNING hotelroomid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_list(p_farmid text)
 RETURNS TABLE("HotelRoomId" integer, "FarmId" text, "RoomNumber" character varying, "HotelRoomTypeId" integer, "HotelFloorId" integer, "Status" character varying, "Description" character varying, "IsActive" boolean, "CreatedAt" timestamp with time zone, "UpdatedAt" timestamp with time zone, "RoomTypeName" character varying, "BaseRate" numeric, "MaxOccupancy" integer, "BedType" character varying, "FloorNumber" integer, "FloorName" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT r.hotelroomid, r.farmid, r.roomnumber, r.hotelroomtypeid, r.hotelfloorid, r.status, r.description, r.isactive, r.createdat, r.updatedat, rt.name, rt.baserate, rt.maxoccupancy, rt.bedtype, f.floornumber, f.name FROM hotelrooms r JOIN hotelroomtypes rt ON r.hotelroomtypeid=rt.hotelroomtypeid LEFT JOIN hotelfloors f ON r.hotelfloorid=f.hotelfloorid WHERE r.farmid=p_farmid ORDER BY f.sortorder, f.floornumber, r.roomnumber; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_statussummary(p_farmid text)
 RETURNS TABLE("Status" character varying, "RoomCount" bigint)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT r.status, COUNT(*) FROM hotelrooms r WHERE r.farmid=p_farmid AND r.isactive=TRUE GROUP BY r.status; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_update(p_hotelroomid integer, p_farmid text, p_roomnumber text, p_hotelroomtypeid integer, p_hotelfloorid integer DEFAULT NULL::integer, p_description text DEFAULT NULL::text, p_isactive boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelrooms SET roomnumber=p_roomnumber,hotelroomtypeid=p_hotelroomtypeid,hotelfloorid=p_hotelfloorid,description=p_description,isactive=p_isactive,updatedat=NOW() WHERE hotelroomid=p_hotelroomid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_room_updatestatus(p_hotelroomid integer, p_farmid text, p_status text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelrooms SET status=p_status,updatedat=NOW() WHERE hotelroomid=p_hotelroomid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomamenity_listbyroom(p_hotelroomid integer, p_farmid text)
 RETURNS TABLE("HotelRoomId" integer, "HotelAmenityId" integer, "FarmId" text, "Name" character varying, "Category" character varying, "Icon" character varying)
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT ra.hotelroomid, ra.hotelamenityid, ra.farmid, a.name, a.category, a.icon FROM hotelroomamenities ra JOIN hotelamenities a ON ra.hotelamenityid=a.hotelamenityid WHERE ra.hotelroomid=p_hotelroomid AND ra.farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomamenity_remove(p_hotelroomid integer, p_hotelamenityid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelroomamenities WHERE hotelroomid=p_hotelroomid AND hotelamenityid=p_hotelamenityid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomamenity_set(p_hotelroomid integer, p_hotelamenityid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN INSERT INTO hotelroomamenities(hotelroomid,hotelamenityid,farmid) VALUES(p_hotelroomid,p_hotelamenityid,p_farmid) ON CONFLICT DO NOTHING; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomtype_delete(p_hotelroomtypeid integer, p_farmid text)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN DELETE FROM hotelroomtypes WHERE hotelroomtypeid=p_hotelroomtypeid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomtype_get(p_hotelroomtypeid integer, p_farmid text)
 RETURNS SETOF hotelroomtypes
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelroomtypes WHERE hotelroomtypeid=p_hotelroomtypeid AND farmid=p_farmid; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomtype_insert(p_farmid text, p_name text, p_description text DEFAULT NULL::text, p_baserate numeric DEFAULT 0, p_maxoccupancy integer DEFAULT 2, p_bedtype text DEFAULT NULL::text, p_imageurl text DEFAULT NULL::text, p_isactive boolean DEFAULT true, p_sortorder integer DEFAULT 0)
 RETURNS integer
 LANGUAGE plpgsql
AS $function$ DECLARE v_id INT; BEGIN INSERT INTO hotelroomtypes(farmid,name,description,baserate,maxoccupancy,bedtype,imageurl,isactive,sortorder) VALUES(p_farmid,p_name,p_description,p_baserate,p_maxoccupancy,p_bedtype,p_imageurl,p_isactive,p_sortorder) RETURNING hotelroomtypeid INTO v_id; RETURN v_id; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomtype_list(p_farmid text)
 RETURNS SETOF hotelroomtypes
 LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY SELECT * FROM hotelroomtypes WHERE farmid=p_farmid ORDER BY sortorder, name; END; $function$
;

CREATE OR REPLACE FUNCTION public.sphotel_roomtype_update(p_hotelroomtypeid integer, p_farmid text, p_name text, p_description text DEFAULT NULL::text, p_baserate numeric DEFAULT 0, p_maxoccupancy integer DEFAULT 2, p_bedtype text DEFAULT NULL::text, p_imageurl text DEFAULT NULL::text, p_isactive boolean DEFAULT true, p_sortorder integer DEFAULT 0)
 RETURNS void
 LANGUAGE plpgsql
AS $function$ BEGIN UPDATE hotelroomtypes SET name=p_name,description=p_description,baserate=p_baserate,maxoccupancy=p_maxoccupancy,bedtype=p_bedtype,imageurl=p_imageurl,isactive=p_isactive,sortorder=p_sortorder,updatedat=NOW() WHERE hotelroomtypeid=p_hotelroomtypeid AND farmid=p_farmid; END; $function$
;




SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;


COMMENT ON SCHEMA "public" IS 'standard public schema';



CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";






CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";






CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";






CREATE OR REPLACE FUNCTION "public"."current_role_is"("target_role" "text") RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select role = target_role from public.profiles where id = auth.uid()),
    false
  );
$$;


ALTER FUNCTION "public"."current_role_is"("target_role" "text") OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_delivery_pricing"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
declare
  pricing record;
begin
  -- Lock down everything that defines *what* the delivery is once it
  -- exists, unless an admin is making the change. Status, driver_id,
  -- timestamps, and notes remain freely updatable for the normal
  -- claim -> pickup -> deliver flow.
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.customer_id      := old.customer_id;
    new.partner_id        := old.partner_id;
    new.category          := old.category;
    new.pickup_address     := old.pickup_address;
    new.pickup_lat        := old.pickup_lat;
    new.pickup_lng        := old.pickup_lng;
    new.dropoff_address    := old.dropoff_address;
    new.dropoff_lat       := old.dropoff_lat;
    new.dropoff_lng       := old.dropoff_lng;
    new.distance_miles     := old.distance_miles;
    new.requested_at      := old.requested_at;
  end if;

  -- Admins can hand-edit zone/fee/payout/cut directly (e.g. comping a
  -- delivery); everyone else gets it recomputed from distance_miles,
  -- full stop.
  if not public.is_admin() then
    select * into pricing from public.zone_pricing(new.distance_miles);
    if pricing.zone is null then
      raise exception 'OUTSIDE_SERVICE_AREA';
    end if;
    new.zone_assigned := pricing.zone;
    new.fee_charged   := pricing.fee;
    new.driver_payout := pricing.driver_payout;
    new.platform_cut  := pricing.platform_cut;
  end if;

  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_delivery_pricing"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."enforce_partner_admin_fields"() RETURNS "trigger"
    LANGUAGE "plpgsql"
    AS $$
begin
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.approved             := old.approved;
    new.founding_merchant    := old.founding_merchant;
    new.onboarding_fee_paid  := old.onboarding_fee_paid;
    new.joined_during_pilot  := old.joined_during_pilot;
    new.profile_id           := old.profile_id;
  end if;
  return new;
end;
$$;


ALTER FUNCTION "public"."enforce_partner_admin_fields"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."handle_new_user"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$
begin
  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'role', 'customer'),
    new.raw_user_meta_data->>'full_name'
  );
  return new;
end;
$$;


ALTER FUNCTION "public"."handle_new_user"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."is_admin"() RETURNS boolean
    LANGUAGE "sql" STABLE SECURITY DEFINER
    SET "search_path" TO 'public'
    AS $$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$$;


ALTER FUNCTION "public"."is_admin"() OWNER TO "postgres";


CREATE OR REPLACE FUNCTION "public"."zone_pricing"("miles" double precision) RETURNS TABLE("zone" integer, "fee" numeric, "driver_payout" numeric, "platform_cut" numeric)
    LANGUAGE "sql" IMMUTABLE
    AS $$
  select
    case
      when miles <= 5  then 1
      when miles <= 10 then 2
      when miles <= 20 then 3
      else null
    end as zone,
    case
      when miles <= 5  then 8::numeric
      when miles <= 10 then 11::numeric
      when miles <= 20 then 15::numeric
      else null
    end as fee,
    case
      when miles <= 5  then 6.00::numeric
      when miles <= 10 then 8.25::numeric
      when miles <= 20 then 11.25::numeric
      else null
    end as driver_payout,
    case
      when miles <= 5  then 2.00::numeric
      when miles <= 10 then 2.75::numeric
      when miles <= 20 then 3.75::numeric
      else null
    end as platform_cut;
$$;


ALTER FUNCTION "public"."zone_pricing"("miles" double precision) OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";


CREATE TABLE IF NOT EXISTS "public"."deliveries" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "customer_id" "uuid",
    "driver_id" "uuid",
    "partner_id" "uuid",
    "status" "text" DEFAULT 'pending'::"text",
    "category" "text" NOT NULL,
    "pickup_address" "text" NOT NULL,
    "pickup_lat" double precision NOT NULL,
    "pickup_lng" double precision NOT NULL,
    "dropoff_address" "text" NOT NULL,
    "dropoff_lat" double precision NOT NULL,
    "dropoff_lng" double precision NOT NULL,
    "distance_miles" double precision,
    "zone_assigned" integer,
    "fee_charged" numeric(10,2),
    "driver_payout" numeric(10,2),
    "platform_cut" numeric(10,2),
    "estimated_duration_minutes" integer,
    "actual_duration_minutes" integer,
    "route_polyline" "text",
    "requested_at" timestamp with time zone DEFAULT "now"(),
    "claimed_at" timestamp with time zone,
    "picked_up_at" timestamp with time zone,
    "delivered_at" timestamp with time zone,
    "notes" "text",
    CONSTRAINT "deliveries_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'claimed'::"text", 'in_progress'::"text", 'completed'::"text", 'cancelled'::"text"]))),
    CONSTRAINT "deliveries_zone_assigned_check" CHECK (("zone_assigned" = ANY (ARRAY[1, 2, 3])))
);


ALTER TABLE "public"."deliveries" OWNER TO "postgres";


COMMENT ON COLUMN "public"."deliveries"."distance_miles" IS 'Driving distance in miles from the Mapbox Directions API, calculated at request time.';



CREATE TABLE IF NOT EXISTS "public"."earnings" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "driver_id" "uuid",
    "delivery_id" "uuid",
    "amount" numeric(10,2) NOT NULL,
    "platform_cut" numeric(10,2) NOT NULL,
    "paid_out" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."earnings" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."menu_items" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "partner_id" "uuid",
    "name" "text" NOT NULL,
    "description" "text",
    "price" numeric(10,2) NOT NULL,
    "category" "text",
    "photo_url" "text",
    "active" boolean DEFAULT true,
    "created_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."menu_items" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."partner_applications" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "business_name" "text" NOT NULL,
    "contact_name" "text" NOT NULL,
    "contact_email" "text" NOT NULL,
    "contact_phone" "text" NOT NULL,
    "address" "text" NOT NULL,
    "pos_system" "text",
    "notes" "text",
    "status" "text" DEFAULT 'pending'::"text",
    "submitted_at" timestamp with time zone DEFAULT "now"(),
    CONSTRAINT "partner_applications_status_check" CHECK (("status" = ANY (ARRAY['pending'::"text", 'approved'::"text", 'rejected'::"text"])))
);


ALTER TABLE "public"."partner_applications" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."partners" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "profile_id" "uuid",
    "business_name" "text" NOT NULL,
    "address" "text" NOT NULL,
    "lat" double precision,
    "lng" double precision,
    "pickup_notes" "text",
    "pos_system" "text",
    "approved" boolean DEFAULT false,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "founding_merchant" boolean DEFAULT false,
    "onboarding_fee_paid" boolean DEFAULT false,
    "joined_during_pilot" boolean DEFAULT false
);


ALTER TABLE "public"."partners" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."profiles" (
    "id" "uuid" NOT NULL,
    "role" "text" NOT NULL,
    "full_name" "text",
    "phone" "text",
    "created_at" timestamp with time zone DEFAULT "now"(),
    "is_admin" boolean DEFAULT false NOT NULL,
    CONSTRAINT "profiles_role_check" CHECK (("role" = ANY (ARRAY['customer'::"text", 'driver'::"text", 'partner'::"text"])))
);


ALTER TABLE "public"."profiles" OWNER TO "postgres";


CREATE TABLE IF NOT EXISTS "public"."route_points" (
    "id" "uuid" DEFAULT "extensions"."uuid_generate_v4"() NOT NULL,
    "delivery_id" "uuid",
    "lat" double precision NOT NULL,
    "lng" double precision NOT NULL,
    "driver_speed" double precision,
    "recorded_at" timestamp with time zone DEFAULT "now"()
);


ALTER TABLE "public"."route_points" OWNER TO "postgres";


ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."earnings"
    ADD CONSTRAINT "earnings_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."menu_items"
    ADD CONSTRAINT "menu_items_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partner_applications"
    ADD CONSTRAINT "partner_applications_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."partners"
    ADD CONSTRAINT "partners_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_pkey" PRIMARY KEY ("id");



ALTER TABLE ONLY "public"."route_points"
    ADD CONSTRAINT "route_points_pkey" PRIMARY KEY ("id");



CREATE OR REPLACE TRIGGER "trg_enforce_delivery_pricing" BEFORE INSERT OR UPDATE ON "public"."deliveries" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_delivery_pricing"();



CREATE OR REPLACE TRIGGER "trg_enforce_partner_admin_fields" BEFORE UPDATE ON "public"."partners" FOR EACH ROW EXECUTE FUNCTION "public"."enforce_partner_admin_fields"();



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_customer_id_fkey" FOREIGN KEY ("customer_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."deliveries"
    ADD CONSTRAINT "deliveries_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id");



ALTER TABLE ONLY "public"."earnings"
    ADD CONSTRAINT "earnings_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "public"."deliveries"("id");



ALTER TABLE ONLY "public"."earnings"
    ADD CONSTRAINT "earnings_driver_id_fkey" FOREIGN KEY ("driver_id") REFERENCES "public"."profiles"("id");



ALTER TABLE ONLY "public"."menu_items"
    ADD CONSTRAINT "menu_items_partner_id_fkey" FOREIGN KEY ("partner_id") REFERENCES "public"."partners"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."partners"
    ADD CONSTRAINT "partners_profile_id_fkey" FOREIGN KEY ("profile_id") REFERENCES "public"."profiles"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."profiles"
    ADD CONSTRAINT "profiles_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;



ALTER TABLE ONLY "public"."route_points"
    ADD CONSTRAINT "route_points_delivery_id_fkey" FOREIGN KEY ("delivery_id") REFERENCES "public"."deliveries"("id") ON DELETE CASCADE;



CREATE POLICY "Admin can manage menu items" ON "public"."menu_items" USING ((("auth"."jwt"() ->> 'email'::"text") = 'sivalkmedia@gmail.com'::"text")) WITH CHECK ((("auth"."jwt"() ->> 'email'::"text") = 'sivalkmedia@gmail.com'::"text"));



CREATE POLICY "Admin can manage partners" ON "public"."partners" USING ((("auth"."jwt"() ->> 'email'::"text") = 'sivalkmedia@gmail.com'::"text")) WITH CHECK ((("auth"."jwt"() ->> 'email'::"text") = 'sivalkmedia@gmail.com'::"text"));



CREATE POLICY "Anyone can submit partner application" ON "public"."partner_applications" FOR INSERT WITH CHECK (true);



CREATE POLICY "Anyone can view active menu items" ON "public"."menu_items" FOR SELECT USING (("active" = true));



CREATE POLICY "Anyone can view approved partners" ON "public"."partners" FOR SELECT USING (("approved" = true));



CREATE POLICY "Customers can create deliveries" ON "public"."deliveries" FOR INSERT WITH CHECK (("auth"."uid"() = "customer_id"));



CREATE POLICY "Customers see own deliveries" ON "public"."deliveries" FOR SELECT USING (("auth"."uid"() = "customer_id"));



CREATE POLICY "Drivers can insert route points" ON "public"."route_points" FOR INSERT WITH CHECK (("auth"."uid"() = ( SELECT "deliveries"."driver_id"
   FROM "public"."deliveries"
  WHERE ("deliveries"."id" = "route_points"."delivery_id"))));



CREATE POLICY "Drivers can update deliveries" ON "public"."deliveries" FOR UPDATE USING (("auth"."uid"() = "driver_id"));



CREATE POLICY "Drivers see own earnings" ON "public"."earnings" FOR SELECT USING (("auth"."uid"() = "driver_id"));



CREATE POLICY "Drivers see pending and own deliveries" ON "public"."deliveries" FOR SELECT USING ((("status" = 'pending'::"text") OR ("auth"."uid"() = "driver_id")));



CREATE POLICY "Partners can manage own menu items" ON "public"."menu_items" USING (("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"())))) WITH CHECK (("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"()))));



CREATE POLICY "Partners can update own business" ON "public"."partners" FOR UPDATE USING (("profile_id" = "auth"."uid"())) WITH CHECK (("profile_id" = "auth"."uid"()));



CREATE POLICY "Partners can view own business" ON "public"."partners" FOR SELECT USING (("profile_id" = "auth"."uid"()));



CREATE POLICY "Users can update own profile" ON "public"."profiles" FOR UPDATE USING (("auth"."uid"() = "id"));



CREATE POLICY "Users can view own profile" ON "public"."profiles" FOR SELECT USING (("auth"."uid"() = "id"));



CREATE POLICY "authenticated users can read deliveries" ON "public"."deliveries" FOR SELECT TO "authenticated" USING (true);



CREATE POLICY "customers can insert deliveries" ON "public"."deliveries" FOR INSERT TO "authenticated" WITH CHECK (("auth"."uid"() = "customer_id"));



ALTER TABLE "public"."deliveries" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "deliveries_insert_own_as_customer" ON "public"."deliveries" FOR INSERT WITH CHECK ((("customer_id" = "auth"."uid"()) AND ("status" = 'pending'::"text") AND ("driver_id" IS NULL)));



CREATE POLICY "deliveries_select_participant_or_pending_driver_or_admin" ON "public"."deliveries" FOR SELECT USING ((("customer_id" = "auth"."uid"()) OR ("driver_id" = "auth"."uid"()) OR "public"."is_admin"() OR (("status" = 'pending'::"text") AND "public"."current_role_is"('driver'::"text")) OR ("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"())))));



CREATE POLICY "deliveries_update_participant_or_admin" ON "public"."deliveries" FOR UPDATE USING (("public"."is_admin"() OR ("driver_id" = "auth"."uid"()) OR ("customer_id" = "auth"."uid"()) OR (("status" = 'pending'::"text") AND "public"."current_role_is"('driver'::"text")))) WITH CHECK (("public"."is_admin"() OR ("driver_id" = "auth"."uid"()) OR (("customer_id" = "auth"."uid"()) AND ("status" = ANY (ARRAY['pending'::"text", 'cancelled'::"text"])))));



CREATE POLICY "drivers can update deliveries" ON "public"."deliveries" FOR UPDATE TO "authenticated" USING ((("status" = 'pending'::"text") OR ("driver_id" = "auth"."uid"())));



ALTER TABLE "public"."earnings" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "earnings_select_own_or_admin" ON "public"."earnings" FOR SELECT USING ((("driver_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."menu_items" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "menu_items_insert_own_partner_or_admin" ON "public"."menu_items" FOR INSERT WITH CHECK (("public"."is_admin"() OR ("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"())))));



CREATE POLICY "menu_items_select_active_or_own_or_admin" ON "public"."menu_items" FOR SELECT USING ((("active" = true) OR "public"."is_admin"() OR ("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"())))));



CREATE POLICY "menu_items_update_own_partner_or_admin" ON "public"."menu_items" FOR UPDATE USING (("public"."is_admin"() OR ("partner_id" IN ( SELECT "partners"."id"
   FROM "public"."partners"
  WHERE ("partners"."profile_id" = "auth"."uid"())))));



ALTER TABLE "public"."partner_applications" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partner_applications_insert_public" ON "public"."partner_applications" FOR INSERT WITH CHECK (("status" = 'pending'::"text"));



CREATE POLICY "partner_applications_select_admin_only" ON "public"."partner_applications" FOR SELECT USING ("public"."is_admin"());



CREATE POLICY "partner_applications_update_admin_only" ON "public"."partner_applications" FOR UPDATE USING ("public"."is_admin"());



ALTER TABLE "public"."partners" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "partners_insert_admin_only" ON "public"."partners" FOR INSERT WITH CHECK ("public"."is_admin"());



CREATE POLICY "partners_select_approved_or_own_or_admin" ON "public"."partners" FOR SELECT USING ((("approved" = true) OR ("profile_id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "partners_update_own_or_admin" ON "public"."partners" FOR UPDATE USING ((("profile_id" = "auth"."uid"()) OR "public"."is_admin"())) WITH CHECK ((("profile_id" = "auth"."uid"()) OR "public"."is_admin"()));



ALTER TABLE "public"."profiles" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "profiles_select_own_or_admin" ON "public"."profiles" FOR SELECT USING ((("id" = "auth"."uid"()) OR "public"."is_admin"()));



CREATE POLICY "profiles_update_own_limited" ON "public"."profiles" FOR UPDATE USING ((("id" = "auth"."uid"()) OR "public"."is_admin"())) WITH CHECK (("public"."is_admin"() OR (("id" = "auth"."uid"()) AND ("is_admin" = false))));



ALTER TABLE "public"."route_points" ENABLE ROW LEVEL SECURITY;


CREATE POLICY "route_points_insert_assigned_driver" ON "public"."route_points" FOR INSERT WITH CHECK ((EXISTS ( SELECT 1
   FROM "public"."deliveries" "d"
  WHERE (("d"."id" = "route_points"."delivery_id") AND ("d"."driver_id" = "auth"."uid"())))));



CREATE POLICY "route_points_select_participant_or_admin" ON "public"."route_points" FOR SELECT USING (("public"."is_admin"() OR (EXISTS ( SELECT 1
   FROM "public"."deliveries" "d"
  WHERE (("d"."id" = "route_points"."delivery_id") AND (("d"."customer_id" = "auth"."uid"()) OR ("d"."driver_id" = "auth"."uid"())))))));





ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";






ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."deliveries";



GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";






















































































































































GRANT ALL ON FUNCTION "public"."current_role_is"("target_role" "text") TO "anon";
GRANT ALL ON FUNCTION "public"."current_role_is"("target_role" "text") TO "authenticated";
GRANT ALL ON FUNCTION "public"."current_role_is"("target_role" "text") TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_delivery_pricing"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_delivery_pricing"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_delivery_pricing"() TO "service_role";



GRANT ALL ON FUNCTION "public"."enforce_partner_admin_fields"() TO "anon";
GRANT ALL ON FUNCTION "public"."enforce_partner_admin_fields"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."enforce_partner_admin_fields"() TO "service_role";



GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user"() TO "service_role";



GRANT ALL ON FUNCTION "public"."is_admin"() TO "anon";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."is_admin"() TO "service_role";



GRANT ALL ON FUNCTION "public"."zone_pricing"("miles" double precision) TO "anon";
GRANT ALL ON FUNCTION "public"."zone_pricing"("miles" double precision) TO "authenticated";
GRANT ALL ON FUNCTION "public"."zone_pricing"("miles" double precision) TO "service_role";


















GRANT ALL ON TABLE "public"."deliveries" TO "anon";
GRANT ALL ON TABLE "public"."deliveries" TO "authenticated";
GRANT ALL ON TABLE "public"."deliveries" TO "service_role";



GRANT ALL ON TABLE "public"."earnings" TO "anon";
GRANT ALL ON TABLE "public"."earnings" TO "authenticated";
GRANT ALL ON TABLE "public"."earnings" TO "service_role";



GRANT ALL ON TABLE "public"."menu_items" TO "anon";
GRANT ALL ON TABLE "public"."menu_items" TO "authenticated";
GRANT ALL ON TABLE "public"."menu_items" TO "service_role";



GRANT ALL ON TABLE "public"."partner_applications" TO "anon";
GRANT ALL ON TABLE "public"."partner_applications" TO "authenticated";
GRANT ALL ON TABLE "public"."partner_applications" TO "service_role";



GRANT ALL ON TABLE "public"."partners" TO "anon";
GRANT ALL ON TABLE "public"."partners" TO "authenticated";
GRANT ALL ON TABLE "public"."partners" TO "service_role";



GRANT ALL ON TABLE "public"."profiles" TO "anon";
GRANT ALL ON TABLE "public"."profiles" TO "authenticated";
GRANT ALL ON TABLE "public"."profiles" TO "service_role";



GRANT ALL ON TABLE "public"."route_points" TO "anon";
GRANT ALL ON TABLE "public"."route_points" TO "authenticated";
GRANT ALL ON TABLE "public"."route_points" TO "service_role";









ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS TO "service_role";






ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES TO "service_role";































drop extension if exists "pg_net";

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();



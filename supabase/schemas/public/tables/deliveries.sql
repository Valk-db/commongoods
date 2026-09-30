CREATE TABLE "public"."deliveries" (
  "id"                           uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "customer_id"                  uuid,
  "driver_id"                    uuid,
  "partner_id"                   uuid,
  "status"                       text                     DEFAULT 'pending'::text,
  "category"                     text                     NOT NULL,
  "pickup_address"               text                     NOT NULL,
  "pickup_lat"                   double precision         NOT NULL,
  "pickup_lng"                   double precision         NOT NULL,
  "dropoff_address"              text                     NOT NULL,
  "dropoff_lat"                  double precision         NOT NULL,
  "dropoff_lng"                  double precision         NOT NULL,
  "distance_miles"               double precision,
  "zone_assigned"                integer,
  "fee_charged"                  numeric(10,2),
  "driver_payout"                numeric(10,2),
  "platform_cut"                 numeric(10,2),
  "estimated_duration_minutes"   integer,
  "actual_duration_minutes"      integer,
  "route_polyline"               text,
  "requested_at"                 timestamp with time zone DEFAULT now(),
  "claimed_at"                   timestamp with time zone,
  "picked_up_at"                 timestamp with time zone,
  "delivered_at"                 timestamp with time zone,
  "notes"                        text,
  "ready_for_pickup_at"          timestamp with time zone,
  "transport_type"               text,
  "base_fee_applied"             numeric(10,2),
  "per_mile_rate_applied"        numeric(10,2),
  "surge_multiplier_applied"     numeric(3,2)             DEFAULT 1.00,
  "tip_amount"                   numeric(10,2)            DEFAULT 0.00,
  "driver_arrived_at_pickup_at"  timestamp with time zone,
  "driver_arrived_at_dropoff_at" timestamp with time zone,
  "cancelled_by"                 text,
  "cancellation_reason_code"     text,
  "dynamic_boost_incentive"      numeric(10,2)            DEFAULT 0.00,
  CONSTRAINT "deliveries_cancelled_by_check" CHECK ((cancelled_by = ANY (ARRAY['customer'::text, 'driver'::text, 'partner'::text, 'system'::text]))),
  CONSTRAINT "deliveries_pkey" PRIMARY KEY (id),
  CONSTRAINT "deliveries_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'claimed'::text, 'in_progress'::text, 'completed'::text, 'cancelled'::text]))),
  CONSTRAINT "deliveries_transport_type_check" CHECK ((transport_type = ANY (ARRAY['car'::text, 'bicycle'::text, 'scooter'::text, 'foot'::text]))),
  CONSTRAINT "deliveries_zone_assigned_check" CHECK ((zone_assigned = ANY (ARRAY[1, 2, 3]))),
  CONSTRAINT "deliveries_partner_id_fkey" FOREIGN KEY (partner_id) REFERENCES public.partners(id),
  CONSTRAINT "deliveries_customer_id_fkey" FOREIGN KEY (customer_id) REFERENCES public.profiles(id),
  CONSTRAINT "deliveries_driver_id_fkey" FOREIGN KEY (driver_id) REFERENCES public.profiles(id)
);

ALTER TABLE "public"."deliveries"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_deliveries_customer_id ON public.deliveries USING btree (customer_id);

CREATE INDEX idx_deliveries_driver_id ON public.deliveries USING btree (driver_id);

CREATE INDEX idx_deliveries_partner_id ON public.deliveries USING btree (partner_id);

CREATE TRIGGER trg_enforce_delivery_pricing
  BEFORE INSERT OR UPDATE ON public.deliveries
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_delivery_pricing();

CREATE POLICY "deliveries_insert_own_as_customer" ON "public"."deliveries"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (((customer_id = ( SELECT auth.uid() AS uid)) AND (status = 'pending'::text) AND (driver_id IS NULL)));

CREATE POLICY "deliveries_select_participant_or_pending_driver_or_admin" ON "public"."deliveries"
  FOR SELECT
  TO PUBLIC
  USING
    (((customer_id = ( SELECT auth.uid() AS uid)) OR (driver_id = ( SELECT auth.uid() AS uid)) OR private.is_admin() OR ((status = 'pending'::text) AND
    private.current_role_is('driver'::text)) OR (partner_id IN ( SELECT partners.id
   FROM public.partners
  WHERE (partners.profile_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "deliveries_update_participant_or_admin" ON "public"."deliveries"
  FOR UPDATE
  TO PUBLIC
  USING
    ((private.is_admin() OR (driver_id = ( SELECT auth.uid() AS uid)) OR (customer_id = ( SELECT auth.uid() AS uid)) OR ((status = 'pending'::text) AND
    private.current_role_is('driver'::text))))
  WITH
    CHECK
    ((private.is_admin() OR (driver_id = ( SELECT auth.uid() AS uid)) OR ((customer_id = ( SELECT auth.uid() AS uid)) AND (status = ANY (ARRAY['pending'::text,
    'cancelled'::text])))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."deliveries" TO "postgres", "service_role";

COMMENT ON COLUMN "public"."deliveries"."distance_miles" IS 'Driving distance in miles from the Mapbox Directions API, calculated at request time.';

REVOKE ALL ON TABLE "public"."deliveries" FROM "authenticated";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."deliveries" TO "authenticated";

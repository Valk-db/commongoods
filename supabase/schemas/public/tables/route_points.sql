CREATE TABLE "public"."route_points" (
  "id"           uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_id"  uuid,
  "lat"          double precision         NOT NULL,
  "lng"          double precision         NOT NULL,
  "driver_speed" double precision,
  "recorded_at"  timestamp with time zone DEFAULT now(),
  CONSTRAINT "route_points_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "route_points_pkey" PRIMARY KEY (id)
);

ALTER TABLE "public"."route_points"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_route_points_delivery_id ON public.route_points USING btree (delivery_id);

CREATE POLICY "route_points_insert_assigned_driver" ON "public"."route_points"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = route_points.delivery_id) AND (d.driver_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "route_points_select_participant_or_admin" ON "public"."route_points"
  FOR SELECT
  TO PUBLIC
  USING ((private.is_admin() OR (EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = route_points.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid))))))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."route_points" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."route_points" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."route_points" TO "authenticated";

CREATE TABLE "public"."performance_metrics" (
  "delivery_id"                     uuid    NOT NULL,
  "estimated_prep_minutes"          integer,
  "actual_prep_minutes"             integer,
  "prep_delay_minutes"              integer,
  "estimated_transit_minutes"       integer,
  "actual_transit_minutes"          integer,
  "transit_delay_minutes"           integer,
  "driver_wait_at_merchant_minutes" integer,
  "had_interaction_issues"          boolean DEFAULT false,
  CONSTRAINT "performance_metrics_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "performance_metrics_pkey" PRIMARY KEY (delivery_id)
);

ALTER TABLE "public"."performance_metrics"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_performance_metrics_delivery_id ON public.performance_metrics USING btree (delivery_id);

CREATE POLICY "performance_metrics_select_admin_or_driver" ON "public"."performance_metrics"
  FOR SELECT
  TO PUBLIC
  USING ((private.is_admin() OR (EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = performance_metrics.delivery_id) AND (d.driver_id = ( SELECT auth.uid() AS uid)))))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."performance_metrics" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."performance_metrics" FROM "authenticated";

GRANT SELECT ON TABLE "public"."performance_metrics" TO "authenticated";

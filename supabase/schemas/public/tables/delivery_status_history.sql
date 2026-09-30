CREATE TABLE "public"."delivery_status_history" (
  "id"          uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_id" uuid,
  "status"      text                     NOT NULL,
  "changed_at"  timestamp with time zone DEFAULT now(),
  "actor_id"    uuid,
  "lat"         double precision,
  "lng"         double precision,
  CONSTRAINT "delivery_status_history_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "delivery_status_history_pkey" PRIMARY KEY (id),
  CONSTRAINT "delivery_status_history_actor_id_fkey" FOREIGN KEY (actor_id) REFERENCES public.profiles(id) ON DELETE SET NULL
);

ALTER TABLE "public"."delivery_status_history"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_delivery_status_history_actor_id ON public.delivery_status_history USING btree (actor_id);

CREATE INDEX idx_delivery_status_history_delivery_id ON public.delivery_status_history USING btree (delivery_id);

CREATE POLICY "delivery_status_history_select_participant_or_admin" ON "public"."delivery_status_history"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = delivery_status_history.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)) OR private.is_admin())))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."delivery_status_history" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."delivery_status_history" FROM "authenticated";

GRANT SELECT ON TABLE "public"."delivery_status_history" TO "authenticated";

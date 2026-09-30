CREATE TABLE "public"."earnings" (
  "id"           uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "driver_id"    uuid,
  "delivery_id"  uuid,
  "amount"       numeric(10,2)            NOT NULL,
  "platform_cut" numeric(10,2)            NOT NULL,
  "paid_out"     boolean                  DEFAULT false,
  "created_at"   timestamp with time zone DEFAULT now(),
  CONSTRAINT "earnings_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id),
  CONSTRAINT "earnings_pkey" PRIMARY KEY (id),
  CONSTRAINT "earnings_driver_id_fkey" FOREIGN KEY (driver_id) REFERENCES public.profiles(id)
);

ALTER TABLE "public"."earnings"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_earnings_delivery_id ON public.earnings USING btree (delivery_id);

CREATE INDEX idx_earnings_driver_id ON public.earnings USING btree (driver_id);

CREATE POLICY "earnings_select_own_or_admin" ON "public"."earnings"
  FOR SELECT
  TO PUBLIC
  USING (((driver_id = ( SELECT auth.uid() AS uid)) OR private.is_admin()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."earnings" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."earnings" FROM "authenticated";

GRANT SELECT ON TABLE "public"."earnings" TO "authenticated";

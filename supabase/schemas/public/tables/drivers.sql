CREATE TABLE "public"."drivers" (
  "id"           uuid                     NOT NULL,
  "is_online"    boolean                  NOT NULL DEFAULT false,
  "vehicle_type" text,
  "approved"     boolean                  DEFAULT false,
  "updated_at"   timestamp with time zone DEFAULT now(),
  CONSTRAINT "drivers_pkey" PRIMARY KEY (id),
  CONSTRAINT "drivers_id_fkey" FOREIGN KEY (id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."drivers"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_drivers_id ON public.drivers USING btree (id);

CREATE TRIGGER trg_enforce_driver_admin_fields
  BEFORE UPDATE ON public.drivers
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_driver_admin_fields();

CREATE POLICY "drivers_all_own" ON "public"."drivers"
  FOR ALL
  TO PUBLIC
  USING ((( SELECT auth.uid() AS uid) = id))
  WITH CHECK ((( SELECT auth.uid() AS uid) = id));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."drivers" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."drivers" FROM "authenticated";

GRANT SELECT, UPDATE ON TABLE "public"."drivers" TO "authenticated";

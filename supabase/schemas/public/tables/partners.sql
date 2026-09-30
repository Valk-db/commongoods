CREATE TABLE "public"."partners" (
  "id"                        uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "profile_id"                uuid,
  "business_name"             text                     NOT NULL,
  "address"                   text                     NOT NULL,
  "lat"                       double precision,
  "lng"                       double precision,
  "pickup_notes"              text,
  "pos_system"                text,
  "approved"                  boolean                  DEFAULT false,
  "created_at"                timestamp with time zone DEFAULT now(),
  "founding_merchant"         boolean                  DEFAULT false,
  "onboarding_fee_paid"       boolean                  DEFAULT false,
  "joined_during_pilot"       boolean                  DEFAULT false,
  "merchant_priority_score"   numeric(3,2)             DEFAULT 5.00,
  "average_prep_time_minutes" numeric(5,2)             DEFAULT 15.00,
  CONSTRAINT "partners_pkey" PRIMARY KEY (id),
  CONSTRAINT "partners_profile_id_fkey" FOREIGN KEY (profile_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."partners"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_partners_profile_id ON public.partners USING btree (profile_id);

CREATE TRIGGER trg_enforce_partner_admin_fields
  BEFORE UPDATE ON public.partners
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_partner_admin_fields();

CREATE POLICY "partners_insert_admin_only" ON "public"."partners"
  FOR INSERT
  TO PUBLIC
  WITH CHECK (private.is_admin());

CREATE POLICY "partners_select_approved_or_own_or_admin" ON "public"."partners"
  FOR SELECT
  TO PUBLIC
  USING (((approved = true) OR (profile_id = ( SELECT auth.uid() AS uid)) OR private.is_admin()));

CREATE POLICY "partners_update_own_or_admin" ON "public"."partners"
  FOR UPDATE
  TO PUBLIC
  USING (((profile_id = ( SELECT auth.uid() AS uid)) OR private.is_admin()))
  WITH CHECK (((profile_id = ( SELECT auth.uid() AS uid)) OR private.is_admin()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partners" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."partners" FROM "anon";

GRANT SELECT ON TABLE "public"."partners" TO "anon";

REVOKE ALL ON TABLE "public"."partners" FROM "authenticated";

GRANT SELECT, UPDATE ON TABLE "public"."partners" TO "authenticated";

CREATE TABLE "public"."partner_applications" (
  "id"            uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "business_name" text                     NOT NULL,
  "contact_name"  text                     NOT NULL,
  "contact_email" text                     NOT NULL,
  "contact_phone" text                     NOT NULL,
  "address"       text                     NOT NULL,
  "pos_system"    text,
  "notes"         text,
  "status"        text                     DEFAULT 'pending'::text,
  "submitted_at"  timestamp with time zone DEFAULT now(),
  CONSTRAINT "partner_applications_pkey" PRIMARY KEY (id),
  CONSTRAINT "partner_applications_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'approved'::text, 'rejected'::text])))
);

ALTER TABLE "public"."partner_applications"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_partner_applications_id ON public.partner_applications USING btree (id);

CREATE TRIGGER trg_enforce_partner_application_admin_fields
  BEFORE UPDATE ON public.partner_applications
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_partner_application_admin_fields();

CREATE POLICY "partner_applications_insert_public" ON "public"."partner_applications"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((status = 'pending'::text));

CREATE POLICY "partner_applications_select_admin_only" ON "public"."partner_applications"
  FOR SELECT
  TO PUBLIC
  USING (private.is_admin());

CREATE POLICY "partner_applications_update_admin_only" ON "public"."partner_applications"
  FOR UPDATE
  TO PUBLIC
  USING (private.is_admin());

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."partner_applications" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."partner_applications" FROM "anon";

GRANT INSERT ON TABLE "public"."partner_applications" TO "anon";

REVOKE ALL ON TABLE "public"."partner_applications" FROM "authenticated";

GRANT INSERT ON TABLE "public"."partner_applications" TO "authenticated";

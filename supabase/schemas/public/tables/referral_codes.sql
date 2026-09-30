CREATE TABLE "public"."referral_codes" (
  "id"         uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "code"       text                     NOT NULL,
  "role"       text                     NOT NULL,
  "label"      text,
  "used_by"    uuid,
  "used_at"    timestamp with time zone,
  "expires_at" timestamp with time zone,
  "is_active"  boolean                  DEFAULT true,
  "created_at" timestamp with time zone DEFAULT now(),
  CONSTRAINT "referral_codes_code_key" UNIQUE (code),
  CONSTRAINT "referral_codes_pkey" PRIMARY KEY (id),
  CONSTRAINT "referral_codes_role_check" CHECK ((role = ANY (ARRAY['driver'::text, 'partner'::text]))),
  CONSTRAINT "referral_codes_used_by_fkey" FOREIGN KEY (used_by) REFERENCES public.profiles(id)
);

ALTER TABLE "public"."referral_codes"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_referral_codes_used_by ON public.referral_codes USING btree (used_by);

CREATE TRIGGER trg_enforce_referral_code_admin_fields
  BEFORE UPDATE ON public.referral_codes
  FOR EACH ROW
  EXECUTE FUNCTION private.enforce_referral_code_admin_fields();

CREATE POLICY "referral_codes_admin_all" ON "public"."referral_codes"
  FOR ALL
  TO PUBLIC
  USING (private.is_admin())
  WITH CHECK (private.is_admin());

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."referral_codes" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."referral_codes" FROM "authenticated";

GRANT SELECT ON TABLE "public"."referral_codes" TO "authenticated";

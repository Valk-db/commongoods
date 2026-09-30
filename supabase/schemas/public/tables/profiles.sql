CREATE TABLE "public"."profiles" (
  "id"                   uuid                     NOT NULL,
  "role"                 text                     NOT NULL,
  "full_name"            text,
  "phone"                text,
  "created_at"           timestamp with time zone DEFAULT now(),
  "is_admin"             boolean                  NOT NULL DEFAULT false,
  "priority_score"       numeric(3,2)             DEFAULT 5.00,
  "lifetime_deliveries"  integer                  DEFAULT 0,
  "cancellation_rate"    numeric(5,2)             DEFAULT 0.00,
  "historical_tip_ratio" numeric(5,2)             DEFAULT 0.00,
  CONSTRAINT "profiles_id_fkey" FOREIGN KEY (id) REFERENCES auth.users(id) ON DELETE CASCADE,
  CONSTRAINT "profiles_pkey" PRIMARY KEY (id),
  CONSTRAINT "profiles_role_check" CHECK ((role = ANY (ARRAY['customer'::text, 'driver'::text, 'partner'::text])))
);

ALTER TABLE "public"."profiles"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_profiles_id ON public.profiles USING btree (id);

CREATE TRIGGER trg_enforce_profile_admin_fields
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_profile_admin_fields();

CREATE POLICY "profiles_select_own_or_admin" ON "public"."profiles"
  FOR SELECT
  TO PUBLIC
  USING (((id = ( SELECT auth.uid() AS uid)) OR private.is_admin()));

CREATE POLICY "profiles_update_own_limited" ON "public"."profiles"
  FOR UPDATE
  TO PUBLIC
  USING (((id = ( SELECT auth.uid() AS uid)) OR private.is_admin()))
  WITH CHECK ((private.is_admin() OR ((id = ( SELECT auth.uid() AS uid)) AND (is_admin = false))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."profiles" TO "postgres", "service_role";

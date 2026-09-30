CREATE TABLE "public"."menu_items" (
  "id"          uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "partner_id"  uuid,
  "name"        text                     NOT NULL,
  "description" text,
  "price"       numeric(10,2)            NOT NULL,
  "category"    text,
  "photo_url"   text,
  "active"      boolean                  DEFAULT true,
  "created_at"  timestamp with time zone DEFAULT now(),
  CONSTRAINT "menu_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "menu_items_partner_id_fkey" FOREIGN KEY (partner_id) REFERENCES public.partners(id) ON DELETE CASCADE
);

ALTER TABLE "public"."menu_items"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_menu_items_partner_id ON public.menu_items USING btree (partner_id);

CREATE POLICY "menu_items_insert_own_partner_or_admin" ON "public"."menu_items"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((private.is_admin() OR (partner_id IN ( SELECT partners.id
   FROM public.partners
  WHERE (partners.profile_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "menu_items_select_active_or_own_or_admin" ON "public"."menu_items"
  FOR SELECT
  TO PUBLIC
  USING (((active = true) OR private.is_admin() OR (partner_id IN ( SELECT partners.id
   FROM public.partners
  WHERE (partners.profile_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "menu_items_update_own_partner_or_admin" ON "public"."menu_items"
  FOR UPDATE
  TO PUBLIC
  USING ((private.is_admin() OR (partner_id IN ( SELECT partners.id
   FROM public.partners
  WHERE (partners.profile_id = ( SELECT auth.uid() AS uid))))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."menu_items" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."menu_items" FROM "anon";

GRANT SELECT ON TABLE "public"."menu_items" TO "anon";

REVOKE ALL ON TABLE "public"."menu_items" FROM "authenticated";

GRANT INSERT, SELECT, UPDATE ON TABLE "public"."menu_items" TO "authenticated";

CREATE TABLE "public"."menu_item_options" (
  "id"             uuid          NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "menu_item_id"   uuid,
  "name"           text          NOT NULL,
  "price_modifier" numeric(10,2) DEFAULT 0.00,
  "is_available"   boolean       DEFAULT true,
  CONSTRAINT "menu_item_options_pkey" PRIMARY KEY (id),
  CONSTRAINT "menu_item_options_menu_item_id_fkey" FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id) ON DELETE CASCADE
);

ALTER TABLE "public"."menu_item_options"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_menu_item_options_menu_item_id ON public.menu_item_options USING btree (menu_item_id);

CREATE POLICY "menu_item_options_all_own_partner" ON "public"."menu_item_options"
  FOR ALL
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM (public.menu_items mi
     JOIN public.partners p ON ((p.id = mi.partner_id)))
  WHERE ((mi.id = menu_item_options.menu_item_id) AND (p.profile_id = ( SELECT auth.uid() AS uid))))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM (public.menu_items mi
     JOIN public.partners p ON ((p.id = mi.partner_id)))
  WHERE ((mi.id = menu_item_options.menu_item_id) AND (p.profile_id = ( SELECT auth.uid() AS uid))))));

CREATE POLICY "menu_item_options_select" ON "public"."menu_item_options"
  FOR SELECT
  TO PUBLIC
  USING (true);

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."menu_item_options" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."menu_item_options" FROM "anon";

GRANT SELECT ON TABLE "public"."menu_item_options" TO "anon";

REVOKE ALL ON TABLE "public"."menu_item_options" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."menu_item_options" TO "authenticated";

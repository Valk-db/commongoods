CREATE TABLE "public"."delivery_item_options" (
  "id"                  uuid          NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_item_id"    uuid,
  "menu_item_option_id" uuid,
  "price_at_purchase"   numeric(10,2) NOT NULL,
  CONSTRAINT "delivery_item_options_pkey" PRIMARY KEY (id),
  CONSTRAINT "delivery_item_options_delivery_item_id_fkey" FOREIGN KEY (delivery_item_id) REFERENCES public.delivery_items(id) ON DELETE CASCADE,
  CONSTRAINT "delivery_item_options_menu_item_option_id_fkey" FOREIGN KEY (menu_item_option_id) REFERENCES public.menu_item_options(id) ON DELETE SET NULL
);

ALTER TABLE "public"."delivery_item_options"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_delivery_item_options_delivery_item_id ON public.delivery_item_options USING btree (delivery_item_id);

CREATE INDEX idx_delivery_item_options_menu_item_option_id ON public.delivery_item_options USING btree (menu_item_option_id);

CREATE POLICY "delivery_item_options_select_participant_or_admin" ON "public"."delivery_item_options"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM (public.delivery_items di
     JOIN public.deliveries d ON ((d.id = di.delivery_id)))
  WHERE
    ((di.id = delivery_item_options.delivery_item_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)) OR (d.partner_id IN ( SELECT
    partners.id
           FROM public.partners
          WHERE (partners.profile_id = ( SELECT auth.uid() AS uid)))) OR private.is_admin())))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."delivery_item_options" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."delivery_item_options" FROM "authenticated";

GRANT SELECT ON TABLE "public"."delivery_item_options" TO "authenticated";

CREATE TABLE "public"."delivery_items" (
  "id"                uuid          NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_id"       uuid,
  "menu_item_id"      uuid,
  "quantity"          integer       NOT NULL DEFAULT 1,
  "price_at_purchase" numeric(10,2) NOT NULL,
  CONSTRAINT "delivery_items_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "delivery_items_pkey" PRIMARY KEY (id),
  CONSTRAINT "delivery_items_quantity_check" CHECK ((quantity > 0)),
  CONSTRAINT "delivery_items_menu_item_id_fkey" FOREIGN KEY (menu_item_id) REFERENCES public.menu_items(id) ON DELETE SET NULL
);

ALTER TABLE "public"."delivery_items"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_delivery_items_delivery_id ON public.delivery_items USING btree (delivery_id);

CREATE INDEX idx_delivery_items_menu_item_id ON public.delivery_items USING btree (menu_item_id);

CREATE POLICY "delivery_items_select_participant_or_admin" ON "public"."delivery_items"
  FOR SELECT
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE
    ((d.id = delivery_items.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)) OR (d.partner_id IN ( SELECT partners.id
           FROM public.partners
          WHERE (partners.profile_id = ( SELECT auth.uid() AS uid)))) OR private.is_admin())))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."delivery_items" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."delivery_items" FROM "authenticated";

GRANT SELECT ON TABLE "public"."delivery_items" TO "authenticated";

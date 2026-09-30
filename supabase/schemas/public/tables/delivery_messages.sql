CREATE TABLE "public"."delivery_messages" (
  "id"           uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_id"  uuid,
  "sender_id"    uuid,
  "message_text" text                     NOT NULL,
  "created_at"   timestamp with time zone DEFAULT now(),
  CONSTRAINT "delivery_messages_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "delivery_messages_pkey" PRIMARY KEY (id),
  CONSTRAINT "delivery_messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES public.profiles(id)
);

ALTER TABLE "public"."delivery_messages"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_delivery_messages_delivery_id ON public.delivery_messages USING btree (delivery_id);

CREATE INDEX idx_delivery_messages_sender_id ON public.delivery_messages USING btree (sender_id);

CREATE POLICY "delivery_messages_all_participant" ON "public"."delivery_messages"
  FOR ALL
  TO PUBLIC
  USING ((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = delivery_messages.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)))))))
  WITH CHECK ((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = delivery_messages.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)))))));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."delivery_messages" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."delivery_messages" FROM "authenticated";

GRANT DELETE, INSERT, SELECT, UPDATE ON TABLE "public"."delivery_messages" TO "authenticated";

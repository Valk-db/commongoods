CREATE TABLE "public"."ratings_and_reviews" (
  "id"             uuid                     NOT NULL DEFAULT extensions.uuid_generate_v4(),
  "delivery_id"    uuid,
  "reviewer_id"    uuid,
  "reviewee_id"    uuid,
  "reviewee_type"  text                     NOT NULL,
  "rating_stars"   integer                  NOT NULL,
  "tags"           text[],
  "written_review" text,
  "created_at"     timestamp with time zone DEFAULT now(),
  CONSTRAINT "ratings_and_reviews_delivery_id_fkey" FOREIGN KEY (delivery_id) REFERENCES public.deliveries(id) ON DELETE CASCADE,
  CONSTRAINT "ratings_and_reviews_pkey" PRIMARY KEY (id),
  CONSTRAINT "ratings_and_reviews_rating_stars_check" CHECK (((rating_stars >= 1) AND (rating_stars <= 5))),
  CONSTRAINT "ratings_and_reviews_reviewee_id_fkey" FOREIGN KEY (reviewee_id) REFERENCES public.profiles(id) ON DELETE CASCADE,
  CONSTRAINT "ratings_and_reviews_reviewee_type_check" CHECK ((reviewee_type = ANY (ARRAY['customer'::text, 'driver'::text, 'partner'::text]))),
  CONSTRAINT "ratings_and_reviews_reviewer_id_fkey" FOREIGN KEY (reviewer_id) REFERENCES public.profiles(id) ON DELETE CASCADE
);

ALTER TABLE "public"."ratings_and_reviews"
  ENABLE ROW LEVEL SECURITY;

CREATE INDEX idx_ratings_and_reviews_delivery_id ON public.ratings_and_reviews USING btree (delivery_id);

CREATE INDEX idx_ratings_and_reviews_reviewee_id ON public.ratings_and_reviews USING btree (reviewee_id);

CREATE INDEX idx_ratings_and_reviews_reviewer_id ON public.ratings_and_reviews USING btree (reviewer_id);

CREATE POLICY "ratings_and_reviews_insert_reviewer" ON "public"."ratings_and_reviews"
  FOR INSERT
  TO PUBLIC
  WITH CHECK ((( SELECT auth.uid() AS uid) = reviewer_id));

CREATE POLICY "ratings_and_reviews_select_participant_or_admin" ON "public"."ratings_and_reviews"
  FOR SELECT
  TO PUBLIC
  USING (((EXISTS ( SELECT 1
   FROM public.deliveries d
  WHERE ((d.id = ratings_and_reviews.delivery_id) AND ((d.customer_id = ( SELECT auth.uid() AS uid)) OR (d.driver_id = ( SELECT auth.uid() AS uid)))))) OR private.is_admin()));

GRANT DELETE, INSERT, MAINTAIN, REFERENCES, SELECT, TRIGGER, TRUNCATE, UPDATE ON TABLE "public"."ratings_and_reviews" TO "postgres", "service_role";

REVOKE ALL ON TABLE "public"."ratings_and_reviews" FROM "authenticated";

GRANT INSERT, SELECT ON TABLE "public"."ratings_and_reviews" TO "authenticated";

CREATE OR REPLACE FUNCTION public.enforce_delivery_pricing()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
declare
  pricing record;
begin
  -- Lock down everything that defines *what* the delivery is once it
  -- exists, unless an admin is making the change. Status, driver_id,
  -- timestamps, and notes remain freely updatable for the normal
  -- claim -> pickup -> deliver flow.
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.customer_id      := old.customer_id;
    new.partner_id        := old.partner_id;
    new.category          := old.category;
    new.pickup_address     := old.pickup_address;
    new.pickup_lat        := old.pickup_lat;
    new.pickup_lng        := old.pickup_lng;
    new.dropoff_address    := old.dropoff_address;
    new.dropoff_lat       := old.dropoff_lat;
    new.dropoff_lng       := old.dropoff_lng;
    new.distance_miles     := old.distance_miles;
    new.requested_at      := old.requested_at;
  end if;

  -- Admins can hand-edit zone/fee/payout/cut directly (e.g. comping a
  -- delivery); everyone else gets it recomputed from distance_miles,
  -- full stop.
  if not public.is_admin() then
    select * into pricing from public.zone_pricing(new.distance_miles);
    if pricing.zone is null then
      raise exception 'OUTSIDE_SERVICE_AREA';
    end if;
    new.zone_assigned := pricing.zone;
    new.fee_charged   := pricing.fee;
    new.driver_payout := pricing.driver_payout;
    new.platform_cut  := pricing.platform_cut;
  end if;

  return new;
end;
$function$;

GRANT EXECUTE ON FUNCTION "public"."enforce_delivery_pricing"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

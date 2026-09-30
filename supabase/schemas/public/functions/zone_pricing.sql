CREATE OR REPLACE FUNCTION public.zone_pricing (
  miles double precision
)
  RETURNS TABLE (
    zone          integer,
    fee           numeric,
    driver_payout numeric,
    platform_cut  numeric
  )
  LANGUAGE sql
  IMMUTABLE
  SET search_path TO 'public'
  AS $function$
  select
    case
      when miles <= 5  then 1
      when miles <= 10 then 2
      when miles <= 20 then 3
      else null
    end as zone,
    case
      when miles <= 5  then 8::numeric
      when miles <= 10 then 11::numeric
      when miles <= 20 then 15::numeric
      else null
    end as fee,
    case
      when miles <= 5  then 6.00::numeric
      when miles <= 10 then 8.25::numeric
      when miles <= 20 then 11.25::numeric
      else null
    end as driver_payout,
    case
      when miles <= 5  then 2.00::numeric
      when miles <= 10 then 2.75::numeric
      when miles <= 20 then 3.75::numeric
      else null
    end as platform_cut;
$function$;

GRANT EXECUTE ON FUNCTION "public"."zone_pricing"(double precision) TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

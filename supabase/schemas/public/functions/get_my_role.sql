CREATE OR REPLACE FUNCTION public.get_my_role()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
BEGIN
  RETURN COALESCE(nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'role', ''), 'customer');
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."get_my_role"() TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."get_my_role"() FROM PUBLIC;

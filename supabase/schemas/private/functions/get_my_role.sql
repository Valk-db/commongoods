CREATE OR REPLACE FUNCTION private.get_my_role()
  RETURNS text
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  RETURN COALESCE(nullif(current_setting('request.jwt.claims', true)::json->'app_metadata'->>'role', ''), 'customer');
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."get_my_role"() TO "authenticated", "postgres", "service_role";

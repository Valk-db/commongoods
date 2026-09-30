CREATE OR REPLACE FUNCTION public.is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$function$;

GRANT EXECUTE ON FUNCTION "public"."is_admin"() TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."is_admin"() FROM PUBLIC;

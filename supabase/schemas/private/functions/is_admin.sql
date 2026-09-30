CREATE OR REPLACE FUNCTION private.is_admin()
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
  select coalesce(
    (select is_admin from public.profiles where id = auth.uid()),
    false
  );
$function$;

GRANT EXECUTE ON FUNCTION "private"."is_admin"() TO "authenticated", "postgres", "service_role";

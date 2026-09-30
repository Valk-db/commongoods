CREATE OR REPLACE FUNCTION private.current_role_is (
  target_role text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
  select coalesce(
    (select role = target_role from public.profiles where id = auth.uid()),
    false
  );
$function$;

GRANT EXECUTE ON FUNCTION "private"."current_role_is"(text) TO "authenticated", "postgres", "service_role";

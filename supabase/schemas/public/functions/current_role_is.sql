CREATE OR REPLACE FUNCTION public.current_role_is (
  target_role text
)
  RETURNS boolean
  LANGUAGE sql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
  select coalesce(
    (select role = target_role from public.profiles where id = auth.uid()),
    false
  );
$function$;

GRANT EXECUTE ON FUNCTION "public"."current_role_is"(text) TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."current_role_is"(text) FROM PUBLIC;

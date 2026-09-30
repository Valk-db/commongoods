CREATE OR REPLACE FUNCTION public.check_user_role (
  required_role text
)
  RETURNS boolean
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND (role = required_role OR is_admin = true)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."check_user_role"(text) TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."check_user_role"(text) FROM PUBLIC;

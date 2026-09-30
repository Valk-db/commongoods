CREATE OR REPLACE FUNCTION private.check_user_role (
  required_role text
)
  RETURNS boolean
  LANGUAGE plpgsql
  STABLE
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  RETURN EXISTS (
    SELECT 1 FROM public.profiles 
    WHERE id = auth.uid() AND (role = required_role OR is_admin = true)
  );
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."check_user_role"(text) TO "authenticated", "postgres", "service_role";

CREATE OR REPLACE FUNCTION public.enforce_profile_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
BEGIN
  -- Only enforce for non-service-role callers
  -- current_setting('role') returns the current role; service_role bypasses RLS
  IF current_setting('role') <> 'service_role' THEN
    -- Prevent changing is_admin (can only be set by service_role via admin panel)
    NEW.is_admin := OLD.is_admin;
    -- Prevent changing role (set at signup via handle_new_user, or by admin via service_role)
    NEW.role := OLD.role;
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "public"."enforce_profile_admin_fields"() TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."enforce_profile_admin_fields"() FROM PUBLIC;

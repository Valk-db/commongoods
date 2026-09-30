CREATE OR REPLACE FUNCTION private.enforce_driver_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.approved := OLD.approved;
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."enforce_driver_admin_fields"() TO "postgres";

CREATE OR REPLACE FUNCTION private.enforce_partner_application_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.status := OLD.status;
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."enforce_partner_application_admin_fields"() TO "postgres";

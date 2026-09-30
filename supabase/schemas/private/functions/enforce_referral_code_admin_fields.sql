CREATE OR REPLACE FUNCTION private.enforce_referral_code_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.active := OLD.active;
    NEW.used_by := OLD.used_by;
    NEW.used_at := OLD.used_at;
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."enforce_referral_code_admin_fields"() TO "postgres";

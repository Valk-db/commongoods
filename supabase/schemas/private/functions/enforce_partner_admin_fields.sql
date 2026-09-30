CREATE OR REPLACE FUNCTION private.enforce_partner_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public', 'private'
  AS $function$
BEGIN
  IF current_setting('role') <> 'service_role' THEN
    NEW.approved := OLD.approved;
    NEW.founding_merchant := OLD.founding_merchant;
    NEW.onboarding_fee_paid := OLD.onboarding_fee_paid;
    NEW.joined_during_pilot := OLD.joined_during_pilot;
    NEW.profile_id := OLD.profile_id;
  END IF;
  RETURN NEW;
END;
$function$;

GRANT EXECUTE ON FUNCTION "private"."enforce_partner_admin_fields"() TO "postgres";

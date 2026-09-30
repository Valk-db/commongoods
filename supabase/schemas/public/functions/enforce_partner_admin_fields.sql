CREATE OR REPLACE FUNCTION public.enforce_partner_admin_fields()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SET search_path TO 'public'
  AS $function$
begin
  if tg_op = 'UPDATE' and not public.is_admin() then
    new.approved             := old.approved;
    new.founding_merchant    := old.founding_merchant;
    new.onboarding_fee_paid  := old.onboarding_fee_paid;
    new.joined_during_pilot  := old.joined_during_pilot;
    new.profile_id           := old.profile_id;
  end if;
  return new;
end;
$function$;

GRANT EXECUTE ON FUNCTION "public"."enforce_partner_admin_fields"() TO PUBLIC, "anon", "authenticated", "postgres", "service_role";

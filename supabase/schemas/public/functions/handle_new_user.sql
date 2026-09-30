CREATE OR REPLACE FUNCTION public.handle_new_user()
  RETURNS TRIGGER
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
  AS $function$
declare
  user_role text;
begin
  user_role := coalesce(new.raw_user_meta_data->>'role', 'customer');

  insert into public.profiles (id, role, full_name)
  values (
    new.id,
    user_role,
    new.raw_user_meta_data->>'full_name'
  );

  -- Auto-create drivers row (pending approval) for driver signups
  if user_role = 'driver' then
    insert into public.drivers (id, is_online, approved)
    values (new.id, false, false);
  end if;

  return new;
end;
$function$;

GRANT EXECUTE ON FUNCTION "public"."handle_new_user"() TO "postgres", "service_role";

REVOKE ALL ON FUNCTION "public"."handle_new_user"() FROM PUBLIC;

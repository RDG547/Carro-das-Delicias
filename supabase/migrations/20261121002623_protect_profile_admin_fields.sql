create or replace function private.guard_profile_admin_fields()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
declare
  jwt_role text := coalesce(auth.jwt() ->> 'role', '');
begin
  if jwt_role = 'service_role'
     or (jwt_role = '' and current_user in ('postgres', 'supabase_auth_admin', 'service_role')) then
    return new;
  end if;
  if public.current_user_is_admin() then return new; end if;
  if tg_op = 'INSERT' then
    if coalesce(new.role, 'client') not in ('client', 'user')
       or coalesce(new.is_banned, false) or new.banned_until is not null then
      raise exception 'Somente administradores podem definir permissões de usuários' using errcode = '42501';
    end if;
  elsif new.role is distinct from old.role
     or new.is_banned is distinct from old.is_banned
     or new.banned_until is distinct from old.banned_until then
    raise exception 'Somente administradores podem alterar permissões de usuários' using errcode = '42501';
  end if;
  return new;
end;
$$;
drop trigger if exists profiles_guard_admin_fields on public.profiles;
create trigger profiles_guard_admin_fields
before insert or update on public.profiles
for each row execute function private.guard_profile_admin_fields();

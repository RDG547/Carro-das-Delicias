do $$
declare table_name text;
begin
  foreach table_name in array array['produtos', 'categorias', 'app_settings'] loop
    if not exists (
      select 1 from pg_publication_tables
      where pubname = 'supabase_realtime' and schemaname = 'public'
        and tablename = table_name
    ) then
      execute format('alter publication supabase_realtime add table public.%I', table_name);
    end if;
    execute format('alter table public.%I replica identity full', table_name);
  end loop;
end $$;

grant select on public.produtos, public.categorias, public.app_settings to anon, authenticated;

drop policy if exists catalog_admin_categories_manage on public.categorias;
create policy catalog_admin_categories_manage on public.categorias
for all to authenticated
using ((select public.current_user_is_admin()))
with check ((select public.current_user_is_admin()));

insert into public.app_settings(key, value)
values ('catalog_visibility', '{"show_products_without_photos":true}'::jsonb)
on conflict (key) do nothing;

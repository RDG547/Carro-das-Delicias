create or replace function public.reorder_categories(category_orders jsonb)
returns void
language plpgsql
security invoker
set search_path = ''
as $$
declare
  total integer;
  supplied integer;
begin
  if not public.current_user_is_admin() then
    raise exception 'Somente administradores podem reordenar categorias' using errcode = '42501';
  end if;
  if category_orders is null or pg_catalog.jsonb_typeof(category_orders) <> 'array' then
    raise exception 'Informe a lista completa das categorias' using errcode = '22023';
  end if;

  -- A ordem é global. O bloqueio dura apenas a validação e um UPDATE, sem I/O externo.
  lock table public.categorias in share row exclusive mode;
  select count(*) into total from public.categorias;
  supplied := pg_catalog.jsonb_array_length(category_orders);
  if supplied <> total
     or (select count(distinct (value->>'id')::integer) from pg_catalog.jsonb_array_elements(category_orders)) <> total
     or (select count(distinct (value->>'order')::integer) from pg_catalog.jsonb_array_elements(category_orders)) <> total
     or exists (
       select 1 from pg_catalog.jsonb_array_elements(category_orders) entry
       left join public.categorias c on c.id = (entry->>'id')::integer
       where c.id is null or (entry->>'order')::integer is null
          or (entry->>'order')::integer < 0 or (entry->>'order')::integer >= total
     ) then
    raise exception 'As categorias mudaram. Atualize a lista antes de salvar a ordem' using errcode = '22023';
  end if;

  update public.categorias c
  set ordem = (entry.value->>'order')::integer,
      "order" = (entry.value->>'order')::integer
  from pg_catalog.jsonb_array_elements(category_orders) entry(value)
  where c.id = (entry.value->>'id')::integer;
end;
$$;
revoke all on function public.reorder_categories(jsonb) from public, anon;
grant execute on function public.reorder_categories(jsonb) to authenticated;

-- Preserva a sequência atual e mantém o campo legado coerente com 'ordem'.
with ranked as (
  select id, (row_number() over (order by ordem nulls last, id) - 1)::integer as position
  from public.categorias
)
update public.categorias c set ordem = ranked.position, "order" = ranked.position
from ranked where c.id = ranked.id
  and (c.ordem is distinct from ranked.position or c."order" is distinct from ranked.position);

-- SOLO PARA LA PRUEBA LOCAL. NO se ejecuta en Supabase.
-- Reproduce lo que Supabase ya trae: esquema auth, auth.users, auth.uid() y los roles anon/authenticated.
create schema if not exists auth;
create table if not exists auth.users (id uuid primary key, email text unique);
create or replace function auth.uid() returns uuid language sql stable as $$
  select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
do $$ begin
  if not exists (select 1 from pg_roles where rolname = 'anon') then create role anon nologin; end if;
  if not exists (select 1 from pg_roles where rolname = 'authenticated') then create role authenticated nologin; end if;
end $$;
grant usage on schema auth to anon, authenticated;
grant execute on function auth.uid() to anon, authenticated;
-- Las 4 cuentas de prueba (en Supabase se crean desde Authentication → Users con estos correos).
insert into auth.users (id, email) values
  ('00000000-0000-0000-0000-0000000000c1', 'cliente1@akj.test'),
  ('00000000-0000-0000-0000-0000000000c2', 'cliente2@akj.test'),
  ('00000000-0000-0000-0000-0000000000e1', 'emprendedor1@akj.test'),
  ('00000000-0000-0000-0000-0000000000e2', 'emprendedor2@akj.test')
on conflict do nothing;

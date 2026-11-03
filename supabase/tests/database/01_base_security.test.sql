-- S12: base schema closed for writing. Clients read at most what they should and write nothing directly.
begin;
select plan(28);
delete from public.players;  -- the database may hold data from manual runs; this transaction is rolled back

-- Every table in public has row level security on (a new table without it fails this test).
select is(
  (select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind in ('r', 'p') and not c.relrowsecurity),
  0, 'todas las tablas de public tienen RLS');
select cmp_ok((select count(*)::int from pg_class c join pg_namespace n on n.oid = c.relnamespace
    where n.nspname = 'public' and c.relkind = 'r'), '>=', 1, 'hay al menos una tabla en public');

-- Nobody but the owner and the service role reaches the tables with write privileges.
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'authenticated', 'PUBLIC')
      and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE', 'REFERENCES', 'TRIGGER')),
  0, 'anon y authenticated no tienen privilegios de escritura sobre ninguna tabla');
select is(
  (select count(*)::int from information_schema.role_table_grants
    where table_schema = 'public' and grantee in ('anon', 'PUBLIC')),
  0, 'anon no tiene ningun privilegio sobre las tablas');

-- Helper schema is private.
select ok(not has_schema_privilege('anon', 'app_private', 'USAGE'), 'anon no usa app_private');
-- (authenticated needs usage so RLS policies can call app_private.me(); the schema is not in the API's exposed schemas)
select ok(not has_function_privilege('authenticated', 'app_private.clean_name(text,int,int)', 'EXECUTE'), 'authenticated no ejecuta clean_name');
select ok(not has_function_privilege('anon', 'app_private.me()', 'EXECUTE'), 'anon no ejecuta me()');

-- Functions in public: no default execute for PUBLIC or anon.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and (has_function_privilege('anon', p.oid, 'EXECUTE')
        or exists (select 1 from aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) a where a.grantee = 0))),
  0, 'ninguna funcion de public es ejecutable por anon ni por PUBLIC');
-- Every function in public is security definer with a pinned search_path.
select is(
  (select count(*)::int from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.prokind = 'f'
      and (not p.prosecdef or not exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%'))),
  0, 'toda funcion de public es security definer con search_path fijo');

insert into public.players (steam_id, name) values (7001, 'Ana'), (7002, 'Beto');

-- anon: nothing.
set local role anon;
select throws_ok($$select * from public.players$$, '42501', null, 'anon no lee players');
select throws_ok($$insert into public.players (steam_id, name) values (9, 'x')$$, '42501', null, 'anon no inserta');
select throws_ok($$update public.players set name = 'x'$$, '42501', null, 'anon no actualiza');
select throws_ok($$delete from public.players$$, '42501', null, 'anon no borra');
select throws_ok($$select public.touch_player('x')$$, '42501', null, 'anon no ejecuta touch_player');
reset role;

-- authenticated as Ana: no direct reads either (reads go through RPC functions that return ids as text), no direct writes.
select set_config('request.jwt.claims', '{"sub":"7001","role":"authenticated"}', true);
set local role authenticated;
select throws_ok($$select * from public.players$$, '42501', null, 'authenticated no lee las tablas directamente');
select throws_ok($$insert into public.players (steam_id, name) values (9, 'x')$$, '42501', null, 'authenticated no inserta');
select throws_ok($$update public.players set name = 'x' where steam_id = 7001$$, '42501', null, 'authenticated no actualiza');
select throws_ok($$delete from public.players where steam_id = 7001$$, '42501', null, 'authenticated no borra');

-- touch_player: sets her own name, sanitized.
select lives_ok($$select public.touch_player(E'  Ana\u202e  la\tgrande  ')$$, 'Ana actualiza su nombre');
reset role;
select is((select name from public.players where steam_id = 7001), 'Ana la grande', 'nombre sin controles bidi ni espacios repetidos');
set local role authenticated;
select throws_ok($$select public.touch_player(repeat('a', 33))$$, 'P0001', 'invalid_name', 'nombre demasiado largo');
select throws_ok($$select public.touch_player(E'\u202e \u2066')$$, 'P0001', 'invalid_name', 'nombre vacio tras limpiar');
select set_config('request.jwt.claims', '{"sub":"7003","role":"authenticated"}', true);
select lives_ok($$select public.touch_player('Nueva')$$, 'Un jugador sin fila se crea');
reset role;
select is((select name from public.players where steam_id = 7003), 'Nueva', 'la fila quedo a nombre de quien llamo');
select is((select name from public.players where steam_id = 7002), 'Beto', 'la de otro no se toca');
set local role authenticated;

-- A subject that is not a number, or a token without the authenticated role, is not a player.
select set_config('request.jwt.claims', '{"sub":"abc","role":"authenticated"}', true);
select throws_ok($$select public.touch_player('x')$$, '28000', 'not_authenticated', 'sub invalido');
select set_config('request.jwt.claims', '{"role":"authenticated"}', true);
select throws_ok($$select public.touch_player('x')$$, '28000', 'not_authenticated', 'sin sub');
select set_config('request.jwt.claims', '{"sub":"7001","role":"anon"}', true);
select throws_ok($$select public.touch_player('x')$$, '28000', 'not_authenticated', 'rol que no es authenticated');

reset role;
select * from finish();
rollback;

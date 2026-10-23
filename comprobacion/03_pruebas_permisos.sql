-- AKJ Impulsa · Pruebas de permisos y reglas (33 casos)
-- Corre igual en la base local y en el SQL Editor de Supabase (como usuario postgres).
-- Requiere 01_esquema_y_permisos.sql y 02_datos_de_prueba.sql. Deja la tabla de resultados al final.

drop table if exists pg_temp.resultados_pruebas;
create temp table resultados_pruebas (
  orden int, caso text, quien text, operacion text, esperado text, obtenido text, cumple boolean
);
grant all on resultados_pruebas to public;

do $$
begin
  if (select count(*) from auth.users where email in
      ('cliente1@akj.test','cliente2@akj.test','emprendedor1@akj.test','emprendedor2@akj.test')) < 4 then
    raise exception 'Faltan cuentas de prueba en auth.users (cliente1/2, emprendedor1/2 @akj.test)';
  end if;
  delete from public.solicitudes where mensaje like '[prueba]%';
end $$;

-- Función auxiliar temporal: ejecuta un caso y registra el resultado.
create or replace function pg_temp.probar(p_orden int, p_caso text, p_quien text, p_op text,
                                          p_rol text, p_uid uuid, p_sql text, p_esperado text,
                                          p_keep boolean default false)
returns void language plpgsql as $$
declare n int; res text; ok boolean;
begin
  begin
    execute format('set local role %I', p_rol);
    perform set_config('request.jwt.claim.sub', coalesce(p_uid::text, ''), true);
    if p_sql ~* '^\s*select' then
      execute 'select count(*) from (' || p_sql || ') t' into n;
    else
      execute 'with r as (' || p_sql || ') select count(*) from r' into n;
    end if;
    res := n || ' fila(s)';
    if not p_keep then raise exception using errcode = 'P0001', message = '__revertir__'; end if;
    execute 'reset role';
    perform set_config('request.jwt.claim.sub', '', true);
  exception when others then
    if sqlerrm <> '__revertir__' then res := 'error: ' || sqlerrm; end if;
  end;
  ok := case p_esperado
          when 'denegado'  then res like 'error:%' or res = '0 fila(s)'
          else res not like 'error:%' and res <> '0 fila(s)' end;
  insert into resultados_pruebas values (p_orden, p_caso, p_quien, p_op, p_esperado, res, ok);
end $$;

do $$
declare
  c1 uuid := (select id from auth.users where email = 'cliente1@akj.test');
  c2 uuid := (select id from auth.users where email = 'cliente2@akj.test');
  e1 uuid := (select id from auth.users where email = 'emprendedor1@akj.test');
  e2 uuid := (select id from auth.users where email = 'emprendedor2@akj.test');
  of1 text := '20000000-0000-0000-0000-000000000001';
  of3 text := '20000000-0000-0000-0000-000000000003';
  neg2 text := '10000000-0000-0000-0000-000000000002';
  sol text;
  leer text; estado text; oferta text;
  i int := 0;
  quien text; rol text; uid uuid;
begin
  -- P0: el cliente 1 crea la solicitud que usan los demás casos (se conserva)
  perform pg_temp.probar(0, 'P0', 'Cliente 1', 'Crear solicitud propia', 'authenticated', c1,
    format('insert into public.solicitudes (cliente_id, oferta_id, mensaje) values (%L, %L, %L) returning id',
           c1, of1, '[prueba] Pantalón azul, subir 3 cm'), 'permitido', true);
  select id::text into sol from public.solicitudes where mensaje like '[prueba]%' order by creada_en desc limit 1;
  if sol is null then raise exception 'P0 no creó la solicitud; revise el esquema'; end if;

  leer   := format('select id from public.solicitudes where id = %L', sol);
  estado := format('update public.solicitudes set estado = %L where id = %L returning id', 'en_atencion', sol);
  oferta := format('update public.ofertas set precio_cop = 1 where id = %L returning id', of1);

  -- N1–N12: 4 condiciones × 3 operaciones (criterio 8.4)
  for quien, rol, uid in
    select * from (values ('Visitante sin sesión', 'anon', null::uuid),
                          ('Cliente ajeno (cliente 2)', 'authenticated', c2),
                          ('Emprendedor ajeno (negocio 2)', 'authenticated', e2),
                          ('Sesión vencida (sin token válido)', 'anon', null::uuid)) v(a, b, c)
  loop
    i := i + 1; perform pg_temp.probar(i, 'N' || i, quien, 'Leer la solicitud', rol, uid, leer, 'denegado');
    i := i + 1; perform pg_temp.probar(i, 'N' || i, quien, 'Cambiar su estado', rol, uid, estado, 'denegado');
    i := i + 1; perform pg_temp.probar(i, 'N' || i, quien, 'Editar la oferta del negocio 1', rol, uid, oferta, 'denegado');
  end loop;

  -- X1–X8: reglas de negocio
  perform pg_temp.probar(13, 'X1', 'Cliente 1 (dueño de la solicitud)', 'Cambiar el estado de su propia solicitud', 'authenticated', c1, estado, 'denegado');
  perform pg_temp.probar(14, 'X2', 'Cliente 2', 'Crear solicitud a nombre del cliente 1', 'authenticated', c2,
    format('insert into public.solicitudes (cliente_id, oferta_id, mensaje) values (%L, %L, %L) returning id', c1, of1, '[prueba] suplantación'), 'denegado');
  perform pg_temp.probar(15, 'X3', 'Emprendedor 1', 'Crear una solicitud (no es cliente)', 'authenticated', e1,
    format('insert into public.solicitudes (cliente_id, oferta_id, mensaje) values (%L, %L, %L) returning id', e1, of1, '[prueba] x'), 'denegado');
  perform pg_temp.probar(16, 'X4', 'Cliente 1', 'Desviar la solicitud a otro negocio', 'authenticated', c1,
    format('insert into public.solicitudes (cliente_id, oferta_id, emprendimiento_id, mensaje) values (%L, %L, %L, %L) returning id', c1, of1, neg2, '[prueba] x'), 'denegado');
  perform pg_temp.probar(17, 'X5', 'Emprendedor 1', 'Cerrar sin motivo', 'authenticated', e1,
    format('update public.solicitudes set estado = %L where id = %L returning id', 'cerrada', sol), 'denegado');
  perform pg_temp.probar(18, 'X6', 'Emprendedor 1', 'Editar el mensaje del cliente', 'authenticated', e1,
    format('update public.solicitudes set mensaje = %L where id = %L returning id', '[prueba] cambiado', sol), 'denegado');
  perform pg_temp.probar(19, 'X7', 'Emprendedor 1', 'Borrar una solicitud', 'authenticated', e1,
    format('delete from public.solicitudes where id = %L returning id', sol), 'denegado');
  perform pg_temp.probar(20, 'X8', 'Emprendedor 1', 'Poner precio negativo a su oferta', 'authenticated', e1,
    format('update public.ofertas set precio_cop = -5 where id = %L returning id', of1), 'denegado');

  -- P1–P5: acceso normal
  perform pg_temp.probar(21, 'P1', 'Visitante sin sesión', 'Consultar el catálogo', 'anon', null,
    'select id from public.ofertas', 'permitido');
  perform pg_temp.probar(22, 'P2', 'Cliente 1', 'Leer su solicitud', 'authenticated', c1, leer, 'permitido');
  perform pg_temp.probar(23, 'P3', 'Emprendedor 1', 'Leer la solicitud de su negocio', 'authenticated', e1, leer, 'permitido');
  perform pg_temp.probar(24, 'P4', 'Emprendedor 1', 'Editar su oferta', 'authenticated', e1,
    format('update public.ofertas set precio_cop = 13000 where id = %L returning id', of1), 'permitido');
  perform pg_temp.probar(25, 'P5', 'Emprendedor 1', 'Pendiente → En atención', 'authenticated', e1, estado, 'permitido', true);

  -- Transiciones
  perform pg_temp.probar(26, 'X9', 'Emprendedor 1', 'En atención → Pendiente (devolver)', 'authenticated', e1,
    format('update public.solicitudes set estado = %L where id = %L returning id', 'pendiente', sol), 'denegado');
  perform pg_temp.probar(27, 'P6', 'Emprendedor 1', 'En atención → Cerrada con motivo', 'authenticated', e1,
    format('update public.solicitudes set estado = %L, motivo_cierre = %L where id = %L returning id', 'cerrada', 'Se acordó la entrega por WhatsApp', sol), 'permitido', true);
  perform pg_temp.probar(28, 'P7', 'Cliente 1', 'Ver el estado y el motivo actualizados', 'authenticated', c1,
    format('select estado, motivo_cierre from public.solicitudes where id = %L and estado = %L', sol, 'cerrada'), 'permitido');
  perform pg_temp.probar(29, 'X10', 'Emprendedor 1', 'Reabrir una solicitud cerrada', 'authenticated', e1,
    format('update public.solicitudes set estado = %L where id = %L returning id', 'en_atencion', sol), 'denegado');

  -- D1–D3: decisión de disponibilidad de ofertas
  perform pg_temp.probar(30, 'D1', 'Cliente 1', 'Ver una oferta no disponible en el catálogo', 'authenticated', c1,
    format('select id from public.ofertas where id = %L', of3), 'denegado');
  perform pg_temp.probar(31, 'D2', 'Cliente 1', 'Crear solicitud sobre una oferta no disponible', 'authenticated', c1,
    format('insert into public.solicitudes (cliente_id, oferta_id, mensaje) values (%L, %L, %L) returning id', c1, of3, '[prueba] x'), 'denegado');
  perform pg_temp.probar(32, 'D3', 'Emprendedor 1', 'Ver su propia oferta no disponible', 'authenticated', e1,
    format('select id from public.ofertas where id = %L', of3), 'permitido');
end $$;

select caso, quien, operacion, esperado, obtenido, cumple from (
  select orden, caso, quien, operacion, esperado, obtenido, case when cumple then 'Sí' else 'NO' end as cumple
  from resultados_pruebas
  union all
  select 999, 'TOTAL', count(*) filter (where cumple) || ' de ' || count(*) || ' casos cumplen', '', '', '', ''
  from resultados_pruebas
) t order by orden;

-- Datos ficticios de prueba. En Supabase, crear antes las 4 cuentas en Authentication → Users:
-- cliente1@akj.test, cliente2@akj.test, emprendedor1@akj.test, emprendedor2@akj.test
insert into public.perfiles (id, rol, nombre)
select id, case when email like 'cliente%' then 'cliente' else 'emprendedor' end,
       case email when 'cliente1@akj.test' then 'Cliente 1' when 'cliente2@akj.test' then 'Cliente 2'
                  when 'emprendedor1@akj.test' then 'Emprendedor 1 (modistería)' else 'Emprendedor 2 (muebles)' end
from auth.users
where email in ('cliente1@akj.test','cliente2@akj.test','emprendedor1@akj.test','emprendedor2@akj.test')
on conflict (id) do nothing;

insert into public.emprendimientos (id, propietario_id, nombre, contacto)
select '10000000-0000-0000-0000-000000000001', id, 'Modistería de prueba', 'https://wa.me/570000000001'
from auth.users where email = 'emprendedor1@akj.test'
on conflict (id) do nothing;
insert into public.emprendimientos (id, propietario_id, nombre, contacto)
select '10000000-0000-0000-0000-000000000002', id, 'Restauración de prueba', null
from auth.users where email = 'emprendedor2@akj.test'
on conflict (id) do nothing;

insert into public.ofertas (id, emprendimiento_id, nombre, descripcion, categoria, precio_cop, disponible) values
  ('20000000-0000-0000-0000-000000000001','10000000-0000-0000-0000-000000000001','Subir ruedo','Ruedo de pantalón o falda','Arreglos',12000,true),
  ('20000000-0000-0000-0000-000000000002','10000000-0000-0000-0000-000000000002','Restaurar silla','Lijado y acabado','Muebles',90000,true),
  ('20000000-0000-0000-0000-000000000003','10000000-0000-0000-0000-000000000001','Vestido de fiesta a medida','Confección completa','Confección',250000,false)
on conflict (id) do nothing;

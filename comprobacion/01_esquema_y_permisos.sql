-- AKJ Impulsa · Esquema y políticas de acceso (v2, 19 oct 2026)
-- Se ejecuta tal cual en el SQL Editor de Supabase.
-- Decisiones incluidas: D1 disponibilidad de ofertas (campo "disponible"),
-- D2 contacto del negocio (campo "contacto"), D3 sin fecha tentativa en el piloto.

create type estado_solicitud as enum ('pendiente', 'en_atencion', 'cerrada');

create table public.perfiles (
  id uuid primary key references auth.users(id),
  rol text not null check (rol in ('cliente', 'emprendedor')),
  nombre text not null
);

create table public.emprendimientos (
  id uuid primary key default gen_random_uuid(),
  propietario_id uuid not null references public.perfiles(id),
  nombre text not null,
  contacto text            -- D2: canal del negocio (p. ej. enlace de WhatsApp); nunca datos del cliente
);

create table public.ofertas (
  id uuid primary key default gen_random_uuid(),
  emprendimiento_id uuid not null references public.emprendimientos(id),
  nombre text not null check (length(trim(nombre)) > 0),
  descripcion text not null check (length(trim(descripcion)) > 0),
  categoria text not null,
  precio_cop numeric(12,0) not null check (precio_cop >= 0),
  precio_es_referencia boolean not null default true,
  disponible boolean not null default true   -- D1
);

create table public.solicitudes (
  id uuid primary key default gen_random_uuid(),
  cliente_id uuid not null references public.perfiles(id),
  oferta_id uuid not null references public.ofertas(id),
  emprendimiento_id uuid not null references public.emprendimientos(id),
  mensaje text not null check (length(trim(mensaje)) between 1 and 500),
  estado estado_solicitud not null default 'pendiente',
  motivo_cierre text,
  creada_en timestamptz not null default now(),
  actualizada_en timestamptz not null default now(),
  constraint cierre_con_motivo check (estado <> 'cerrada' or length(trim(coalesce(motivo_cierre,''))) > 0)
);

-- Reglas en la base ---------------------------------------------------------
-- Al crear: el negocio sale de la oferta (nunca del navegador), la oferta debe estar disponible
-- y el estado inicia en pendiente.
create or replace function public.antes_de_crear_solicitud() returns trigger
language plpgsql security definer set search_path = public as $$
declare v_negocio uuid;
begin
  select o.emprendimiento_id into v_negocio from ofertas o where o.id = new.oferta_id and o.disponible;
  if v_negocio is null then raise exception 'La oferta no existe o no está disponible'; end if;
  if new.emprendimiento_id is not null and new.emprendimiento_id <> v_negocio then
    raise exception 'El emprendimiento no corresponde a la oferta';
  end if;
  new.emprendimiento_id := v_negocio;
  new.estado := 'pendiente'; new.motivo_cierre := null;
  new.creada_en := now(); new.actualizada_en := now();
  return new;
end $$;
create trigger t_crear_solicitud before insert on public.solicitudes
  for each row execute function public.antes_de_crear_solicitud();

-- Al actualizar: solo cambian estado y motivo, y solo en las transiciones de 4.5.
create or replace function public.antes_de_actualizar_solicitud() returns trigger
language plpgsql as $$
begin
  if (new.cliente_id, new.oferta_id, new.emprendimiento_id, new.mensaje, new.creada_en)
     is distinct from (old.cliente_id, old.oferta_id, old.emprendimiento_id, old.mensaje, old.creada_en) then
    raise exception 'Solo se pueden cambiar el estado y el motivo de cierre';
  end if;
  if not ((old.estado = 'pendiente'   and new.estado in ('en_atencion','cerrada'))
       or (old.estado = 'en_atencion' and new.estado = 'cerrada')) then
    raise exception 'Transición no permitida: % → %', old.estado, new.estado;
  end if;
  new.actualizada_en := now();
  return new;
end $$;
create trigger t_actualizar_solicitud before update on public.solicitudes
  for each row execute function public.antes_de_actualizar_solicitud();

-- Permisos ------------------------------------------------------------------
-- Supabase concede por defecto todos los privilegios a anon y authenticated; se retiran
-- y se conceden solo los necesarios.
revoke all on public.perfiles, public.emprendimientos, public.ofertas, public.solicitudes from anon, authenticated;

alter table public.perfiles        enable row level security;
alter table public.emprendimientos enable row level security;
alter table public.ofertas         enable row level security;
alter table public.solicitudes     enable row level security;

grant usage on schema public to anon, authenticated;
grant select on public.emprendimientos, public.ofertas to anon, authenticated;
grant select on public.perfiles to authenticated;
grant insert, update on public.ofertas to authenticated;
grant select on public.solicitudes to authenticated;
grant insert (oferta_id, mensaje, cliente_id) on public.solicitudes to authenticated;
grant update (estado, motivo_cierre) on public.solicitudes to authenticated;
-- Sin DELETE para nadie: en el piloto las solicitudes no se borran.

create policy perfil_propio on public.perfiles for select to authenticated
  using (id = auth.uid());

create policy catalogo_negocios on public.emprendimientos for select to anon, authenticated
  using (true);

-- Catálogo: cualquiera ve las ofertas disponibles; el dueño ve también las suyas no disponibles (D1).
create policy catalogo_ofertas on public.ofertas for select to anon, authenticated
  using (disponible or exists (select 1 from public.emprendimientos e
                               where e.id = emprendimiento_id and e.propietario_id = auth.uid()));
create policy crear_oferta_propia on public.ofertas for insert to authenticated
  with check (exists (select 1 from public.emprendimientos e
                      where e.id = emprendimiento_id and e.propietario_id = auth.uid()));
create policy editar_oferta_propia on public.ofertas for update to authenticated
  using      (exists (select 1 from public.emprendimientos e where e.id = emprendimiento_id and e.propietario_id = auth.uid()))
  with check (exists (select 1 from public.emprendimientos e where e.id = emprendimiento_id and e.propietario_id = auth.uid()));

-- Solicitudes: el cliente ve las suyas; el emprendedor, las de su negocio.
create policy ver_solicitudes on public.solicitudes for select to authenticated
  using (cliente_id = auth.uid()
         or exists (select 1 from public.emprendimientos e
                    where e.id = emprendimiento_id and e.propietario_id = auth.uid()));
create policy crear_solicitud on public.solicitudes for insert to authenticated
  with check (cliente_id = auth.uid()
              and exists (select 1 from public.perfiles p where p.id = auth.uid() and p.rol = 'cliente'));
create policy gestionar_solicitud on public.solicitudes for update to authenticated
  using      (exists (select 1 from public.emprendimientos e where e.id = emprendimiento_id and e.propietario_id = auth.uid()))
  with check (exists (select 1 from public.emprendimientos e where e.id = emprendimiento_id and e.propietario_id = auth.uid()));

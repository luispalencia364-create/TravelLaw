-- ---------------------------------------------------------------------
-- Números de emergencia automáticos para cada destino
--
-- Todo destino creado desde el panel de administración debe iniciar
-- con las líneas nacionales de emergencia en el módulo SOS. Esta
-- migración:
--   1) Rellena los contactos faltantes en los destinos existentes.
--   2) Actualiza admin_crear_destino para insertarlos al crear.
-- ---------------------------------------------------------------------

-- 1. Backfill: destinos que aún no tienen las líneas nacionales.
insert into public.contacto_emergencia (id_destino, entidad, telefono, fuente)
select d.id_destino, c.entidad, c.telefono,
       'Línea nacional - pendiente de validación local'
from public.destino d
cross join (values
  ('Línea Única de Emergencias', '123'),
  ('Bomberos',                   '119'),
  ('Cruz Roja Colombiana',       '132'),
  ('Defensa Civil',              '144')
) as c (entidad, telefono)
where not exists (
  select 1 from public.contacto_emergencia ce
  where ce.id_destino = d.id_destino
    and ce.telefono = c.telefono
);

-- 2. Crear destino con sus contactos de emergencia por defecto.
create or replace function public.admin_crear_destino(
  p_nombre    text,
  p_municipio text,
  p_lat       double precision,
  p_lng       double precision
)
returns int
language plpgsql
security definer
set search_path = public, extensions
as $$
declare
  v_id int;
begin
  if not private.es_staff() then
    raise exception 'Solo el equipo de TravelLaw puede gestionar destinos'
      using errcode = '42501';
  end if;

  if p_nombre is null or btrim(p_nombre) = ''
     or p_municipio is null or btrim(p_municipio) = '' then
    raise exception 'Nombre y municipio son obligatorios';
  end if;

  if p_lat is null or p_lng is null
     or p_lat < -90 or p_lat > 90 or p_lng < -180 or p_lng > 180 then
    raise exception 'Coordenadas no válidas';
  end if;

  if exists (
    select 1 from public.destino
    where lower(nombre) = lower(btrim(p_nombre))
  ) then
    raise exception 'Ya existe un destino con ese nombre';
  end if;

  insert into public.destino (nombre, municipio, ubicacion)
  values (
    btrim(p_nombre),
    btrim(p_municipio),
    st_setsrid(st_makepoint(p_lng, p_lat), 4326)::geography
  )
  returning id_destino into v_id;

  -- Todo destino nuevo inicia con las líneas nacionales de emergencia.
  insert into public.contacto_emergencia (id_destino, entidad, telefono, fuente)
  select v_id, c.entidad, c.telefono,
         'Línea nacional - pendiente de validación local'
  from (values
    ('Línea Única de Emergencias', '123'),
    ('Bomberos',                   '119'),
    ('Cruz Roja Colombiana',       '132'),
    ('Defensa Civil',              '144')
  ) as c (entidad, telefono);

  return v_id;
end;
$$;

revoke all on function public.admin_crear_destino(
  text, text, double precision, double precision
) from public, anon;
grant execute on function public.admin_crear_destino(
  text, text, double precision, double precision
) to authenticated;

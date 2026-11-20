-- =====================================================================
-- TravelLaw · Comunidad de viajeros como mini red social
-- =====================================================================
-- Agrega "me gusta" a las publicaciones y deja listo el terreno para
-- comentarios y fotos. Los comentarios y las evidencias ya existían en
-- el esquema base; esta migración añade la tabla de likes, sus políticas
-- y un índice para ordenar comentarios por fecha.
-- =====================================================================
set search_path to public, extensions;

-- ---------------------------------------------------------------------
-- 1. ME GUSTA
--    Un usuario solo puede dar "me gusta" una vez por publicación.
-- ---------------------------------------------------------------------
create table if not exists public.me_gusta (
  id_publicacion uuid not null references public.publicacion (id_publicacion) on delete cascade,
  id_usuario     uuid not null references public.usuario (id_usuario) on delete cascade,
  fecha          timestamptz not null default now(),
  primary key (id_publicacion, id_usuario)
);

alter table public.me_gusta enable row level security;

drop policy if exists "me gusta: ver" on public.me_gusta;
create policy "me gusta: ver" on public.me_gusta for select to authenticated
  using (
    exists (
      select 1
      from public.publicacion p
      where p.id_publicacion = me_gusta.id_publicacion
    )
  );

drop policy if exists "me gusta: crear" on public.me_gusta;
create policy "me gusta: crear" on public.me_gusta for insert to authenticated
  with check (
    id_usuario = (select auth.uid())
    and (select private.usuario_activo())
    and exists (
      select 1
      from public.publicacion p
      where p.id_publicacion = me_gusta.id_publicacion
        and p.estado = 'publicada'
    )
  );

drop policy if exists "me gusta: retirar propio" on public.me_gusta;
create policy "me gusta: retirar propio" on public.me_gusta for delete to authenticated
  using (id_usuario = (select auth.uid()));

grant select, insert, delete on public.me_gusta to authenticated;

-- ---------------------------------------------------------------------
-- 2. COMENTARIOS
--    La tabla y sus políticas ya existen. Solo se agrega un índice
--    compuesto para cargar el hilo de cada publicación por fecha.
-- ---------------------------------------------------------------------
create index if not exists idx_comentario_publicacion_fecha
  on public.comentario (id_publicacion, fecha);

-- ---------------------------------------------------------------------
-- 3. FOTOS / EVIDENCIAS
--    La tabla evidencia y el bucket privado "evidencias" ya existen.
--    Las políticas actuales permiten:
--      · que el dueño de la publicación suba fotos a <uid>/...
--      · que cualquier usuario autenticado vea las fotos de
--        publicaciones visibles.
--    No se requieren cambios adicionales.
-- ---------------------------------------------------------------------

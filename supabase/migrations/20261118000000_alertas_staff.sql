-- =====================================================================
-- TravelLaw · Staff puede crear alertas verificadas
-- =====================================================================
-- Permite que moderadores, administradores y superadministradores creen
-- alertas desde el módulo normal que se publican directamente (verificadas),
-- sin pasar por la cola de moderación.
-- =====================================================================
set search_path to public, extensions;

drop policy if exists "alerta: crear" on public.alerta;

create policy "alerta: crear" on public.alerta
  for insert to authenticated
  with check (
    id_usuario = (select auth.uid())
    and (
      -- Turistas/residentes: siempre pendiente de moderación.
      (estado = 'pendiente_moderacion' and id_moderador is null)
      -- Staff: puede publicar directamente como verificada.
      or (
        (select private.es_staff())
        and estado in ('pendiente_moderacion', 'verificada')
        and (estado = 'pendiente_moderacion' or id_moderador is null)
      )
    )
  );
-- =====================================================================
-- TravelLaw · Alertas: visibilidad solo después de la moderación
-- =====================================================================
-- Hasta ahora la política "alerta: ver" dejaba leer las alertas en estado
-- 'pendiente_moderacion' a cualquier usuario autenticado, por lo que un
-- reporte recién creado aparecía en el feed público antes de ser revisado.
--
-- Con este cambio:
--   * El autor sigue viendo sus propias alertas en cualquier estado.
--   * El staff (moderador/administrador) ve todo para poder moderar.
--   * El resto de usuarios solo ve alertas 'verificada'.
-- =====================================================================
set search_path to public, extensions;

-- 1. Lectura pública únicamente de alertas verificadas.
drop policy if exists "alerta: ver" on alerta;
create policy "alerta: ver" on alerta for select to authenticated
  using (id_usuario = (select auth.uid())
         or estado = 'verificada'
         or (select private.es_staff()));

-- 2. Solo se pueden confirmar alertas ya verificadas de otros usuarios.
drop policy if exists "confirmacion: crear" on confirmacion_alerta;
create policy "confirmacion: crear" on confirmacion_alerta
  for insert to authenticated
  with check (id_usuario = (select auth.uid())
              and (select private.usuario_activo())
              and exists (select 1 from public.alerta a
                          where a.id_alerta = confirmacion_alerta.id_alerta
                            and a.id_usuario <> (select auth.uid())
                            and a.estado = 'verificada'));

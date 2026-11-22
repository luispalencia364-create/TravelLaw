# Panel de administración de TravelLaw

## 1. Aplicar los cambios en Supabase

En **Supabase → SQL Editor**, ejecuta en este orden:

1. `supabase/migrations/20261108000000_admin_control.sql`
2. `supabase/migrations/20261109000000_contenido_admin.sql`
3. `supabase/migrations/20261110000000_alertas_moderacion.sql`
4. `supabase/migrations/20261111000000_sos_destinos.sql`
5. `supabase/migrations/20261112000000_moderacion_permisos.sql`
6. `supabase/migrations/20261113000000_lugares_publicos.sql`
7. `supabase/migrations/20261114000000_comunidad_social.sql`
8. `supabase/migrations/20261115000000_notificaciones.sql`
9. `supabase/migrations/20261116000000_moderacion_comunidad.sql`
10. `supabase/migrations/20261117000000_expresiones_aprobacion.sql`
11. `supabase/seed.sql`

El primero crea el rol de **superadministrador**, las funciones para
crear/gestionar cuentas y las protecciones para que nadie pueda ascenderse
a sí mismo. El segundo añade la **gestión de contenido** (lugares con estado
activo/inactivo, destinos, normas, alertas oficiales y contactos SOS con
funciones RPC que aceptan coordenadas). El tercero oculta las alertas
`pendiente_moderacion` del feed público hasta que un moderador o
administrador las verifique. El cuarto garantiza que **todo destino nuevo
nazca con las líneas nacionales de emergencia** (123, 119, 132 y 144) en el
módulo SOS y rellena los destinos existentes que no las tengan. El quinto
limita a los moderadores a **suspender o reactivar cuentas de turista**
(sin poder eliminarlas ni tocar administradores). El sexto expone los
**lugares activos** (restaurantes, alojamientos, atracciones...) para que
el buscador de la app los encuentre por nombre, categoría o destino. El
séptimo convierte la **comunidad de viajeros** en una mini red social con
me gusta, comentarios y fotos. El octavo agrega las **notificaciones**
para turistas: guarda el destino activo y la última ubicación, crea la
tabla `notificacion` con RLS y Realtime, y avisa de alertas de la zona,
me gusta y comentarios. El noveno añade la **moderación de la comunidad**:
restringir, eliminar o restaurar publicaciones, con aviso al autor. El
décimo permite que cualquier viajero proponga **expresiones culturales**
que quedan pendientes hasta que un moderador o administrador las
apruebe; solo las aprobadas son visibles para el resto. El
undécimo crea el administrador de ejemplo.

> Es importante aplicar la migración antes de abrir la app: el perfil del
> usuario ahora incluye la columna `es_super_admin`.

Si usas la CLI de Supabase:

```bash
supabase db push
# o, para un entorno local:
supabase db reset
```

## 2. Administrador de ejemplo

| Dato | Valor |
| --- | --- |
| Nombre | Administrador General |
| Correo | `admin@travellaw.app` |
| Contraseña | `TravelLaw2026*` |
| Rol | Administrador (superadministrador) |

> Cambia la contraseña antes de publicar la app.

## 3. Cómo entrar

1. Inicia sesión con el correo y la contraseña de ejemplo.
2. Abre el menú lateral.
3. Entra a **Panel de administración**.

Desde ahí puedes:

- Ver el resumen de usuarios, administradores, moderadores y suspendidos.
- Crear administradores y moderadores.
- Nombrar moderadores o administradores.
- Suspender o reactivar permisos.
- Eliminar cuentas (si no tienen contenido asociado; si lo tienen, el
  sistema recomienda suspenderlas).
- Entrar a cualquier módulo de la app con el acceso total del administrador.
- Abrir **Gestión de contenido** (tarjeta del resumen), con 5 pestañas:

| Pestaña | Qué permite |
| --- | --- |
| Lugares | Crear, editar, **deshabilitar/habilitar** y borrar lugares de cada destino (nombre, categoría, horario, coordenadas). |
| Destinos | Crear y editar destinos, y desactivarlos del mapa con un interruptor (el borrado es definitivo y arranca con sus lugares, normas, alertas y contactos). Todo destino nuevo se crea con las líneas nacionales de emergencia (123, 119, 132 y 144) en SOS. |
| Normas | Crear, editar, descontinuar (deja de mostrarse) y borrar normas legales/ambientales/culturales por destino, con fuente y versión en inglés opcional. |
| Alertas | Crear alertas oficiales verificadas, verificar/rechazar/marcar vencidas, editar y borrar. |
| Contactos SOS | Agregar, editar y borrar contactos de emergencia por destino (entidad, teléfono, dirección, fuente). |

## 3.1 Funciones SQL nuevas (migración 2)

- Columna `lugar.activo` (por defecto `true`): deshabilitar un lugar lo
  oculta de la app sin borrarlo.
- Listados: `listar_destinos_admin`, `listar_categorias_lugar`,
  `listar_lugares_admin`, `listar_normas_admin`, `listar_contactos_admin`,
  `listar_alertas_admin` (devuelven lat/lng simples en vez de PostGIS).
- Escritura con coordenadas: `admin_crear_destino`,
  `admin_actualizar_destino`, `admin_crear_lugar`,
  `admin_actualizar_lugar` y `admin_crear_alerta` (permite publicar alertas
  ya verificadas, algo que las políticas RLS normales no permitían).
- Crear/editar/eliminar normas y contactos SOS se hace con el cliente de
  Supabase directamente: las políticas "staff gestiona" ya lo permiten.

## 3.2 Panel de moderación

Moderadores y administradores activos tienen la entrada **"Moderación"** en
el menú lateral (ruta `/moderacion`). Tiene 5 pestañas:

| Pestaña | Qué permite |
| --- | --- |
| Alertas | Verificar (publica en el destino), rechazar y **eliminar** alertas de viajeros. Se puede alternar entre pendientes y todas. |
| Reportes | Ver los reportes de cobro abusivo de los viajeros y **eliminarlos**. |
| SOS | Filtrar por destino y **eliminar** contactos de emergencia del módulo SOS. |
| Turistas | Buscar cuentas de turista y **suspenderlas o reactivarlas**. No permite eliminarlas ni cambiarles el rol, el correo o el nombre. |
| Comunidad | Ver las publicaciones de la comunidad y **restringirlas** (dejan de ser visibles), **eliminarlas** o **restaurarlas**. El autor recibe una notificación con el motivo. |

Los administradores conservan el acceso completo desde **Gestión de
contenido** (alertas y contactos SOS) y desde **Panel de administración →
Usuarios** (suspender, reactivar, cambiar rol o eliminar cuentas).

## 4. Reglas de seguridad

- Solo el **superadministrador** puede crear o modificar administradores,
  cambiar el flag de superadministrador y eliminar cuentas.
- Los administradores normales pueden crear moderadores y suspender cuentas
  de usuarios.
- Los **moderadores** pueden verificar/eliminar alertas, reportes y contactos
  SOS, pero sobre las cuentas solo pueden **suspender o reactivar turistas**.
  No pueden eliminarlas ni gestionar administradores.
- Un usuario suspendido ve una pantalla de bloqueo y no puede usar la app.
- Siempre debe quedar al menos un superadministrador activo.
- El flag `es_super_admin` no se puede activar desde el cliente: la base de
  datos lo protege con un trigger.
- Las funciones de contenido solo las puede ejecutar el equipo
  (`private.es_staff()`: administradores y moderadores); el panel de
  administración además pide rol de administrador activo.

## 5. Flujos de los viajeros y moderación

Los usuarios con rol **turista** (y en general cualquier usuario activo) ya
pueden participar desde la app:

- **Alertas y reportes → botón "Reportar alerta"**: crea una alerta con
  estado `pendiente_moderacion`. No aparece en el feed público hasta que el
  staff la verifica.
- **Comunidad de viajeros → botón "Publicar"**: publica una recomendación
  con hasta 5 fotos. Cada publicación permite dar **me gusta**, abrir el
  hilo de **comentarios** y ampliar las fotos. El autor y el staff pueden
  eliminar publicaciones y comentarios.
- **Precios y cobros → botón "Reportar cobro"**: envía un reporte de cobro
  abusivo con estado `pendiente_revision`; solo lo ve el autor y el staff.
- **Buscador de destinos y lugares**: en la pantalla de inicio se puede
  escribir el nombre de un destino, municipio o lugar (por ejemplo
  "Osaka") para ver coincidencias. En el selector de destino de cada módulo
  se filtran solo los destinos. Al tocar un lugar se activa su destino y se
  muestra su categoría y horario.

Para moderar, moderadores y administradores tienen la entrada
**"Moderación"** en el menú lateral (ruta `/moderacion`). Desde ahí pueden
**Verificar** (pasa a `verificada` y se publica), **Rechazar** o **Eliminar**
alertas; **eliminar** reportes de cobro y contactos SOS; y **suspender o
reactivar** cuentas de turista. Los administradores también pueden gestionar
alertas y contactos SOS desde **Panel de administración → Gestión de
contenido**, y todas las cuentas desde **Panel de administración → Usuarios**.

La migración 3 (`20261110000000_alertas_moderacion.sql`) refuerza esto en la
base de datos: solo el autor, el staff y las alertas verificadas son
visibles para el resto de usuarios. La migración 5
(`20261112000000_moderacion_permisos.sql`) limita al moderador a ver y
suspender/reactivar únicamente cuentas de turista. La migración 6
(`20261113000000_lugares_publicos.sql`) expone los lugares activos de
destinos activos mediante `listar_lugares_publicos()`, usando la lectura
pública de `lugar` y `categoria_lugar`. La migración 7
(`20261114000000_comunidad_social.sql`) crea `me_gusta` con sus políticas y
un índice para el hilo de comentarios. Las fotos usan el bucket privado
`evidencias` y la tabla `evidencia` que ya existían.

La migración 8 (`20261115000000_notificaciones.sql`) añade la campana de
**notificaciones** para los viajeros. Guarda el destino activo y la última
ubicación del usuario, crea la tabla `notificacion` con RLS y Realtime, y
genera avisos cuando se sube o verifica una alerta de su zona, cuando
alguien da me gusta a su publicación y cuando alguien la comenta. La
migración 9 (`20261116000000_moderacion_comunidad.sql`) agrega las columnas
`motivo_moderacion`/`fecha_moderacion` a `publicacion` y las funciones
`listar_publicaciones_moderacion()` y `moderar_publicacion()` para
restringir, eliminar o restaurar publicaciones avisando al autor.

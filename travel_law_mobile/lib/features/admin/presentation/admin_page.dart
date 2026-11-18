import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../app/rutas.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../data/admin_repository.dart';
import 'widgets/crear_cuenta_dialog.dart';

/// Panel exclusivo del administrador. Desde aquí se gestionan las cuentas,
/// los roles y el acceso a todos los módulos de TravelLaw.
class AdminPage extends ConsumerWidget {
  const AdminPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider);

    return perfil.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _AccesoDenegado(
        detalle: 'No se pudo verificar tu rol. Revisa tu conexión.',
      ),
      data: (p) {
        if (p == null || !p.esAdministrador || p.estado != 'activo') {
          return const _AccesoDenegado();
        }
        return _PanelAdmin(perfil: p);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Acceso restringido
// ─────────────────────────────────────────────────────────────

class _AccesoDenegado extends StatelessWidget {
  const _AccesoDenegado({this.detalle});

  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Panel de administración')),
      body: Column(
        children: [
          Expanded(
            child: EmptyState(
              icon: Icons.lock_outline,
              message: 'Acceso restringido',
              detail: detalle ??
                  'Solo el administrador de TravelLaw puede entrar a este panel.',
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.go('/'),
                icon: const Icon(Icons.arrow_back),
                label: const Text('Volver al inicio'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Panel principal
// ─────────────────────────────────────────────────────────────

class _PanelAdmin extends ConsumerStatefulWidget {
  const _PanelAdmin({required this.perfil});

  final Perfil perfil;

  @override
  ConsumerState<_PanelAdmin> createState() => _PanelAdminState();
}

class _PanelAdminState extends ConsumerState<_PanelAdmin> {
  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _crearCuenta() async {
    final creado = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => CrearCuentaDialog(
        esSuperAdmin: widget.perfil.esSuperAdmin,
      ),
    );

    if (creado != true) return;
    ref.invalidate(usuariosAdminProvider);
    _mensaje('Cuenta creada correctamente.');
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Panel de administración'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.dashboard_outlined), text: 'Resumen'),
              Tab(icon: Icon(Icons.people_alt_outlined), text: 'Usuarios'),
              Tab(
                icon: Icon(Icons.admin_panel_settings_outlined),
                text: 'Administradores',
              ),
            ],
          ),
        ),
        body: TabBarView(
          children: [
            _ResumenTab(perfil: widget.perfil),
            _UsuariosTab(perfil: widget.perfil),
            _UsuariosTab(perfil: widget.perfil, soloAdministradores: true),
          ],
        ),
        floatingActionButton: FloatingActionButton.extended(
          onPressed: _crearCuenta,
          icon: const Icon(Icons.person_add_alt_1),
          label: Text(
            widget.perfil.esSuperAdmin ? 'Crear admin' : 'Crear moderador',
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: resumen
// ─────────────────────────────────────────────────────────────

class _ResumenTab extends ConsumerWidget {
  const _ResumenTab({required this.perfil});

  final Perfil perfil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usuariosAsync = ref.watch(usuariosAdminProvider);
    final textTheme = Theme.of(context).textTheme;

    return RefreshIndicator(
      onRefresh: () async {
        final _ = await ref.refresh(usuariosAdminProvider.future);
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
        children: [
          _EncabezadoAdmin(perfil: perfil),
          const SizedBox(height: 20),
          const _TarjetaContenido(),
          const SizedBox(height: 20),
          usuariosAsync.when(
            skipLoadingOnReload: true,
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(16),
                child: CircularProgressIndicator(),
              ),
            ),
            error: (e, _) => _AvisoConfiguracion(error: e),
            data: (usuarios) => _Estadisticas(usuarios: usuarios),
          ),
          const SizedBox(height: 24),
          Text('Acceso total a la app', style: textTheme.titleMedium),
          const SizedBox(height: 4),
          const Text(
            'El administrador puede entrar a cualquier módulo y supervisar '
            'toda la información de la plataforma.',
          ),
          const SizedBox(height: 12),
          const _AccesoModulos(),
          const SizedBox(height: 24),
          _NotaPermisos(perfil: perfil),
        ],
      ),
    );
  }
}

class _EncabezadoAdmin extends StatelessWidget {
  const _EncabezadoAdmin({required this.perfil});

  final Perfil perfil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            scheme.primary,
            Color.lerp(scheme.primary, scheme.tertiary, 0.65)!,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(24),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CircleAvatar(
                radius: 26,
                backgroundColor: scheme.onPrimary.withValues(alpha: 0.18),
                child: Icon(
                  Icons.admin_panel_settings,
                  color: scheme.onPrimary,
                  size: 30,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      perfil.esSuperAdmin
                          ? 'Control total de TravelLaw'
                          : 'Panel de administración',
                      style: textTheme.titleLarge?.copyWith(
                        color: scheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      perfil.nombre,
                      style: textTheme.bodyMedium?.copyWith(
                        color: scheme.onPrimary.withValues(alpha: 0.9),
                      ),
                    ),
                  ],
                ),
              ),
              if (perfil.esSuperAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.onPrimary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    'SUPERADMIN',
                    style: textTheme.labelSmall?.copyWith(
                      color: scheme.onPrimary,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _DatoChip(
                icono: Icons.email_outlined,
                texto: perfil.email,
                color: scheme.onPrimary,
              ),
              _DatoChip(
                icono: Icons.badge_outlined,
                texto: perfil.rolEtiqueta,
                color: scheme.onPrimary,
              ),
              _DatoChip(
                icono: Icons.verified_user_outlined,
                texto: perfil.estadoEtiqueta,
                color: scheme.onPrimary,
              ),
              _DatoChip(
                icono: Icons.calendar_today_outlined,
                texto: 'Desde ${formatearFecha(perfil.fechaRegistro)}',
                color: scheme.onPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DatoChip extends StatelessWidget {
  const _DatoChip({
    required this.icono,
    required this.texto,
    required this.color,
  });

  final IconData icono;
  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icono, size: 14, color: color),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 220),
            child: Text(
              texto,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Estadisticas extends StatelessWidget {
  const _Estadisticas({required this.usuarios});

  final List<UsuarioAdmin> usuarios;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = usuarios.length;
    final admins = usuarios.where((u) => u.esAdministrador).length;
    final moderadores = usuarios.where((u) => u.esModerador).length;
    final suspendidos = usuarios.where((u) => !u.estaActivo).length;

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        _StatCard(
          icono: Icons.people_alt_outlined,
          valor: total,
          etiqueta: 'Usuarios',
          color: scheme.primary,
        ),
        _StatCard(
          icono: Icons.admin_panel_settings_outlined,
          valor: admins,
          etiqueta: 'Administradores',
          color: scheme.tertiary,
        ),
        _StatCard(
          icono: Icons.shield_outlined,
          valor: moderadores,
          etiqueta: 'Moderadores',
          color: scheme.secondary,
        ),
        _StatCard(
          icono: Icons.pause_circle_outline,
          valor: suspendidos,
          etiqueta: 'Suspendidos',
          color: scheme.error,
        ),
      ],
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icono,
    required this.valor,
    required this.etiqueta,
    required this.color,
  });

  final IconData icono;
  final int valor;
  final String etiqueta;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 154,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          Icon(icono, color: color),
          const SizedBox(width: 10),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$valor',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  color: color,
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(etiqueta, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ],
      ),
    );
  }
}

class _AvisoConfiguracion extends StatelessWidget {
  const _AvisoConfiguracion({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.warning_amber_outlined, color: scheme.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'No se pudo cargar la información',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: scheme.onErrorContainer,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Verifica que la migración de administración esté aplicada '
                    'en Supabase y vuelve a intentarlo.',
                    style: TextStyle(color: scheme.onErrorContainer),
                  ),
                  if (error is PostgrestException) ...[
                    const SizedBox(height: 6),
                    Text(
                      (error as PostgrestException).message,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: scheme.onErrorContainer,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ModuloAdmin {
  const _ModuloAdmin(this.nombre, this.icono, this.ruta);

  final String nombre;
  final IconData icono;
  final String ruta;
}

const _modulosAdmin = [
  _ModuloAdmin('Legal y normativa', Icons.gavel_outlined, Rutas.legal),
  _ModuloAdmin('Cultura y traductor', Icons.translate, Rutas.cultura),
  _ModuloAdmin('Alertas y reportes', Icons.warning_amber_outlined, Rutas.alertas),
  _ModuloAdmin('Precios y cobros', Icons.request_quote_outlined, Rutas.precios),
  _ModuloAdmin('Comunidad', Icons.groups_outlined, Rutas.comunidad),
  _ModuloAdmin('Orientación', Icons.help_outline, Rutas.orientacion),
  _ModuloAdmin(
    'Descargas offline',
    Icons.download_for_offline_outlined,
    Rutas.descargas,
  ),
  _ModuloAdmin('Emergencias SOS', Icons.sos_outlined, Rutas.sos),
  _ModuloAdmin('Configuración', Icons.settings_outlined, Rutas.configuracion),
];

/// Acceso directo a la gestión de contenido (lugares, normas, alertas y SOS).
class _TarjetaContenido extends StatelessWidget {
  const _TarjetaContenido();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.primaryContainer.withValues(alpha: 0.5),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(Rutas.adminContenido),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                child: const Icon(Icons.tune_outlined),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Gestión de contenido',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 2),
                    const Text(
                      'Crea, edita, deshabilita o elimina lugares, destinos, '
                      'normas, alertas oficiales y contactos del SOS.',
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_outlined),
            ],
          ),
        ),
      ),
    );
  }
}

class _AccesoModulos extends StatelessWidget {
  const _AccesoModulos();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final ancho = (constraints.maxWidth - 12) / 2;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _modulosAdmin
              .map(
                (m) => SizedBox(
                  width: ancho,
                  child: _ModuloCard(modulo: m),
                ),
              )
              .toList(),
        );
      },
    );
  }
}

class _ModuloCard extends StatelessWidget {
  const _ModuloCard({required this.modulo});

  final _ModuloAdmin modulo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () => context.push(modulo.ruta),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
          child: Row(
            children: [
              Icon(modulo.icono, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  modulo.nombre,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
              const Icon(Icons.chevron_right, size: 18),
            ],
          ),
        ),
      ),
    );
  }
}

class _NotaPermisos extends StatelessWidget {
  const _NotaPermisos({required this.perfil});

  final Perfil perfil;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: scheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Reglas de control',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ],
            ),
            const SizedBox(height: 10),
            const Text(
              '• El superadministrador puede crear administradores y '
              'moderadores, cambiar roles, suspender o eliminar cuentas.\n'
              '• Los administradores pueden crear moderadores y suspender '
              'cuentas de usuarios.\n'
              '• Los moderadores verifican y eliminan alertas, reportes y '
              'contactos SOS; solo pueden suspender o reactivar turistas.\n'
              '• La suspensión bloquea el acceso sin borrar el historial.\n'
              '• Siempre debe quedar al menos un superadministrador activo.',
            ),
            if (!perfil.esSuperAdmin) ...[
              const SizedBox(height: 10),
              Text(
                'Tu cuenta es administrador, pero no superadministrador: '
                'la gestión de administradores está restringida.',
                style: TextStyle(color: scheme.error),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: usuarios
// ─────────────────────────────────────────────────────────────

enum _AccionAdmin {
  hacerAdmin,
  hacerModerador,
  quitarRol,
  suspender,
  reactivar,
  eliminar,
}

class _UsuariosTab extends ConsumerStatefulWidget {
  const _UsuariosTab({
    required this.perfil,
    this.soloAdministradores = false,
  });

  final Perfil perfil;
  final bool soloAdministradores;

  @override
  ConsumerState<_UsuariosTab> createState() => _UsuariosTabState();
}

class _UsuariosTabState extends ConsumerState<_UsuariosTab> {
  final _busqueda = TextEditingController();
  final Set<String> _ocupados = {};
  String _filtro = 'todos';

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  bool _coincide(UsuarioAdmin u) {
    if (widget.soloAdministradores) return true;

    final q = normalizar(_busqueda.text.trim());
    if (q.isNotEmpty &&
        !normalizar('${u.nombre} ${u.email}').contains(q)) {
      return false;
    }

    return switch (_filtro) {
      'administradores' => u.esAdministrador,
      'moderadores' => u.esModerador,
      'turistas' => u.rol == 'turista',
      'residentes' => u.rol == 'residente',
      'suspendidos' => !u.estaActivo,
      _ => true,
    };
  }

  Future<void> _ejecutar(UsuarioAdmin u, _AccionAdmin accion) async {
    if (accion == _AccionAdmin.eliminar) {
      final ok = await _confirmar(
        context,
        titulo: 'Eliminar cuenta',
        mensaje:
            '¿Eliminar definitivamente la cuenta de ${u.nombre}?\n\n'
            'Si la cuenta tiene alertas, reportes o publicaciones asociadas, '
            'el sistema pedirá suspenderla en lugar de eliminarla.',
        accion: 'Eliminar',
      );
      if (!ok || !mounted) return;
    }

    if (accion == _AccionAdmin.suspender) {
      final ok = await _confirmar(
        context,
        titulo: 'Suspender cuenta',
        mensaje:
            '¿Suspender a ${u.nombre}? No podrá iniciar sesión ni usar la app '
            'hasta que la reactives.',
        accion: 'Suspender',
      );
      if (!ok || !mounted) return;
    }

    if (accion == _AccionAdmin.quitarRol) {
      final ok = await _confirmar(
        context,
        titulo: 'Quitar rol administrativo',
        mensaje:
            '¿Convertir a ${u.nombre} en turista? Perderá el acceso al panel '
            'de administración y a la moderación.',
        accion: 'Quitar rol',
      );
      if (!ok || !mounted) return;
    }

    if (accion == _AccionAdmin.hacerAdmin) {
      final ok = await _confirmar(
        context,
        titulo: 'Nombrar administrador',
        mensaje:
            '¿Dar acceso de administrador a ${u.nombre}? Podrá gestionar '
            'usuarios y moderadores desde este panel.',
        accion: 'Nombrar',
      );
      if (!ok || !mounted) return;
    }

    if (accion == _AccionAdmin.hacerModerador) {
      final ok = await _confirmar(
        context,
        titulo: 'Nombrar moderador',
        mensaje:
            '¿Dar permisos de moderador a ${u.nombre}? Podrá verificar y '
            'eliminar alertas, reportes y contactos SOS, y suspender '
            'cuentas de turistas.',
        accion: 'Nombrar',
      );
      if (!ok || !mounted) return;
    }

    if (!mounted) return;
    setState(() => _ocupados.add(u.id));

    try {
      final repo = ref.read(adminRepositoryProvider);
      switch (accion) {
        case _AccionAdmin.hacerAdmin:
          await repo.actualizarUsuario(id: u.id, rol: 'administrador');
        case _AccionAdmin.hacerModerador:
          await repo.actualizarUsuario(id: u.id, rol: 'moderador');
        case _AccionAdmin.quitarRol:
          await repo.actualizarUsuario(id: u.id, rol: 'turista');
        case _AccionAdmin.suspender:
          await repo.actualizarUsuario(id: u.id, estado: 'suspendido');
        case _AccionAdmin.reactivar:
          await repo.actualizarUsuario(id: u.id, estado: 'activo');
        case _AccionAdmin.eliminar:
          await repo.eliminarUsuario(u.id);
      }

      if (!mounted) return;
      ref.invalidate(usuariosAdminProvider);
      _mensaje(_mensajeAccion(accion));
    } catch (e) {
      if (mounted) _mensaje(_errorTexto(e));
    } finally {
      if (mounted) setState(() => _ocupados.remove(u.id));
    }
  }

  String _mensajeAccion(_AccionAdmin accion) => switch (accion) {
    _AccionAdmin.hacerAdmin => 'Ahora la cuenta es administrador.',
    _AccionAdmin.hacerModerador => 'Ahora la cuenta es moderador.',
    _AccionAdmin.quitarRol => 'Rol administrativo retirado.',
    _AccionAdmin.suspender => 'Cuenta suspendida.',
    _AccionAdmin.reactivar => 'Cuenta reactivada.',
    _AccionAdmin.eliminar => 'Cuenta eliminada.',
  };

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(usuariosAdminProvider);
    final filtrados = async.whenData((usuarios) {
      final base = widget.soloAdministradores
          ? usuarios.where((u) => u.esAdministrador).toList()
          : usuarios;
      return base.where(_coincide).toList();
    });

    return Column(
      children: [
        if (widget.soloAdministradores)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Icon(
                      Icons.admin_panel_settings_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(width: 12),
                    const Expanded(
                      child: Text(
                        'Los administradores tienen acceso al panel. Solo el '
                        'superadministrador puede crear o modificar '
                        'administradores.',
                      ),
                    ),
                  ],
                ),
              ),
            ),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: TextField(
              controller: _busqueda,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Buscar por nombre o correo',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _busqueda.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Limpiar búsqueda',
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _busqueda.clear();
                          setState(() {});
                        },
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 52,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 8,
              ),
              children: [
                _filtroChip('todos', 'Todos'),
                _filtroChip('administradores', 'Administradores'),
                _filtroChip('moderadores', 'Moderadores'),
                _filtroChip('turistas', 'Turistas'),
                _filtroChip('residentes', 'Residentes'),
                _filtroChip('suspendidos', 'Suspendidos'),
              ],
            ),
          ),
        ],
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 80),
            child: AsyncListView<UsuarioAdmin>(
              value: filtrados,
              emptyIcon: widget.soloAdministradores
                  ? Icons.admin_panel_settings_outlined
                  : Icons.people_outline,
              emptyMessage: widget.soloAdministradores
                  ? 'Sin administradores'
                  : 'No hay usuarios que coincidan',
              emptyDetail: widget.soloAdministradores
                  ? 'Crea el primero con el botón de la esquina.'
                  : 'Prueba con otro filtro o búsqueda.',
              onRefresh: () async {
                final _ = await ref.refresh(usuariosAdminProvider.future);
              },
              itemBuilder: (context, u) => _UsuarioTile(
                usuario: u,
                perfil: widget.perfil,
                ocupado: _ocupados.contains(u.id),
                onAccion: (accion) => _ejecutar(u, accion),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _filtroChip(String valor, String etiqueta) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(etiqueta),
        selected: _filtro == valor,
        onSelected: (_) => setState(() => _filtro = valor),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Fila de usuario
// ─────────────────────────────────────────────────────────────

class _UsuarioTile extends StatelessWidget {
  const _UsuarioTile({
    required this.usuario,
    required this.perfil,
    required this.ocupado,
    required this.onAccion,
  });

  final UsuarioAdmin usuario;
  final Perfil perfil;
  final bool ocupado;
  final Future<void> Function(_AccionAdmin accion) onAccion;

  bool get _esMiCuenta => usuario.id == perfil.id;

  List<_AccionAdmin> _acciones() {
    if (_esMiCuenta) return const [];

    final acciones = <_AccionAdmin>[];
    final soySuper = perfil.esSuperAdmin;

    if (soySuper && !usuario.esSuperAdmin) {
      if (!usuario.esAdministrador) {
        acciones.add(_AccionAdmin.hacerAdmin);
      }
      if (!usuario.esModerador) {
        acciones.add(_AccionAdmin.hacerModerador);
      }
      if (usuario.esAdministrador || usuario.esModerador) {
        acciones.add(_AccionAdmin.quitarRol);
      }
    }

    if (usuario.esAdministrador && !soySuper) {
      // Un administrador normal no puede tocar a otro administrador.
      return acciones;
    }

    acciones.add(
      usuario.estaActivo ? _AccionAdmin.suspender : _AccionAdmin.reactivar,
    );

    if (soySuper && !usuario.esSuperAdmin) {
      acciones.add(_AccionAdmin.eliminar);
    }

    return acciones;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final acciones = _acciones();

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: _colorRol(scheme).withValues(alpha: 0.18),
          foregroundColor: _colorRol(scheme),
          child: Text(usuario.inicial),
        ),
        title: Row(
          children: [
            Flexible(
              child: Text(
                usuario.nombre,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (usuario.esSuperAdmin) ...[
              const SizedBox(width: 6),
              Icon(Icons.verified, size: 17, color: scheme.tertiary),
            ],
            if (_esMiCuenta) ...[
              const SizedBox(width: 6),
              Text(
                '(tú)',
                style: Theme.of(context).textTheme.labelSmall,
              ),
            ],
          ],
        ),
        subtitle: Text(
          '${usuario.email}\n'
          '${usuario.rolEtiqueta}  ·  ${usuario.estadoEtiqueta}',
        ),
        isThreeLine: true,
        trailing: ocupado
            ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : acciones.isEmpty
                ? null
                : PopupMenuButton<_AccionAdmin>(
                    tooltip: 'Acciones de la cuenta',
                    onSelected: onAccion,
                    itemBuilder: (context) => acciones
                        .map(
                          (a) => PopupMenuItem(
                            value: a,
                            child: Row(
                              children: [
                                Icon(_iconoAccion(a), size: 20),
                                const SizedBox(width: 10),
                                Text(_etiquetaAccion(a)),
                              ],
                            ),
                          ),
                        )
                        .toList(),
                  ),
      ),
    );
  }

  Color _colorRol(ColorScheme scheme) {
    if (usuario.esSuperAdmin) return scheme.tertiary;
    if (usuario.esAdministrador) return scheme.primary;
    if (usuario.esModerador) return scheme.secondary;
    return scheme.outline;
  }

  IconData _iconoAccion(_AccionAdmin a) => switch (a) {
    _AccionAdmin.hacerAdmin => Icons.admin_panel_settings_outlined,
    _AccionAdmin.hacerModerador => Icons.shield_outlined,
    _AccionAdmin.quitarRol => Icons.person_off_outlined,
    _AccionAdmin.suspender => Icons.pause_circle_outline,
    _AccionAdmin.reactivar => Icons.play_circle_outline,
    _AccionAdmin.eliminar => Icons.delete_outline,
  };

  String _etiquetaAccion(_AccionAdmin a) => switch (a) {
    _AccionAdmin.hacerAdmin => 'Nombrar administrador',
    _AccionAdmin.hacerModerador => 'Nombrar moderador',
    _AccionAdmin.quitarRol => 'Quitar rol administrativo',
    _AccionAdmin.suspender => 'Suspender permisos',
    _AccionAdmin.reactivar => 'Reactivar cuenta',
    _AccionAdmin.eliminar => 'Eliminar cuenta',
  };
}

// ─────────────────────────────────────────────────────────────
// Utilidades
// ─────────────────────────────────────────────────────────────

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  String accion = 'Confirmar',
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return resultado ?? false;
}

String _errorTexto(Object error) {
  if (error is PostgrestException) return error.message;
  return 'No se pudo completar la operación. Revisa tu conexión.';
}

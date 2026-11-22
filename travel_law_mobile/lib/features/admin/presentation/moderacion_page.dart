import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../alertas/data/alertas_repository.dart';
import '../../auth/data/perfil_provider.dart';
import '../../comunidad/data/comunidad_repository.dart';
import '../../cultura/data/cultura_repository.dart';
import '../data/admin_repository.dart';
import '../data/contenido_repository.dart';
import '../data/moderacion_repository.dart';

/// Panel de moderación para moderadores y administradores activos.
///
/// Incluye las tareas que el rol moderador puede realizar:
///   * Verificar, rechazar y eliminar alertas de viajeros.
///   * Eliminar reportes de cobro abusivo.
///   * Eliminar contactos de emergencia del módulo SOS.
///   * Restringir, eliminar o restaurar publicaciones de la comunidad.
///   * Suspender o reactivar cuentas de turista (nunca eliminarlas).
class ModeracionPage extends ConsumerWidget {
  const ModeracionPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider);

    return perfil.when(
      skipLoadingOnReload: true,
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (_, _) => const _AccesoRestringido(
        detalle: 'No se pudo verificar tu rol. Revisa tu conexión.',
      ),
      data: (p) {
        final esStaff =
            p != null &&
            p.estado == 'activo' &&
            (p.esModerador || p.esAdministrador);
        if (!esStaff) return const _AccesoRestringido();
        return const _PanelModeracion();
      },
    );
  }
}

class _AccesoRestringido extends StatelessWidget {
  const _AccesoRestringido({this.detalle});

  final String? detalle;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Moderación')),
      body: EmptyState(
        icon: Icons.lock_outline,
        message: 'Acceso restringido',
        detail:
            detalle ??
            'Solo moderadores y administradores pueden entrar a este panel.',
      ),
    );
  }
}

class _PanelModeracion extends StatelessWidget {
  const _PanelModeracion();

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 6,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Moderación'),
          bottom: const TabBar(
            isScrollable: true,
            tabs: [
              Tab(icon: Icon(Icons.warning_amber_outlined), text: 'Alertas'),
              Tab(icon: Icon(Icons.request_quote_outlined), text: 'Reportes'),
              Tab(icon: Icon(Icons.sos_outlined), text: 'SOS'),
              Tab(icon: Icon(Icons.people_outline), text: 'Turistas'),
              Tab(icon: Icon(Icons.forum_outlined), text: 'Comunidad'),
               Tab(icon: Icon(Icons.translate), text: 'Expresiones'),
            ],
          ),
        ),
        body: const TabBarView(
          children: [
            _AlertasTab(),
            _ReportesTab(),
            _SosTab(),
            _TuristasTab(),
            _ComunidadTab(),
             _ExpresionesTab(),
           ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Compartidos
// ─────────────────────────────────────────────────────────────

class _ChipEstado extends StatelessWidget {
  const _ChipEstado({required this.texto, required this.color});

  final String texto;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        texto,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

Color _colorAlerta(String estado, ColorScheme scheme) => switch (estado) {
  'verificada' => scheme.primary,
  'pendiente_moderacion' => scheme.secondary,
  'rechazada' => scheme.error,
  _ => scheme.outline,
};

void _mensaje(BuildContext context, String texto) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(content: Text(texto), behavior: SnackBarBehavior.floating),
    );
}

Future<bool> _confirmar(
  BuildContext context, {
  required String titulo,
  required String mensaje,
  required String accion,
}) async {
  final resultado = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(titulo),
      content: Text(mensaje),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () => Navigator.pop(context, true),
          child: Text(accion),
        ),
      ],
    ),
  );
  return resultado ?? false;
}

// ─────────────────────────────────────────────────────────────
// Pestaña: alertas
// ─────────────────────────────────────────────────────────────

class _AlertasTab extends ConsumerStatefulWidget {
  const _AlertasTab();

  @override
  ConsumerState<_AlertasTab> createState() => _AlertasTabState();
}

class _AlertasTabState extends ConsumerState<_AlertasTab> {
  final Set<String> _ocupados = {};
  bool _soloPendientes = true;

  Future<void> _cambiarEstado(AlertaAdmin a, String estado) async {
    setState(() => _ocupados.add(a.id));
    try {
      await ref
          .read(contenidoRepositoryProvider)
          .actualizarAlerta(
            id: a.id,
            tipo: a.tipo,
            descripcion: a.descripcion,
            fechaEvento: a.fechaEvento ?? a.fechaCreacion,
            estado: estado,
          );
      ref.invalidate(alertasAdminProvider);
      ref.invalidate(alertasDestinoProvider(a.idDestino));
      ref.invalidate(misAlertasProvider);
      if (!mounted) return;
      _mensaje(
        context,
        estado == 'verificada'
            ? 'Alerta verificada y publicada en el destino.'
            : 'Alerta rechazada.',
      );
    } on Exception catch (e) {
      if (mounted) _mensaje(context, mensajeErrorContenido(e));
    } finally {
      if (mounted) setState(() => _ocupados.remove(a.id));
    }
  }

  Future<void> _eliminar(AlertaAdmin a) async {
    final ok = await _confirmar(
      context,
      titulo: 'Eliminar alerta',
      mensaje:
          '¿Eliminar la alerta de ${a.destino}? Sus confirmaciones se '
          'borrarán con ella.',
      accion: 'Eliminar',
    );
    if (!ok || !mounted) return;

    setState(() => _ocupados.add(a.id));
    try {
      await ref.read(contenidoRepositoryProvider).eliminarAlerta(a.id);
      ref.invalidate(alertasAdminProvider);
      ref.invalidate(alertasDestinoProvider(a.idDestino));
      ref.invalidate(misAlertasProvider);
      if (!mounted) return;
      _mensaje(context, 'Alerta eliminada.');
    } on Exception catch (e) {
      if (mounted) _mensaje(context, mensajeErrorContenido(e));
    } finally {
      if (mounted) setState(() => _ocupados.remove(a.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(alertasAdminProvider);
    final filtradas = async.whenData((lista) {
      final base = _soloPendientes
          ? lista.where((a) => a.estado == 'pendiente_moderacion').toList()
          : [...lista];
      base.sort((a, b) {
        final pa = a.estado == 'pendiente_moderacion' ? 0 : 1;
        final pb = b.estado == 'pendiente_moderacion' ? 0 : 1;
        if (pa != pb) return pa.compareTo(pb);
        return b.fechaCreacion.compareTo(a.fechaCreacion);
      });
      return base;
    });

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Row(
            children: [
              FilterChip(
                label: const Text('Pendientes'),
                selected: _soloPendientes,
                onSelected: (_) => setState(() => _soloPendientes = true),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('Todas'),
                selected: !_soloPendientes,
                onSelected: (_) => setState(() => _soloPendientes = false),
              ),
            ],
          ),
        ),
        Expanded(
          child: AsyncListView<AlertaAdmin>(
            value: filtradas,
            emptyIcon: Icons.task_alt_outlined,
            emptyMessage: _soloPendientes
                ? 'No hay alertas pendientes'
                : 'Sin alertas',
            emptyDetail: _soloPendientes
                ? 'Las alertas reportadas por los viajeros aparecerán aquí.'
                : 'No hay alertas registradas.',
            onRefresh: () async {
              ref.invalidate(alertasAdminProvider);
              await ref.read(alertasAdminProvider.future);
            },
            itemBuilder: (context, a) => _AlertaCard(
              alerta: a,
              ocupado: _ocupados.contains(a.id),
              onVerificar: () => _cambiarEstado(a, 'verificada'),
              onRechazar: () => _cambiarEstado(a, 'rechazada'),
              onEliminar: () => _eliminar(a),
            ),
          ),
        ),
      ],
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({
    required this.alerta,
    required this.ocupado,
    required this.onVerificar,
    required this.onRechazar,
    required this.onEliminar,
  });

  final AlertaAdmin alerta;
  final bool ocupado;
  final VoidCallback onVerificar;
  final VoidCallback onRechazar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final pendiente = alerta.estado == 'pendiente_moderacion';

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    '${alerta.tipoEtiqueta} · ${alerta.destino}',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                _ChipEstado(
                  texto: alerta.estadoEtiqueta,
                  color: _colorAlerta(alerta.estado, scheme),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alerta.descripcion),
            const SizedBox(height: 4),
            Text(
              'Por ${alerta.autor.isEmpty ? 'un viajero' : alerta.autor} · '
              '${fechaRelativa(alerta.fechaEvento ?? alerta.fechaCreacion)}',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: scheme.outline,
              ),
            ),
            const SizedBox(height: 12),
            if (ocupado)
              const Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: [
                  if (pendiente) ...[
                    FilledButton.icon(
                      onPressed: onVerificar,
                      icon: const Icon(Icons.check),
                      label: const Text('Verificar'),
                    ),
                    OutlinedButton.icon(
                      onPressed: onRechazar,
                      icon: const Icon(Icons.close),
                      label: const Text('Rechazar'),
                    ),
                  ],
                  TextButton.icon(
                    onPressed: onEliminar,
                    icon: Icon(Icons.delete_outline, color: scheme.error),
                    label: Text(
                      'Eliminar',
                      style: TextStyle(color: scheme.error),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: reportes de cobro
// ─────────────────────────────────────────────────────────────

class _ReportesTab extends ConsumerStatefulWidget {
  const _ReportesTab();

  @override
  ConsumerState<_ReportesTab> createState() => _ReportesTabState();
}

class _ReportesTabState extends ConsumerState<_ReportesTab> {
  final Set<String> _ocupados = {};

  Future<void> _eliminar(ReporteModeracion r) async {
    final ok = await _confirmar(
      context,
      titulo: 'Eliminar reporte',
      mensaje:
          '¿Eliminar el reporte de “${r.servicio}” en ${r.destino}? '
          'Esta acción no se puede deshacer.',
      accion: 'Eliminar',
    );
    if (!ok || !mounted) return;

    setState(() => _ocupados.add(r.id));
    try {
      await ref.read(moderacionRepositoryProvider).eliminarReporte(r.id);
      ref.invalidate(reportesModeracionProvider);
      if (!mounted) return;
      _mensaje(context, 'Reporte eliminado.');
    } on Exception catch (e) {
      if (mounted) _mensaje(context, 'No se pudo eliminar el reporte: $e');
    } finally {
      if (mounted) setState(() => _ocupados.remove(r.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(reportesModeracionProvider);
    final scheme = Theme.of(context).colorScheme;

    return AsyncListView<ReporteModeracion>(
      value: async,
      emptyIcon: Icons.request_quote_outlined,
      emptyMessage: 'Sin reportes de cobro',
      emptyDetail: 'Los reportes de cobros abusivos aparecerán aquí.',
      onRefresh: () async {
        ref.invalidate(reportesModeracionProvider);
        await ref.read(reportesModeracionProvider.future);
      },
      itemBuilder: (context, r) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: ListTile(
          leading: CircleAvatar(
            backgroundColor: scheme.surfaceContainerHighest.withValues(
              alpha: 0.7,
            ),
            child: const Icon(Icons.request_quote_outlined, size: 22),
          ),
          title: Text(
            '${r.servicio} · ${r.destino}',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          subtitle: Text(
            '${r.autor.isEmpty ? 'Un viajero' : r.autor} pagó '
            '${formatearPesos(r.precioPagado)}\n'
            '${formatearFecha(r.fecha)} · ${r.estadoEtiqueta}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          isThreeLine: true,
          trailing: _ocupados.contains(r.id)
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : IconButton(
                  tooltip: 'Eliminar reporte',
                  icon: Icon(Icons.delete_outline, color: scheme.error),
                  onPressed: () => _eliminar(r),
                ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: contactos SOS
// ─────────────────────────────────────────────────────────────

class _SosTab extends ConsumerStatefulWidget {
  const _SosTab();

  @override
  ConsumerState<_SosTab> createState() => _SosTabState();
}

class _SosTabState extends ConsumerState<_SosTab> {
  int? _idDestino;
  final Set<int> _ocupados = {};

  Future<void> _eliminar(ContactoAdmin c) async {
    final ok = await _confirmar(
      context,
      titulo: 'Eliminar contacto SOS',
      mensaje:
          '¿Eliminar “${c.entidad}” (${c.telefono}) de ${c.destino}? '
          'Dejará de aparecer en el módulo SOS.',
      accion: 'Eliminar',
    );
    if (!ok || !mounted) return;

    setState(() => _ocupados.add(c.id));
    try {
      await ref.read(contenidoRepositoryProvider).eliminarContacto(c.id);
      ref.invalidate(contactosAdminProvider);
      if (!mounted) return;
      _mensaje(context, 'Contacto SOS eliminado.');
    } on Exception catch (e) {
      if (mounted) _mensaje(context, mensajeErrorContenido(e));
    } finally {
      if (mounted) setState(() => _ocupados.remove(c.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(contactosAdminProvider);
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];
    final filtrados = async.whenData(
      (contactos) => contactos
          .where((c) => _idDestino == null || c.idDestino == _idDestino)
          .toList(),
    );
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        Card(
          margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
            child: DropdownButtonFormField<int>(
              initialValue: _idDestino,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Filtrar por destino',
                prefixIcon: Icon(Icons.location_city_outlined),
                border: InputBorder.none,
              ),
              isDense: true,
              items: [
                const DropdownMenuItem<int>(
                  value: null,
                  child: Text('Todos los destinos'),
                ),
                for (final d in destinos)
                  DropdownMenuItem(
                    value: d.id,
                    child: Text(d.etiqueta, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _idDestino = v),
            ),
          ),
        ),
        Expanded(
          child: AsyncListView<ContactoAdmin>(
            value: filtrados,
            emptyIcon: Icons.sos_outlined,
            emptyMessage: 'Sin contactos SOS',
            emptyDetail: 'Los contactos de emergencia aparecerán aquí.',
            onRefresh: () async {
              ref.invalidate(contactosAdminProvider);
              ref.invalidate(destinosAdminProvider);
              await ref.read(contactosAdminProvider.future);
            },
            itemBuilder: (context, c) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: scheme.errorContainer,
                  foregroundColor: scheme.onErrorContainer,
                  child: const Icon(Icons.sos_outlined, size: 22),
                ),
                title: Text(
                  '${c.entidad} · ${c.telefono}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${c.destino}'
                  '${c.direccion == null || c.direccion!.isEmpty ? '' : '\n${c.direccion}'}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: _ocupados.contains(c.id)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : IconButton(
                        tooltip: 'Eliminar contacto',
                        icon: Icon(Icons.delete_outline, color: scheme.error),
                        onPressed: () => _eliminar(c),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: turistas
// ─────────────────────────────────────────────────────────────

class _TuristasTab extends ConsumerStatefulWidget {
  const _TuristasTab();

  @override
  ConsumerState<_TuristasTab> createState() => _TuristasTabState();
}

class _TuristasTabState extends ConsumerState<_TuristasTab> {
  final _busqueda = TextEditingController();
  final Set<String> _ocupados = {};

  @override
  void dispose() {
    _busqueda.dispose();
    super.dispose();
  }

  Future<void> _cambiar(UsuarioAdmin u, bool activar) async {
    final ok = await _confirmar(
      context,
      titulo: activar ? 'Reactivar cuenta' : 'Suspender cuenta',
      mensaje: activar
          ? '¿Reactivar a ${u.nombre}? Podrá volver a usar la app.'
          : '¿Suspender a ${u.nombre}? No podrá iniciar sesión ni usar la app '
                'hasta que la reactives.',
      accion: activar ? 'Reactivar' : 'Suspender',
    );
    if (!ok || !mounted) return;

    setState(() => _ocupados.add(u.id));
    try {
      await ref
          .read(moderacionRepositoryProvider)
          .cambiarEstadoTurista(
            id: u.id,
            estado: activar ? 'activo' : 'suspendido',
          );
      ref.invalidate(turistasModeracionProvider);
      if (!mounted) return;
      _mensaje(context, activar ? 'Cuenta reactivada.' : 'Cuenta suspendida.');
    } on Exception catch (e) {
      if (mounted) _mensaje(context, 'No se pudo actualizar la cuenta: $e');
    } finally {
      if (mounted) setState(() => _ocupados.remove(u.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(turistasModeracionProvider);
    final q = normalizar(_busqueda.text.trim());
    final filtrados = async.whenData(
      (lista) => lista
          .where(
            (u) =>
                q.isEmpty ||
                normalizar('${u.nombre} ${u.email}').contains(q),
          )
          .toList(),
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: TextField(
            controller: _busqueda,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              hintText: 'Buscar turista por nombre o correo',
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
        Expanded(
          child: AsyncListView<UsuarioAdmin>(
            value: filtrados,
            emptyIcon: Icons.people_outline,
            emptyMessage: q.isEmpty ? 'Sin turistas' : 'Sin coincidencias',
            emptyDetail: q.isEmpty
                ? 'Las cuentas de turista aparecerán aquí.'
                : 'Prueba con otro nombre o correo.',
            onRefresh: () async {
              ref.invalidate(turistasModeracionProvider);
              await ref.read(turistasModeracionProvider.future);
            },
            itemBuilder: (context, u) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: CircleAvatar(child: Text(u.inicial)),
                title: Text(u.nombre),
                subtitle: Text(
                  '${u.email}\n${u.estadoEtiqueta}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                isThreeLine: true,
                trailing: _ocupados.contains(u.id)
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Switch(
                        value: u.estaActivo,
                        onChanged: (v) => _cambiar(u, v),
                      ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: comunidad de viajeros
// ─────────────────────────────────────────────────────────────

Color _colorPublicacion(String estado, ColorScheme scheme) => switch (estado) {
  'publicada' => scheme.primary,
  'oculta' => scheme.error,
  'pendiente_moderacion' => scheme.secondary,
  _ => scheme.outline,
};

class _ComunidadTab extends ConsumerStatefulWidget {
  const _ComunidadTab();

  @override
  ConsumerState<_ComunidadTab> createState() => _ComunidadTabState();
}

class _ComunidadTabState extends ConsumerState<_ComunidadTab> {
  final Set<String> _ocupados = {};

  Future<String?> _pedirMotivo(
    PublicacionModeracion p,
    String accion,
  ) async {
    var motivo = 'Normas de convivencia';
    final detalle = TextEditingController();
    final resultado = await showDialog<String>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            accion == 'restringir'
                ? 'Restringir publicación'
                : 'Eliminar publicación',
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  accion == 'restringir'
                      ? 'La publicación dejará de ser visible en la '
                            'comunidad. El autor recibirá una notificación '
                            'con el motivo.'
                      : 'La publicación y sus fotos se eliminarán de forma '
                            'permanente. El autor recibirá una notificación '
                            'con el motivo.',
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    ChoiceChip(
                      label: const Text('Normas de convivencia'),
                      selected: motivo == 'Normas de convivencia',
                      onSelected: (_) => setStateDialog(
                        () => motivo = 'Normas de convivencia',
                      ),
                    ),
                    ChoiceChip(
                      label: const Text('Uso indebido de la app'),
                      selected: motivo == 'Uso indebido de la app',
                      onSelected: (_) => setStateDialog(
                        () => motivo = 'Uso indebido de la app',
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: detalle,
                  maxLines: 2,
                  maxLength: 200,
                  decoration: const InputDecoration(
                    labelText: 'Detalle adicional (opcional)',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: accion == 'eliminar'
                  ? FilledButton.styleFrom(
                      backgroundColor: Theme.of(context).colorScheme.error,
                    )
                  : null,
              onPressed: () {
                final texto = [
                  motivo,
                  detalle.text.trim(),
                ].where((e) => e.isNotEmpty).join(': ');
                Navigator.pop(context, texto);
              },
              child: Text(accion == 'restringir' ? 'Restringir' : 'Eliminar'),
            ),
          ],
        ),
      ),
    );
    detalle.dispose();
    return resultado;
  }

  Future<void> _ejecutar(
    PublicacionModeracion p,
    String accion,
    String? motivo,
  ) async {
    setState(() => _ocupados.add(p.id));
    try {
      await ref
          .read(moderacionRepositoryProvider)
          .moderarPublicacion(id: p.id, accion: accion, motivo: motivo);
      ref.invalidate(publicacionesModeracionProvider);
      ref.invalidate(comunidadFeedProvider);
      if (!mounted) return;
      _mensaje(
        context,
        switch (accion) {
          'restringir' =>
            'Publicación restringida. El autor recibió una notificación.',
          'eliminar' =>
            'Publicación eliminada. El autor recibió una notificación.',
          _ => 'Publicación restaurada. El autor recibió una notificación.',
        },
      );
    } on Exception catch (e) {
      if (mounted) _mensaje(context, mensajeErrorContenido(e));
    } finally {
      if (mounted) setState(() => _ocupados.remove(p.id));
    }
  }

  Future<void> _restringir(PublicacionModeracion p) async {
    final motivo = await _pedirMotivo(p, 'restringir');
    if (motivo == null || !mounted) return;
    await _ejecutar(p, 'restringir', motivo);
  }

  Future<void> _eliminar(PublicacionModeracion p) async {
    final motivo = await _pedirMotivo(p, 'eliminar');
    if (motivo == null || !mounted) return;
    await _ejecutar(p, 'eliminar', motivo);
  }

  Future<void> _restaurar(PublicacionModeracion p) async {
    final ok = await _confirmar(
      context,
      titulo: 'Restaurar publicación',
      mensaje:
          '¿Restaurar la publicación de ${p.autor}? Volverá a ser visible '
          'en la comunidad y el autor recibirá una notificación.',
      accion: 'Restaurar',
    );
    if (!ok || !mounted) return;
    await _ejecutar(p, 'restaurar', null);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(publicacionesModeracionProvider);
    final scheme = Theme.of(context).colorScheme;

    return AsyncListView<PublicacionModeracion>(
      value: async,
      emptyIcon: Icons.forum_outlined,
      emptyMessage: 'Sin publicaciones',
      emptyDetail:
          'Las publicaciones de la comunidad aparecerán aquí para que '
          'puedas restringirlas o eliminarlas.',
      onRefresh: () async {
        ref.invalidate(publicacionesModeracionProvider);
        await ref.read(publicacionesModeracionProvider.future);
      },
      itemBuilder: (context, p) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    child: Text(
                      p.autor.isEmpty ? '?' : p.autor[0].toUpperCase(),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${p.autor} · ${p.destino}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  _ChipEstado(
                    texto: p.estadoEtiqueta,
                    color: _colorPublicacion(p.estado, scheme),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                p.descripcion,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 6),
              Text(
                '${fechaRelativa(p.fechaCreacion)} · '
                '${p.meGusta} me gusta · ${p.comentarios} comentarios · '
                '${p.evidencias} fotos',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.outline,
                ),
              ),
              if (p.motivoModeracion != null &&
                  p.motivoModeracion!.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  'Motivo: ${p.motivoModeracion}',
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: scheme.error,
                  ),
                ),
              ],
              const SizedBox(height: 10),
              if (_ocupados.contains(p.id))
                const Center(
                  child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    if (p.puedeRestringirse)
                      OutlinedButton.icon(
                        onPressed: () => _restringir(p),
                        icon: const Icon(Icons.visibility_off_outlined),
                        label: const Text('Restringir'),
                      ),
                    if (p.estaRestringida)
                      OutlinedButton.icon(
                        onPressed: () => _restaurar(p),
                        icon: const Icon(Icons.restore),
                        label: const Text('Restaurar'),
                      ),
                    TextButton.icon(
                      onPressed: () => _eliminar(p),
                      icon: Icon(Icons.delete_outline, color: scheme.error),
                      label: Text(
                        'Eliminar',
                        style: TextStyle(color: scheme.error),
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}


// ─────────────────────────────────────────────────────────────
// Expresiones culturales pendientes de aprobación
// ─────────────────────────────────────────────────────────────
class _ExpresionesTab extends ConsumerStatefulWidget {
  const _ExpresionesTab();

  @override
  ConsumerState<_ExpresionesTab> createState() => _ExpresionesTabState();
}

class _ExpresionesTabState extends ConsumerState<_ExpresionesTab> {
  final Set<int> _ocupados = {};

  Future<void> _moderar(Expresion e, String accion) async {
    setState(() => _ocupados.add(e.id));
    try {
      await moderarExpresion(ref, e.id, accion);
      ref.invalidate(expresionesPendientesProvider);
      ref.invalidate(expresionesProvider);
      if (!mounted) return;
      _mensaje(
        context,
        accion == 'aprobar'
            ? 'Expresión aprobada y visible para todos.'
            : 'Expresión rechazada.',
      );
    } on Exception catch (ex) {
      if (mounted) _mensaje(context, mensajeErrorContenido(ex));
    } finally {
      if (mounted) setState(() => _ocupados.remove(e.id));
    }
  }

  Future<void> _eliminar(Expresion e) async {
    final ok = await _confirmar(
      context,
      titulo: 'Eliminar expresión',
      mensaje: '¿Eliminar "${e.expresion}"? Esta acción no se puede deshacer.',
      accion: 'Eliminar',
    );
    if (!ok || !mounted) return;
    setState(() => _ocupados.add(e.id));
    try {
      await eliminarExpresion(ref, e.id);
      ref.invalidate(expresionesPendientesProvider);
      ref.invalidate(expresionesProvider);
      if (!mounted) return;
      _mensaje(context, 'Expresión eliminada.');
    } on Exception catch (ex) {
      if (mounted) _mensaje(context, mensajeErrorContenido(ex));
    } finally {
      if (mounted) setState(() => _ocupados.remove(e.id));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(expresionesPendientesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(
            'Expresiones propuestas por los viajeros pendientes de aprobación.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Expanded(
          child: AsyncListView<Expresion>(
            value: async,
            emptyIcon: Icons.task_alt_outlined,
            emptyMessage: 'No hay expresiones pendientes',
            emptyDetail:
                'Las expresiones propuestas por los viajeros aparecerán aquí.',
            onRefresh: () async {
              ref.invalidate(expresionesPendientesProvider);
              await ref.read(expresionesPendientesProvider.future);
            },
            itemBuilder: (context, e) => Card(
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.translate, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            e.expresion,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.bold),
                          ),
                        ),
                        _ChipEstado(
                          texto: 'Pendiente',
                          color: Theme.of(context).colorScheme.tertiary,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text('ES: ${e.significadoEs}'),
                    if (e.significadoEn != null &&
                        e.significadoEn!.trim().isNotEmpty)
                      Text('EN: ${e.significadoEn}'),
                    const SizedBox(height: 4),
                    Text(
                      'Por ${e.idUsuario ?? 'un viajero'}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.outline,
                          ),
                    ),
                    const SizedBox(height: 12),
                    if (_ocupados.contains(e.id))
                      const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          FilledButton.icon(
                            onPressed: () => _moderar(e, 'aprobar'),
                            icon: const Icon(Icons.check),
                            label: const Text('Aprobar'),
                          ),
                          OutlinedButton.icon(
                            onPressed: () => _moderar(e, 'rechazar'),
                            icon: const Icon(Icons.close),
                            label: const Text('Rechazar'),
                          ),
                          TextButton.icon(
                            onPressed: () => _eliminar(e),
                            icon: Icon(Icons.delete_outline,
                                color: Theme.of(context).colorScheme.error),
                            label: Text(
                              'Eliminar',
                              style: TextStyle(
                                  color: Theme.of(context).colorScheme.error),
                            ),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

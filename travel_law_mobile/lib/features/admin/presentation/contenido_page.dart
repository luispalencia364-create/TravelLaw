import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/rutas.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../data/contenido_repository.dart';
import 'widgets/gestion_dialogs.dart';

/// Apartado del panel de administración para gestionar el contenido de
/// TravelLaw: lugares, destinos, normas, alertas oficiales y contactos SOS.
/// El guard solo deja pasar a administradores activos.
class ContenidoPage extends ConsumerWidget {
  const ContenidoPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider);

    return perfil.when(
      skipLoadingOnReload: true,
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => const _AccesoBloqueado(
        detalle: 'No se pudo verificar tu rol. Revisa tu conexión.',
      ),
      data: (p) {
        if (p == null || !p.esAdministrador || p.estado != 'activo') {
          return const _AccesoBloqueado();
        }
        return _PanelContenido(perfil: p);
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Acceso restringido
// ─────────────────────────────────────────────────────────────

class _AccesoBloqueado extends StatelessWidget {
  const _AccesoBloqueado({this.detalle});

  final String? detalle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: const Text('Gestión de contenido')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.lock_outline, size: 64, color: scheme.error),
              const SizedBox(height: 12),
              Text(
                'Acceso restringido',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              const Text(
                'Este apartado es exclusivo de los administradores de TravelLaw.',
                textAlign: TextAlign.center,
              ),
              if (detalle != null) ...[
                const SizedBox(height: 8),
                Text(
                  detalle!,
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
              const SizedBox(height: 16),
              FilledButton.tonal(
                onPressed: () => context.go(Rutas.admin),
                child: const Text('Volver al panel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Panel con pestañas
// ─────────────────────────────────────────────────────────────

class _PanelContenido extends ConsumerStatefulWidget {
  const _PanelContenido({required this.perfil});

  final Perfil perfil;

  @override
  ConsumerState<_PanelContenido> createState() => _PanelContenidoState();
}

class _PanelContenidoState extends ConsumerState<_PanelContenido>
    with SingleTickerProviderStateMixin {
  late final TabController _controller = TabController(length: 5, vsync: this);

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
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

  Future<void> _crear() async {
    final bool ok;
    switch (_controller.index) {
      case 0:
        ok = await mostrarDialogoLugar(context);
        _despuesDeGuardar(ok, 'Lugar creado.');
      case 1:
        ok = await mostrarDialogoDestino(context);
        _despuesDeGuardar(ok, 'Destino creado.');
      case 2:
        ok = await mostrarDialogoNorma(context);
        _despuesDeGuardar(ok, 'Norma creada.');
      case 3:
        ok = await mostrarDialogoAlerta(context);
        _despuesDeGuardar(ok, 'Alerta oficial publicada.');
      default:
        ok = await mostrarDialogoContacto(context);
        _despuesDeGuardar(ok, 'Contacto SOS creado.');
    }
  }

  void _despuesDeGuardar(bool ok, String mensaje) {
    if (!ok) return;
    refrescarContenido(ref);
    _mensaje(mensaje);
  }

  @override
  Widget build(BuildContext context) {
    const etiquetas = [
      (Icons.place_outlined, 'Lugares'),
      (Icons.location_city_outlined, 'Destinos'),
      (Icons.gavel_outlined, 'Normas'),
      (Icons.warning_amber_outlined, 'Alertas'),
      (Icons.sos_outlined, 'Contactos SOS'),
    ];

    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestión de contenido'),
        bottom: TabBar(
          controller: _controller,
          isScrollable: true,
          tabs: [
            for (final (icono, texto) in etiquetas)
              Tab(icon: Icon(icono), text: texto),
          ],
        ),
      ),
      body: TabBarView(
        controller: _controller,
        children: [
          _LugaresTab(mensaje: _mensaje, confirmar: _confirmar),
          _DestinosTab(mensaje: _mensaje, confirmar: _confirmar),
          _NormasTab(mensaje: _mensaje, confirmar: _confirmar),
          _AlertasTab(mensaje: _mensaje, confirmar: _confirmar),
          _ContactosTab(mensaje: _mensaje, confirmar: _confirmar),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _crear,
        icon: const Icon(Icons.add),
        label: Text(_etiquetaFab),
      ),
    );
  }

  String get _etiquetaFab => switch (_controller.index) {
    0 => 'Nuevo lugar',
    1 => 'Nuevo destino',
    2 => 'Nueva norma',
    3 => 'Nueva alerta',
    _ => 'Nuevo contacto',
  };
}

// ─────────────────────────────────────────────────────────────
// Compartidos
// ─────────────────────────────────────────────────────────────

typedef _Mensaje = void Function(String texto);

typedef _Confirmar =
    Future<bool> Function(
      BuildContext context, {
      required String titulo,
      required String mensaje,
      required String accion,
    });

enum _Accion { editar, activar, desactivar, eliminar }

Color _colorLugar(bool activo, ColorScheme scheme) =>
    activo ? scheme.primary : scheme.outline;

Color _colorAlerta(String estado, ColorScheme scheme) => switch (estado) {
  'verificada' => scheme.primary,
  'pendiente_moderacion' => scheme.secondary,
  'rechazada' => scheme.error,
  _ => scheme.outline,
};

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

/// Fila de contenido con menú de acciones.
class _FilaContenido extends StatelessWidget {
  const _FilaContenido({
    required this.titulo,
    required this.detalle,
    required this.chip,
    required this.chipColor,
    required this.onAccion,
    this.etiquetaActivar = 'Activar',
    this.etiquetaDesactivar = 'Desactivar',
    this.ocultarAccionesEstado = false,
    this.ocupado = false,
    this.icono = Icons.inventory_2_outlined,
  });

  final String titulo;
  final Map<String, String> detalle;
  final String chip;
  final Color chipColor;
  final void Function(_Accion) onAccion;
  final bool ocupado;
  final bool ocultarAccionesEstado;
  final String etiquetaActivar;
  final String etiquetaDesactivar;
  final IconData icono;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        contentPadding: const EdgeInsets.fromLTRB(14, 10, 4, 10),
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          child: ocupado
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(icono, size: 22),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                titulo,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: 8),
            _ChipEstado(texto: chip, color: chipColor),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (detalle.isNotEmpty)
                Text(
                  detalle.entries.first.value,
                  style: const TextStyle(fontWeight: FontWeight.w500),
                ),
              if (detalle.length > 1)
                Text(
                  detalle.entries.elementAt(1).value,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
        isThreeLine: true,
        trailing: PopupMenuButton<_Accion>(
          onSelected: onAccion,
          itemBuilder: (context) => [
            const PopupMenuItem(
              value: _Accion.editar,
              child: ListTile(
                leading: Icon(Icons.edit_outlined),
                title: Text('Editar'),
                dense: true,
              ),
            ),
            if (!ocultarAccionesEstado) ...[
              PopupMenuItem(
                value: _Accion.activar,
                child: ListTile(
                  leading: const Icon(Icons.check_circle_outline),
                  title: Text(etiquetaActivar),
                  dense: true,
                ),
              ),
              PopupMenuItem(
                value: _Accion.desactivar,
                child: ListTile(
                  leading: const Icon(Icons.pause_circle_outline),
                  title: Text(etiquetaDesactivar),
                  dense: true,
                ),
              ),
            ],
            const PopupMenuDivider(),
            PopupMenuItem(
              value: _Accion.eliminar,
              child: ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('Eliminar', style: TextStyle(color: scheme.error)),
                dense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FiltroDestino extends StatelessWidget {
  const _FiltroDestino({
    required this.destinos,
    required this.valor,
    required this.onChanged,
  });

  final List<DestinoAdmin> destinos;
  final int? valor;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
        child: DropdownButtonFormField<int>(
          initialValue: valor,
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
          onChanged: onChanged,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: lugares
// ─────────────────────────────────────────────────────────────

class _LugaresTab extends ConsumerStatefulWidget {
  const _LugaresTab({required this.mensaje, required this.confirmar});

  final _Mensaje mensaje;
  final _Confirmar confirmar;

  @override
  ConsumerState<_LugaresTab> createState() => _LugaresTabState();
}

class _LugaresTabState extends ConsumerState<_LugaresTab> {
  int? _idDestino;
  final Set<int> _ocupados = {};

  String _detalle(LugarAdmin l) => '${l.categoria} · ${l.destino}';

  Future<void> _ejecutar(LugarAdmin l, _Accion a) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      switch (a) {
        case _Accion.editar:
          final ok = await mostrarDialogoLugar(context, lugar: l);
          if (!ok) return;
          widget.mensaje('Lugar actualizado.');
          refrescarContenido(ref);
          return;
        case _Accion.activar:
          await repo.actualizarLugar(
            id: l.id,
            idDestino: l.idDestino,
            idCategoria: l.idCategoria,
            nombre: l.nombre,
            horario: l.horario,
            activo: true,
          );
          widget.mensaje('Lugar activado de nuevo.');
        case _Accion.desactivar:
          await repo.actualizarLugar(
            id: l.id,
            idDestino: l.idDestino,
            idCategoria: l.idCategoria,
            nombre: l.nombre,
            horario: l.horario,
            activo: false,
          );
          widget.mensaje('Lugar deshabilitado: desaparece de la app.');
        case _Accion.eliminar:
          final ok = await widget.confirmar(
            context,
            titulo: 'Eliminar lugar',
            mensaje:
                '¿Eliminar “${l.nombre}” definitivamente? Si solo lo quieres '
                'ocultar de la app, usa “Desactivar” en el menú.',
            accion: 'Eliminar',
          );
          if (!ok || !mounted) return;
          await repo.eliminarLugar(l.id);
          widget.mensaje('Lugar eliminado.');
      }
      if (mounted) setState(() => _ocupados.remove(l.id));
      refrescarContenido(ref);
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(l.id));
      widget.mensaje(mensajeErrorContenido(e));
    }
  }

  void _conAccion(LugarAdmin l, _Accion a) {
    setState(() => _ocupados.add(l.id));
    _ejecutar(l, a);
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(lugaresAdminProvider);
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];
    final filtrados = async.whenData(
      (lugares) => lugares
          .where((l) => _idDestino == null || l.idDestino == _idDestino)
          .toList(),
    );
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _FiltroDestino(
          destinos: destinos,
          valor: _idDestino,
          onChanged: (v) => setState(() => _idDestino = v),
        ),
        Expanded(
          child: AsyncListView<LugarAdmin>(
            value: filtrados,
            emptyIcon: Icons.place_outlined,
            emptyMessage: 'Sin lugares',
            emptyDetail: 'Crea el primero con el botón “Nuevo lugar”.',
            onRefresh: () async {
              final _ = await ref.refresh(lugaresAdminProvider.future);
              final _ = await ref.refresh(destinosAdminProvider.future);
            },
            itemBuilder: (context, l) => _FilaContenido(
              icono: Icons.place_outlined,
              titulo: l.nombre,
              chip: l.activo ? 'Activo' : 'Deshabilitado',
              chipColor: _colorLugar(l.activo, scheme),
              ocupado: _ocupados.contains(l.id),
              onAccion: (a) => _conAccion(l, a),
              detalle: {
                'categoria': _detalle(l),
                'coordenadas':
                    '${l.posicion.$1}, ${l.posicion.$2} · ${l.horario ?? 'Sin horario'}',
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: destinos
// ─────────────────────────────────────────────────────────────

class _DestinosTab extends ConsumerStatefulWidget {
  const _DestinosTab({required this.mensaje, required this.confirmar});

  final _Mensaje mensaje;
  final _Confirmar confirmar;

  @override
  ConsumerState<_DestinosTab> createState() => _DestinosTabState();
}

class _DestinosTabState extends ConsumerState<_DestinosTab> {
  final Set<int> _ocupados = {};

  Future<void> _cambiarDestino(DestinoAdmin d, bool activo) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      await repo.actualizarDestino(
        id: d.id,
        nombre: d.nombre,
        municipio: d.municipio,
        activo: activo,
      );
      if (mounted) setState(() => _ocupados.remove(d.id));
      refrescarContenido(ref);
      widget.mensaje(
        activo ? 'Destino activado de nuevo en el mapa.' : 'Destino deshabilitado.',
      );
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(d.id));
      widget.mensaje(mensajeErrorContenido(e));
    }
  }

  Future<void> _ejecutar(DestinoAdmin d, _Accion a) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      switch (a) {
        case _Accion.editar:
          final ok = await mostrarDialogoDestino(context, destino: d);
          if (!ok) return;
          widget.mensaje('Destino actualizado.');
          refrescarContenido(ref);
          return;
        case _Accion.activar:
        case _Accion.desactivar:
          await _cambiarDestino(d, a == _Accion.activar);
          return;
        case _Accion.eliminar:
          final ok = await widget.confirmar(
            context,
            titulo: 'Eliminar destino',
            mensaje:
                '¿Eliminar “${d.nombre}” definitivamente? También se borrarán '
                'sus lugares, normas, alertas y contactos. Si solo quieres '
                'ocultarlo del mapa, usa el interruptor de la fila.',
            accion: 'Eliminar',
          );
          if (!ok || !mounted) return;
          if (mounted) setState(() => _ocupados.add(d.id));
          await repo.eliminarDestino(d.id);
          if (mounted) setState(() => _ocupados.remove(d.id));
          refrescarContenido(ref);
          widget.mensaje('Destino eliminado.');
      }
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(d.id));
      widget.mensaje(mensajeErrorContenido(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(destinosAdminProvider);
    final scheme = Theme.of(context).colorScheme;

    return AsyncListView<DestinoAdmin>(
      value: async,
      emptyIcon: Icons.location_city_outlined,
      emptyMessage: 'Sin destinos',
      emptyDetail: 'Crea el primero con el botón “Nuevo destino”.',
      onRefresh: () async {
        final _ = await ref.refresh(destinosAdminProvider.future);
      },
      itemBuilder: (context, d) => ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        leading: CircleAvatar(
          backgroundColor: scheme.surfaceContainerHighest.withValues(alpha: 0.7),
          child: _ocupados.contains(d.id)
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Icon(Icons.location_city_outlined, size: 22),
        ),
        title: Text(
          d.nombre,
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        subtitle: Text(
          '${d.municipio} · lat ${d.posicion.$1.toStringAsFixed(4)}, '
          'lng ${d.posicion.$2.toStringAsFixed(4)}',
        ),
        isThreeLine: true,
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Switch(
              value: d.activo,
              activeThumbColor: scheme.primary,
              onChanged: _ocupados.contains(d.id)
                  ? null
                  : (v) async {
                      setState(() => _ocupados.add(d.id));
                      await _cambiarDestino(d, v);
                    },
            ),
            PopupMenuButton<_Accion>(
              onSelected: (a) => _ejecutar(d, a),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: _Accion.editar,
                  child: ListTile(
                    leading: Icon(Icons.edit_outlined),
                    title: Text('Editar'),
                    dense: true,
                  ),
                ),
                const PopupMenuDivider(),
                PopupMenuItem(
                  value: _Accion.eliminar,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline, color: scheme.error),
                    title: Text('Eliminar', style: TextStyle(color: scheme.error)),
                    dense: true,
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
// Pestaña: normas
// ─────────────────────────────────────────────────────────────

class _NormasTab extends ConsumerStatefulWidget {
  const _NormasTab({required this.mensaje, required this.confirmar});

  final _Mensaje mensaje;
  final _Confirmar confirmar;

  @override
  ConsumerState<_NormasTab> createState() => _NormasTabState();
}

class _NormasTabState extends ConsumerState<_NormasTab> {
  int? _idDestino;
  final Set<int> _ocupados = {};

  Future<void> _ejecutar(NormaAdmin n, _Accion a) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      switch (a) {
        case _Accion.editar:
          final ok = await mostrarDialogoNorma(context, norma: n);
          if (!ok) return;
          widget.mensaje('Norma actualizada.');
          refrescarContenido(ref);
          return;
        case _Accion.activar:
          await repo.cambiarVigenciaNorma(id: n.id, vigente: true);
          widget.mensaje('Norma marcada como vigente.');
        case _Accion.desactivar:
          await repo.cambiarVigenciaNorma(id: n.id, vigente: false);
          widget.mensaje('Norma descontinuada: ya no se muestra en Legal.');
        case _Accion.eliminar:
          final ok = await widget.confirmar(
            context,
            titulo: 'Eliminar norma',
            mensaje:
                '¿Eliminar “${n.tituloEs}” definitivamente? Si solo quieres '
                'que deje de mostrarse, usa “Desactivar” para descontinuarla.',
            accion: 'Eliminar',
          );
          if (!ok || !mounted) return;
          await repo.eliminarNorma(n.id);
          widget.mensaje('Norma eliminada.');
      }
      if (mounted) setState(() => _ocupados.remove(n.id));
      refrescarContenido(ref);
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(n.id));
      widget.mensaje(mensajeErrorContenido(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(normasAdminProvider);
    final destinos =
        ref.watch(destinosAdminProvider).value ?? const <DestinoAdmin>[];
    final filtrados = async.whenData(
      (normas) => normas
          .where((n) => _idDestino == null || n.idDestino == _idDestino)
          .toList(),
    );
    final scheme = Theme.of(context).colorScheme;

    return Column(
      children: [
        _FiltroDestino(
          destinos: destinos,
          valor: _idDestino,
          onChanged: (v) => setState(() => _idDestino = v),
        ),
        Expanded(
          child: AsyncListView<NormaAdmin>(
            value: filtrados,
            emptyIcon: Icons.gavel_outlined,
            emptyMessage: 'Sin normas',
            emptyDetail: 'Crea la primera con el botón “Nueva norma”.',
            onRefresh: () async {
              final _ = await ref.refresh(normasAdminProvider.future);
              final _ = await ref.refresh(destinosAdminProvider.future);
            },
            itemBuilder: (context, n) => _FilaContenido(
              icono: Icons.gavel_outlined,
              titulo: n.tituloEs,
              chip: n.vigente ? 'Vigente' : 'Descontinuada',
              chipColor: _colorLugar(n.vigente, scheme),
              ocupado: _ocupados.contains(n.id),
              etiquetaActivar: 'Marcar vigente',
              etiquetaDesactivar: 'Descontinuar',
              onAccion: (a) async {
                setState(() => _ocupados.add(n.id));
                await _ejecutar(n, a);
              },
              detalle: {
                'tipo': '${n.tipoEtiqueta} · ${n.destino}',
                'contenido':
                    '${n.contenidoEs} (actualizada ${formatearFecha(n.fechaActualizacion)})',
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: alertas
// ─────────────────────────────────────────────────────────────

class _AlertasTab extends ConsumerStatefulWidget {
  const _AlertasTab({required this.mensaje, required this.confirmar});

  final _Mensaje mensaje;
  final _Confirmar confirmar;

  @override
  ConsumerState<_AlertasTab> createState() => _AlertasTabState();
}

class _AlertasTabState extends ConsumerState<_AlertasTab> {
  final Set<String> _ocupados = {};

  Future<void> _ejecutar(AlertaAdmin al, _Accion a) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      switch (a) {
        case _Accion.editar:
          final ok = await mostrarDialogoAlerta(context, alerta: al);
          if (!ok) return;
          widget.mensaje('Alerta actualizada.');
          refrescarContenido(ref);
          return;
        case _Accion.activar:
          await repo.actualizarAlerta(
            id: al.id,
            tipo: al.tipo,
            descripcion: al.descripcion,
            fechaEvento: al.fechaEvento ?? DateTime.now(),
            estado: 'verificada',
          );
          widget.mensaje('Alerta verificada: ya está visible en la app.');
        case _Accion.desactivar:
          await repo.actualizarAlerta(
            id: al.id,
            tipo: al.tipo,
            descripcion: al.descripcion,
            fechaEvento: al.fechaEvento ?? DateTime.now(),
            estado: 'vencida',
          );
          widget.mensaje('Alerta marcada como vencida.');
        case _Accion.eliminar:
          final ok = await widget.confirmar(
            context,
            titulo: 'Eliminar alerta',
            mensaje:
                '¿Eliminar la alerta de ${al.destino}? Sus confirmaciones '
                'se borrarán con ella.',
            accion: 'Eliminar',
          );
          if (!ok || !mounted) return;
          await repo.eliminarAlerta(al.id);
          widget.mensaje('Alerta eliminada.');
      }
      if (mounted) setState(() => _ocupados.remove(al.id));
      refrescarContenido(ref);
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(al.id));
      widget.mensaje(mensajeErrorContenido(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(alertasAdminProvider);
    final scheme = Theme.of(context).colorScheme;

    return AsyncListView<AlertaAdmin>(
      value: async,
      emptyIcon: Icons.warning_amber_outlined,
      emptyMessage: 'Sin alertas',
      emptyDetail: 'Crea una con el botón “Nueva alerta”.',
      onRefresh: () async {
        final _ = await ref.refresh(alertasAdminProvider.future);
      },
      itemBuilder: (context, al) => _FilaContenido(
        icono: Icons.warning_amber_outlined,
        titulo: '${AlertaAdmin.tipos[al.tipo] ?? al.tipo} · ${al.destino}',
        chip: al.estadoEtiqueta,
        chipColor: _colorAlerta(al.estado, scheme),
        ocupado: _ocupados.contains(al.id),
        etiquetaActivar: 'Verificar',
        etiquetaDesactivar: 'Marcar vencida',
        onAccion: (a) async {
          setState(() => _ocupados.add(al.id));
          await _ejecutar(al, a);
        },
        detalle: {
          'descripcion': al.descripcion,
          'meta':
              'Por ${al.autor} · evento ${formatearFecha(al.fechaEvento)}',
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Pestaña: contactos SOS
// ─────────────────────────────────────────────────────────────

class _ContactosTab extends ConsumerStatefulWidget {
  const _ContactosTab({required this.mensaje, required this.confirmar});

  final _Mensaje mensaje;
  final _Confirmar confirmar;

  @override
  ConsumerState<_ContactosTab> createState() => _ContactosTabState();
}

class _ContactosTabState extends ConsumerState<_ContactosTab> {
  int? _idDestino;
  final Set<int> _ocupados = {};

  Future<void> _ejecutar(ContactoAdmin c, _Accion a) async {
    final repo = ref.read(contenidoRepositoryProvider);
    try {
      switch (a) {
        case _Accion.editar:
          final ok = await mostrarDialogoContacto(context, contacto: c);
          if (!ok) return;
          widget.mensaje('Contacto SOS actualizado.');
          refrescarContenido(ref);
          return;
        case _Accion.activar:
        case _Accion.desactivar:
          return;
        case _Accion.eliminar:
          final ok = await widget.confirmar(
            context,
            titulo: 'Eliminar contacto',
            mensaje:
                '¿Eliminar “${c.entidad}” de la lista de emergencias de '
                '${c.destino}? Dejará de aparecer en el módulo SOS.',
            accion: 'Eliminar',
          );
          if (!ok || !mounted) return;
          await repo.eliminarContacto(c.id);
          widget.mensaje('Contacto SOS eliminado.');
      }
      if (mounted) setState(() => _ocupados.remove(c.id));
      refrescarContenido(ref);
    } on Exception catch (e) {
      if (mounted) setState(() => _ocupados.remove(c.id));
      widget.mensaje(mensajeErrorContenido(e));
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
        _FiltroDestino(
          destinos: destinos,
          valor: _idDestino,
          onChanged: (v) => setState(() => _idDestino = v),
        ),
        Expanded(
          child: AsyncListView<ContactoAdmin>(
            value: filtrados,
            emptyIcon: Icons.sos_outlined,
            emptyMessage: 'Sin contactos SOS',
            emptyDetail: 'Agrega el primero con el botón “Nuevo contacto”.',
            onRefresh: () async {
              final _ = await ref.refresh(contactosAdminProvider.future);
              final _ = await ref.refresh(destinosAdminProvider.future);
            },
            itemBuilder: (context, c) => _FilaContenido(
              icono: Icons.sos_outlined,
              titulo: c.entidad,
              chip: 'SOS',
              chipColor: scheme.error,
              ocupado: _ocupados.contains(c.id),
              ocultarAccionesEstado: true,
              onAccion: (a) async {
                setState(() => _ocupados.add(c.id));
                await _ejecutar(c, a);
              },
              detalle: {
                'telefono':
                    '${c.telefono} · ${c.destino}',
                'meta':
                    '${c.direccion ?? 'Sin dirección'}${c.fuente == null || c.fuente!.isEmpty ? '' : ' · Fuente: ${c.fuente}'}',
              },
            ),
          ),
        ),
      ],
    );
  }
}

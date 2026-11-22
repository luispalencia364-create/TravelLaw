import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/rutas.dart';
import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../data/notificaciones_repository.dart';

/// Bandeja de avisos del viajero: alertas de su destino y actividad de la
/// comunidad de viajeros.
class NotificacionesPage extends ConsumerWidget {
  const NotificacionesPage({super.key});

  Future<void> _marcarTodas(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(notificacionesRepositoryProvider).marcarTodasLeidas();
    } catch (e) {
      debugPrint('No se pudieron marcar las notificaciones: $e');
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudieron marcar las notificaciones.'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(notificacionesProvider);
    final noLeidas = ref.watch(notificacionesNoLeidasProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          if (noLeidas > 0)
            TextButton.icon(
              onPressed: () => _marcarTodas(context, ref),
              icon: const Icon(Icons.done_all),
              label: const Text('Marcar leídas'),
            ),
        ],
      ),
      body: async.when(
        skipLoadingOnReload: true,
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(notificacionesProvider);
            try {
              await ref.read(notificacionesProvider.future);
            } catch (_) {
              // El mensaje de error ya lo muestra la pantalla.
            }
          },
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            children: const [
              SizedBox(
                height: 420,
                child: EmptyState(
                  icon: Icons.cloud_off_outlined,
                  message: 'No se pudieron cargar las notificaciones',
                  detail:
                      'Revisa tu conexión y desliza hacia abajo para '
                      'reintentar.',
                ),
              ),
            ],
          ),
        ),
        data: (lista) => RefreshIndicator(
          onRefresh: () async {
            ref.invalidate(notificacionesProvider);
            try {
              await ref.read(notificacionesProvider.future);
            } catch (_) {
              // Se conserva la lista anterior si la recarga falla.
            }
          },
          child: lista.isEmpty
              ? ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  children: const [
                    SizedBox(
                      height: 420,
                      child: EmptyState(
                        icon: Icons.notifications_none,
                        message: 'Sin notificaciones',
                        detail:
                            'Aquí verás las alertas de tu destino y las '
                            'novedades de la comunidad de viajeros.',
                      ),
                    ),
                  ],
                )
              : ListView.builder(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
                  itemCount: lista.length,
                  itemBuilder: (context, i) =>
                      _NotificacionCard(notificacion: lista[i]),
                ),
        ),
      ),
    );
  }
}

class _NotificacionCard extends ConsumerWidget {
  const _NotificacionCard({required this.notificacion});

  final Notificacion notificacion;

  IconData get _icono => switch (notificacion.tipo) {
    'alerta_nueva' || 'alerta_verificada' => Icons.warning_amber_rounded,
    'comunidad_me_gusta' => Icons.favorite_outline,
    'comunidad_comentario' => Icons.chat_bubble_outline,
    'comunidad_publicacion_eliminada' => Icons.delete_outline,
    'comunidad_publicacion_restringida' => Icons.visibility_off_outlined,
    'comunidad_publicacion_restaurada' => Icons.restore,
    'cultura_sugerencia' => Icons.translate,
    'cultura_aprobada' => Icons.check_circle_outline,
    'cultura_rechazada' => Icons.cancel_outlined,
    _ => Icons.notifications_outlined,
  };

  Color _color(ColorScheme scheme) {
    if (notificacion.esDeAlerta) return Colors.amber.shade800;
    if (notificacion.tipo == 'comunidad_publicacion_eliminada' ||
        notificacion.tipo == 'comunidad_publicacion_restringida') {
      return scheme.error;
    }
    return scheme.primary;
  }

  Future<void> _abrir(BuildContext context, WidgetRef ref) async {
    if (!notificacion.leida) {
      try {
        await ref
            .read(notificacionesRepositoryProvider)
            .marcarLeida(notificacion.id);
      } catch (e) {
        debugPrint('No se pudo marcar la notificación como leída: $e');
      }
    }

    final idDestino = notificacion.idDestino;
    if (idDestino != null) {
      ref.read(destinoActivoProvider.notifier).seleccionar(idDestino);
    }

    if (!context.mounted) return;
    if (notificacion.esDeAlerta) {
      context.push(Rutas.alertas);
    } else if (notificacion.esDeComunidad) {
      context.push(Rutas.comunidad);
    } else if (notificacion.esDeCultura) {
      if (notificacion.tipo == 'cultura_sugerencia') {
        context.push(Rutas.moderacion);
      } else {
        context.push(Rutas.cultura);
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final noLeida = !notificacion.leida;
    final color = _color(scheme);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: noLeida
          ? scheme.primaryContainer.withValues(alpha: 0.22)
          : null,
      child: ListTile(
        onTap: () => _abrir(context, ref),
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          foregroundColor: color,
          child: Icon(_icono, size: 20),
        ),
        title: Row(
          children: [
            Expanded(
              child: Text(
                notificacion.titulo,
                style: TextStyle(
                  fontWeight: noLeida ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
            if (noLeida)
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
              ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(notificacion.mensaje),
              const SizedBox(height: 4),
              Text(
                fechaRelativa(notificacion.fecha),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
              ),
            ],
          ),
        ),
        isThreeLine: true,
      ),
    );
  }
}

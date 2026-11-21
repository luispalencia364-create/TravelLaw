import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class AlertaItem {
  const AlertaItem({
    required this.id,
    required this.tipo,
    required this.descripcion,
    required this.estado,
    this.fechaEvento,
  });

  final String id;
  final String tipo;
  final String descripcion;
  final String estado;
  final DateTime? fechaEvento;

  factory AlertaItem.fromMap(Map<String, dynamic> m) => AlertaItem(
    id: m['id_alerta'] as String,
    tipo: (m['tipo'] as String?) ?? 'otro',
    descripcion: m['descripcion'] as String,
    estado: (m['estado'] as String?) ?? 'pendiente_moderacion',
    fechaEvento: parseFecha(m['fecha_evento']),
  );
}

const _columnas = 'id_alerta, tipo, descripcion, estado, fecha_evento';

/// Días hacia atrás que se muestran en el módulo de alertas (0 = todo).
class DiasAlertasNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void cambiar(int dias) => state = dias;
}

final diasAlertasProvider = NotifierProvider<DiasAlertasNotifier, int>(
  DiasAlertasNotifier.new,
);

/// Alertas vigentes del destino. Solo se muestran las verificadas: las
/// pendientes quedan ocultas hasta que el staff las active.
final alertasDestinoProvider = FutureProvider.autoDispose
    .family<List<AlertaItem>, int>((ref, idDestino) async {
      final dias = ref.watch(diasAlertasProvider);
      final base = ref
          .watch(supabaseProvider)
          .from('alerta')
          .select(_columnas)
          .eq('id_destino', idDestino)
          .eq('estado', 'verificada');
      final filtrada = dias > 0
          ? base.gte(
              'fecha_evento',
              DateTime.now()
                  .subtract(Duration(days: dias))
                  .toUtc()
                  .toIso8601String(),
            )
          : base;
      final data = await filtrada.order('fecha_evento', ascending: false);
      return data.map(AlertaItem.fromMap).toList();
    });

/// Alertas creadas por el usuario (van a estado 'pendiente_moderacion' automáticamente).
final usuarioAlertasProvider = FutureProvider.autoDispose
    .family<List<AlertaItem>, String?>((ref, uid) async {
      final client = ref.watch(supabaseProvider);
      if (uid == null) return const <AlertaItem>[];
      final dias = ref.watch(diasAlertasProvider);
      final base = client.from('alerta').select(_columnas).eq('id_usuario', uid);
      final filtrada = dias > 0
          ? base.gte(
              'fecha_evento',
              DateTime.now()
                  .subtract(Duration(days: dias))
                  .toUtc()
                  .toIso8601String(),
            )
          : base;
      final data = await filtrada.order('fecha_creacion', ascending: false);
      return data.map(AlertaItem.fromMap).toList();
    });

/// Alertas creadas por el usuario autenticado actual.
final misAlertasProvider = FutureProvider.autoDispose<List<AlertaItem>>((ref) {
  final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
  return ref.watch(usuarioAlertasProvider(uid).future);
});

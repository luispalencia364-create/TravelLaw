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

/// Alertas vigentes del destino (últimos 30 días). Solo se muestran las
/// verificadas: las pendientes quedan ocultas hasta que el staff las active.
final alertasDestinoProvider = FutureProvider.autoDispose
    .family<List<AlertaItem>, int>((ref, idDestino) async {
      final desde = DateTime.now().subtract(const Duration(days: 30));
      final data = await ref
          .watch(supabaseProvider)
          .from('alerta')
          .select(_columnas)
          .eq('id_destino', idDestino)
          .eq('estado', 'verificada')
          .gte('fecha_evento', desde.toUtc().toIso8601String())
          .order('fecha_evento', ascending: false);
      return data.map(AlertaItem.fromMap).toList();
    });

/// Alertas creadas por el usuario (van a estado 'pendiente_moderacion' automáticamente).
final usuarioAlertasProvider = FutureProvider.autoDispose
    .family<List<AlertaItem>, String?>((ref, uid) async {
      final client = ref.watch(supabaseProvider);
      if (uid == null) return const <AlertaItem>[];
      final data = await client
          .from('alerta')
          .select(_columnas)
          .eq('id_usuario', uid)
          .order('fecha_creacion', ascending: false);
      return data.map(AlertaItem.fromMap).toList();
    });

/// Alertas creadas por el usuario autenticado actual.
final misAlertasProvider = FutureProvider.autoDispose<List<AlertaItem>>((ref) {
  final uid = ref.watch(supabaseProvider).auth.currentUser?.id;
  return ref.watch(usuarioAlertasProvider(uid).future);
});

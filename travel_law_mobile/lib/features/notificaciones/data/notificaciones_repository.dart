import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

/// Aviso dirigido a un usuario: alertas de su zona y novedades de la
/// comunidad de viajeros.
class Notificacion {
  const Notificacion({
    required this.id,
    required this.tipo,
    required this.titulo,
    required this.mensaje,
    required this.leida,
    this.fecha,
    this.idDestino,
    this.idAlerta,
    this.idPublicacion,
  });

  final String id;
  final String tipo;
  final String titulo;
  final String mensaje;
  final bool leida;
  final DateTime? fecha;
  final int? idDestino;
  final String? idAlerta;
  final String? idPublicacion;

  factory Notificacion.fromMap(Map<String, dynamic> m) => Notificacion(
    id: m['id_notificacion'] as String,
    tipo: (m['tipo'] as String?) ?? 'general',
    titulo: (m['titulo'] as String?) ?? 'Notificación',
    mensaje: (m['mensaje'] as String?) ?? '',
    leida: (m['leida'] as bool?) ?? false,
    fecha: parseFecha(m['fecha']),
    idDestino: (m['id_destino'] as num?)?.toInt(),
    idAlerta: m['id_alerta'] as String?,
    idPublicacion: m['id_publicacion'] as String?,
  );

  bool get esDeAlerta => tipo.startsWith('alerta_');
  bool get esDeComunidad => tipo.startsWith('comunidad_');
}

class NotificacionesRepository {
  NotificacionesRepository(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Stream en tiempo real de las últimas 100 notificaciones del usuario.
  /// Si Realtime no está habilitado, al menos entrega la carga inicial.
  Stream<List<Notificacion>> observar() {
    final uid = _uid;
    if (uid == null) return Stream.value(const <Notificacion>[]);
    return _client
        .from('notificacion')
        .stream(primaryKey: ['id_notificacion'])
        .eq('id_usuario', uid)
        .order('fecha', ascending: false)
        .limit(100)
        .map((filas) => filas.map(Notificacion.fromMap).toList());
  }

  Future<void> marcarLeida(String id) async {
    await _client
        .from('notificacion')
        .update({'leida': true})
        .eq('id_notificacion', id);
  }

  Future<void> marcarTodasLeidas() async {
    final uid = _uid;
    if (uid == null) return;
    await _client
        .from('notificacion')
        .update({'leida': true})
        .eq('id_usuario', uid)
        .eq('leida', false);
  }

  Future<void> eliminar(String id) async {
    await _client.from('notificacion').delete().eq('id_notificacion', id);
  }
}

final notificacionesRepositoryProvider = Provider<NotificacionesRepository>(
  (ref) => NotificacionesRepository(ref.watch(supabaseProvider)),
);

/// Lista de notificaciones con actualización en tiempo real.
final notificacionesProvider =
    StreamProvider.autoDispose<List<Notificacion>>((ref) {
      final client = ref.watch(supabaseProvider);
      // Al cambiar de sesión se vuelve a suscribir con el nuevo usuario.
      ref.watch(authStateProvider);
      if (client.auth.currentUser?.id == null) {
        return Stream.value(const <Notificacion>[]);
      }
      return ref.watch(notificacionesRepositoryProvider).observar();
    });

/// Cantidad de avisos sin leer (para el badge de la campana y el menú).
final notificacionesNoLeidasProvider = Provider.autoDispose<int>((ref) {
  final lista =
      ref.watch(notificacionesProvider).asData?.value ??
      const <Notificacion>[];
  return lista.where((n) => !n.leida).length;
});

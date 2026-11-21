import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import 'admin_repository.dart';

/// Reporte de cobro visible para el equipo de moderación.
class ReporteModeracion {
  const ReporteModeracion({
    required this.id,
    required this.servicio,
    required this.precioPagado,
    required this.estado,
    required this.destino,
    required this.autor,
    this.fecha,
  });

  final String id;
  final String servicio;
  final double precioPagado;
  final String estado;
  final String destino;
  final String autor;
  final DateTime? fecha;

  factory ReporteModeracion.fromMap(Map<String, dynamic> m) {
    final destino = m['destino'];
    final usuario = m['usuario'];
    return ReporteModeracion(
      id: m['id_reporte'] as String,
      servicio: (m['servicio'] as String?) ?? '',
      precioPagado: (m['precio_pagado'] as num?)?.toDouble() ?? 0,
      estado: (m['estado'] as String?) ?? 'pendiente_revision',
      destino: destino is Map ? (destino['nombre'] as String? ?? '') : '',
      autor: usuario is Map ? (usuario['nombre'] as String? ?? '') : '',
      fecha: parseFecha(m['fecha']),
    );
  }

  String get estadoEtiqueta => switch (estado) {
    'pendiente_revision' => 'Pendiente',
    'revisado' => 'Revisado',
    'rechazado' => 'Rechazado',
    _ => capitalizar(estado),
  };
}

/// Publicación de la comunidad vista desde el panel de moderación.
class PublicacionModeracion {
  const PublicacionModeracion({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.autor,
    required this.descripcion,
    required this.estado,
    required this.fechaCreacion,
    this.motivoModeracion,
    this.fechaModeracion,
    this.meGusta = 0,
    this.comentarios = 0,
    this.evidencias = 0,
  });

  final String id;
  final int idDestino;
  final String destino;
  final String autor;
  final String descripcion;
  final String estado;
  final String? motivoModeracion;
  final DateTime fechaCreacion;
  final DateTime? fechaModeracion;
  final int meGusta;
  final int comentarios;
  final int evidencias;

  factory PublicacionModeracion.fromMap(Map<String, dynamic> m) {
    return PublicacionModeracion(
      id: m['id_publicacion'] as String,
      idDestino: m['id_destino'] as int,
      destino: (m['destino'] as String?) ?? '',
      autor: (m['autor'] as String?) ?? '',
      descripcion: (m['descripcion'] as String?) ?? '',
      estado: (m['estado'] as String?) ?? 'publicada',
      motivoModeracion: m['motivo_moderacion'] as String?,
      fechaCreacion: parseFecha(m['fecha_creacion']) ?? DateTime.now(),
      fechaModeracion: parseFecha(m['fecha_moderacion']),
      meGusta: (m['me_gusta'] as num?)?.toInt() ?? 0,
      comentarios: (m['comentarios'] as num?)?.toInt() ?? 0,
      evidencias: (m['evidencias'] as num?)?.toInt() ?? 0,
    );
  }

  String get estadoEtiqueta => switch (estado) {
    'publicada' => 'Publicada',
    'oculta' => 'Restringida',
    'pendiente_moderacion' => 'Pendiente',
    'rechazada' => 'Rechazada',
    _ => capitalizar(estado),
  };

  bool get estaVisible => estado == 'publicada';
  bool get estaRestringida => estado == 'oculta';
  bool get puedeRestringirse =>
      estado == 'publicada' || estado == 'pendiente_moderacion';
}

/// Operaciones de moderación que no son contenido institucional:
/// reportes de cobro y cuentas de turistas.
class ModeracionRepository {
  ModeracionRepository(this._client);

  final SupabaseClient _client;

  Future<List<ReporteModeracion>> listarReportes() async {
    final data = await _client
        .from('reporte_cobro')
        .select(
          'id_reporte, servicio, precio_pagado, estado, fecha, '
          'destino(nombre), usuario(nombre)',
        )
        .order('fecha', ascending: false);
    return (data as List)
        .map(
          (m) => ReporteModeracion.fromMap(Map<String, dynamic>.from(m as Map)),
        )
        .toList();
  }

  Future<void> eliminarReporte(String id) async {
    await _client.from('reporte_cobro').delete().eq('id_reporte', id);
  }

  /// Publicaciones de la comunidad (publicadas, restringidas y eliminadas
  /// ya no aparecen) para que el staff las modere.
  Future<List<PublicacionModeracion>> listarPublicaciones() async {
    final data = await _client.rpc('listar_publicaciones_moderacion');
    return (data as List)
        .map(
          (m) => PublicacionModeracion.fromMap(
            Map<String, dynamic>.from(m as Map),
          ),
        )
        .toList();
  }

  /// `accion`: 'restringir' | 'eliminar' | 'restaurar'.
  /// El autor recibe una notificación con el motivo.
  Future<void> moderarPublicacion({
    required String id,
    required String accion,
    String? motivo,
  }) async {
    await _client.rpc(
      'moderar_publicacion',
      params: {
        'p_id_publicacion': id,
        'p_accion': accion,
        'p_motivo': motivo,
      },
    );
  }

  /// Solo devuelve turistas: la política RLS deja ver al moderador
  /// únicamente su propio perfil y las cuentas de turista.
  Future<List<UsuarioAdmin>> listarTuristas() async {
    final data = await _client
        .from('usuario')
        .select(
          'id_usuario, nombre, email, idioma, estado, fecha_registro, '
          'es_super_admin, rol(nombre)',
        )
        .order('fecha_registro', ascending: true);
    return (data as List)
        .map((m) => UsuarioAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .where((u) => u.rol == 'turista')
        .toList();
  }

  /// Suspende o reactiva una cuenta de turista. El trigger de la base de
  /// datos impide cualquier otro cambio (rol, correo, nombre, etc.).
  Future<void> cambiarEstadoTurista({
    required String id,
    required String estado,
  }) async {
    await _client
        .from('usuario')
        .update({'estado': estado})
        .eq('id_usuario', id);
  }
}

final moderacionRepositoryProvider = Provider<ModeracionRepository>(
  (ref) => ModeracionRepository(ref.watch(supabaseProvider)),
);

final reportesModeracionProvider =
    FutureProvider.autoDispose<List<ReporteModeracion>>(
      (ref) => ref.watch(moderacionRepositoryProvider).listarReportes(),
    );

final publicacionesModeracionProvider =
    FutureProvider.autoDispose<List<PublicacionModeracion>>(
      (ref) => ref.watch(moderacionRepositoryProvider).listarPublicaciones(),
    );

final turistasModeracionProvider =
    FutureProvider.autoDispose<List<UsuarioAdmin>>(
      (ref) => ref.watch(moderacionRepositoryProvider).listarTuristas(),
    );

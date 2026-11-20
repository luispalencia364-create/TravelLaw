import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../destinos/data/destinos_repository.dart';
import '../../lugares/data/lugares_repository.dart';

/// Texto de error amable en español (los RPC devuelven mensajes en español).
String mensajeErrorContenido(Object error) {
  if (error is PostgrestException && error.message.trim().isNotEmpty) {
    return error.message;
  }
  return 'No se pudo completar la operación. Revisa tu conexión.';
}

/// Convierte "4,5" o "4.5" en double. Devuelve null si no es válido.
double? parseCoordenada(String texto) {
  final limpio = texto.trim().replaceAll(',', '.');
  if (limpio.isEmpty) return null;
  return double.tryParse(limpio);
}

// ─────────────────────────────────────────────────────────────
// Modelos
// ─────────────────────────────────────────────────────────────

/// Cualquier destino, incluidos los deshabilitados.
class DestinoAdmin {
  const DestinoAdmin({
    required this.id,
    required this.nombre,
    required this.municipio,
    required this.posicion,
    required this.activo,
  });

  final int id;
  final String nombre;
  final String municipio;
  final (double, double) posicion;
  final bool activo;

  factory DestinoAdmin.fromMap(Map<String, dynamic> m) => DestinoAdmin(
    id: m['id_destino'] as int,
    nombre: (m['nombre'] as String?) ?? '',
    municipio: (m['municipio'] as String?) ?? '',
    posicion: (
      (m['lat'] as num?)?.toDouble() ?? 0,
      (m['lng'] as num?)?.toDouble() ?? 0,
    ),
    activo: (m['activo'] as bool?) ?? true,
  );

  String get etiqueta =>
      activo ? '$nombre · $municipio' : '$nombre · $municipio (inactivo)';
}

class CategoriaLugar {
  const CategoriaLugar({required this.id, required this.nombre});

  final int id;
  final String nombre;

  factory CategoriaLugar.fromMap(Map<String, dynamic> m) => CategoriaLugar(
    id: m['id_categoria'] as int,
    nombre: (m['nombre'] as String?) ?? '',
  );
}

class LugarAdmin {
  const LugarAdmin({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.idCategoria,
    required this.categoria,
    required this.nombre,
    required this.activo,
    this.horario,
    required this.posicion,
  });

  final int id;
  final int idDestino;
  final String destino;
  final int idCategoria;
  final String categoria;
  final String nombre;
  final String? horario;
  final bool activo;
  final (double, double) posicion;

  factory LugarAdmin.fromMap(Map<String, dynamic> m) => LugarAdmin(
    id: m['id_lugar'] as int,
    idDestino: m['id_destino'] as int,
    destino: (m['destino'] as String?) ?? '',
    idCategoria: m['id_categoria'] as int,
    categoria: (m['categoria'] as String?) ?? '',
    nombre: (m['nombre'] as String?) ?? '',
    horario: m['horario'] as String?,
    activo: (m['activo'] as bool?) ?? true,
    posicion: (
      (m['lat'] as num?)?.toDouble() ?? 0,
      (m['lng'] as num?)?.toDouble() ?? 0,
    ),
  );
}

class NormaAdmin {
  const NormaAdmin({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.tipo,
    required this.tituloEs,
    required this.contenidoEs,
    required this.vigente,
    this.tituloEn,
    this.contenidoEn,
    this.fuente,
    this.fechaActualizacion,
  });

  final int id;
  final int idDestino;
  final String destino;
  final String tipo;
  final String tituloEs;
  final String? tituloEn;
  final String contenidoEs;
  final String? contenidoEn;
  final String? fuente;
  final bool vigente;
  final DateTime? fechaActualizacion;

  factory NormaAdmin.fromMap(Map<String, dynamic> m) => NormaAdmin(
    id: m['id_norma'] as int,
    idDestino: m['id_destino'] as int,
    destino: (m['destino'] as String?) ?? '',
    tipo: (m['tipo'] as String?) ?? 'legal',
    tituloEs: (m['titulo_es'] as String?) ?? '',
    tituloEn: m['titulo_en'] as String?,
    contenidoEs: (m['contenido_es'] as String?) ?? '',
    contenidoEn: m['contenido_en'] as String?,
    fuente: m['fuente'] as String?,
    vigente: (m['vigente'] as bool?) ?? true,
    fechaActualizacion: parseFecha(m['fecha_actualizacion']),
  );

  static const tipos = {
    'legal': 'Legal',
    'ambiental': 'Ambiental',
    'cultural': 'Cultural',
    'otro': 'Otro',
  };
  String get tipoEtiqueta => tipos[tipo] ?? capitalizar(tipo);
}

class ContactoAdmin {
  const ContactoAdmin({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.entidad,
    required this.telefono,
    this.direccion,
    this.fuente,
    this.fechaActualizacion,
  });

  final int id;
  final int idDestino;
  final String destino;
  final String entidad;
  final String telefono;
  final String? direccion;
  final String? fuente;
  final DateTime? fechaActualizacion;

  factory ContactoAdmin.fromMap(Map<String, dynamic> m) => ContactoAdmin(
    id: m['id_contacto'] as int,
    idDestino: m['id_destino'] as int,
    destino: (m['destino'] as String?) ?? '',
    entidad: (m['entidad'] as String?) ?? '',
    telefono: (m['telefono'] as String?) ?? '',
    direccion: m['direccion'] as String?,
    fuente: m['fuente'] as String?,
    fechaActualizacion: parseFecha(m['fecha_actualizacion']),
  );
}

class AlertaAdmin {
  const AlertaAdmin({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.autor,
    required this.tipo,
    required this.descripcion,
    required this.estado,
    required this.fechaCreacion,
    this.fechaEvento,
    required this.posicion,
  });

  final String id;
  final int idDestino;
  final String destino;
  final String autor;
  final String tipo;
  final String descripcion;
  final String estado;
  final DateTime fechaCreacion;
  final DateTime? fechaEvento;
  final (double, double) posicion;

  factory AlertaAdmin.fromMap(Map<String, dynamic> m) => AlertaAdmin(
    id: (m['id_alerta'] as String?) ?? '',
    idDestino: m['id_destino'] as int,
    destino: (m['destino'] as String?) ?? '',
    autor: (m['autor'] as String?) ?? '',
    tipo: (m['tipo'] as String?) ?? 'otro',
    descripcion: (m['descripcion'] as String?) ?? '',
    estado: (m['estado'] as String?) ?? 'pendiente_moderacion',
    fechaEvento: parseFecha(m['fecha_evento']),
    fechaCreacion: parseFecha(m['fecha_creacion']) ?? DateTime.now(),
    posicion: (
      (m['lat'] as num?)?.toDouble() ?? 0,
      (m['lng'] as num?)?.toDouble() ?? 0,
    ),
  );

  static const tipos = {
    'riesgo': 'Riesgo',
    'emergencia': 'Emergencia',
    'cierre_vial': 'Cierre vial',
    'clima': 'Clima',
    'otro': 'Otro',
  };
  static const estados = {
    'pendiente_moderacion': 'Pendiente',
    'verificada': 'Verificada',
    'rechazada': 'Rechazada',
    'vencida': 'Vencida',
  };

  String get tipoEtiqueta => tipos[tipo] ?? capitalizar(tipo);
  String get estadoEtiqueta => estados[estado] ?? capitalizar(estado);
}

// ─────────────────────────────────────────────────────────────
// Repositorio
// ─────────────────────────────────────────────────────────────

/// CRUD de contenido institucional: destinos, lugares, normas, alertas
/// oficiales y contactos SOS. Usa RPCs cuando la ubicación es necesaria
/// (PostGIS no acepta lat/lng planos desde el cliente).
class ContenidoRepository {
  ContenidoRepository(this._client);

  final SupabaseClient _client;

  Future<List<DestinoAdmin>> listarDestinos() async {
    final data = await _client.rpc('listar_destinos_admin');
    return (data as List)
        .map((m) => DestinoAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<List<CategoriaLugar>> listarCategorias() async {
    final data = await _client.rpc('listar_categorias_lugar');
    return (data as List)
        .map((m) => CategoriaLugar.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<List<LugarAdmin>> listarLugares({int? idDestino}) async {
    final data = await _client.rpc(
      'listar_lugares_admin',
      params: {'p_id_destino': idDestino},
    );
    return (data as List)
        .map((m) => LugarAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<List<NormaAdmin>> listarNormas({int? idDestino}) async {
    final data = await _client.rpc(
      'listar_normas_admin',
      params: {'p_id_destino': idDestino},
    );
    return (data as List)
        .map((m) => NormaAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<List<ContactoAdmin>> listarContactos({int? idDestino}) async {
    final data = await _client.rpc(
      'listar_contactos_admin',
      params: {'p_id_destino': idDestino},
    );
    return (data as List)
        .map((m) => ContactoAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  Future<List<AlertaAdmin>> listarAlertas() async {
    final data = await _client.rpc('listar_alertas_admin');
    return (data as List)
        .map((m) => AlertaAdmin.fromMap(Map<String, dynamic>.from(m as Map)))
        .toList();
  }

  // Destinos -------------------------------------------------------------
  Future<int> crearDestino({
    required String nombre,
    required String municipio,
    required double lat,
    required double lng,
  }) async {
    final id = await _client.rpc(
      'admin_crear_destino',
      params: {
        'p_nombre': nombre,
        'p_municipio': municipio,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    return id as int;
  }

  Future<void> actualizarDestino({
    required int id,
    required String nombre,
    required String municipio,
    double? lat,
    double? lng,
    bool? activo,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      'p_nombre': nombre,
      'p_municipio': municipio,
    };
    if (lat != null) params['p_lat'] = lat;
    if (lng != null) params['p_lng'] = lng;
    if (activo != null) params['p_activo'] = activo;
    await _client.rpc('admin_actualizar_destino', params: params);
  }

  // Lugares --------------------------------------------------------------
  Future<int> crearLugar({
    required int idDestino,
    required int idCategoria,
    required String nombre,
    String? horario,
    required double lat,
    required double lng,
  }) async {
    final id = await _client.rpc(
      'admin_crear_lugar',
      params: {
        'p_id_destino': idDestino,
        'p_id_categoria': idCategoria,
        'p_nombre': nombre,
        'p_horario': horario,
        'p_lat': lat,
        'p_lng': lng,
      },
    );
    return id as int;
  }

  Future<void> actualizarLugar({
    required int id,
    required int idDestino,
    required int idCategoria,
    required String nombre,
    String? horario,
    double? lat,
    double? lng,
    bool? activo,
  }) async {
    final params = <String, dynamic>{
      'p_id': id,
      'p_id_destino': idDestino,
      'p_id_categoria': idCategoria,
      'p_nombre': nombre,
      'p_horario': horario,
    };
    if (lat != null) params['p_lat'] = lat;
    if (lng != null) params['p_lng'] = lng;
    if (activo != null) params['p_activo'] = activo;
    await _client.rpc('admin_actualizar_lugar', params: params);
  }

  Future<void> eliminarLugar(int id) async {
    await _client.from('lugar').delete().eq('id_lugar', id);
  }

  // Normas ---------------------------------------------------------------
  Future<void> crearNorma({
    required int idDestino,
    required String tipo,
    required String tituloEs,
    required String contenidoEs,
    String? tituloEn,
    String? contenidoEn,
    String? fuente,
  }) async {
    await _client.from('norma').insert({
      'id_destino': idDestino,
      'tipo': tipo,
      'titulo_es': tituloEs,
      if (tituloEn?.trim().isNotEmpty ?? false) 'titulo_en': tituloEn!.trim(),
      'contenido_es': contenidoEs,
      if (contenidoEn?.trim().isNotEmpty ?? false)
        'contenido_en': contenidoEn!.trim(),
      if (fuente?.trim().isNotEmpty ?? false) 'fuente': fuente!.trim(),
      'vigente': true,
    });
  }

  Future<void> actualizarNorma({
    required int id,
    required String tipo,
    required String tituloEs,
    required String contenidoEs,
    String? tituloEn,
    String? contenidoEn,
    String? fuente,
    bool? vigente,
  }) async {
    await _client
        .from('norma')
        .update({
          'tipo': tipo,
          'titulo_es': tituloEs,
          'titulo_en': tituloEn,
          'contenido_es': contenidoEs,
          'contenido_en': contenidoEn,
          'fuente': fuente,
          'vigente': ?vigente,
        })
        .eq('id_norma', id);
  }

  Future<void> eliminarNorma(int id) async {
    await _client.from('norma').delete().eq('id_norma', id);
  }

  Future<void> cambiarVigenciaNorma({
    required int id,
    required bool vigente,
  }) async {
    await _client.from('norma').update({'vigente': vigente}).eq('id_norma', id);
  }

  // Destinos (eliminación) ------------------------------------------------
  Future<void> eliminarDestino(int id) async {
    await _client.from('destino').delete().eq('id_destino', id);
  }

  // Alertas --------------------------------------------------------------
  Future<String> crearAlerta({
    required int idDestino,
    required String tipo,
    required String descripcion,
    required DateTime fechaEvento,
    double? lat,
    double? lng,
    String estado = 'verificada',
  }) async {
    final id = await _client.rpc(
      'admin_crear_alerta',
      params: {
        'p_id_destino': idDestino,
        'p_tipo': tipo,
        'p_descripcion': descripcion,
        'p_fecha_evento': fechaEvento.toUtc().toIso8601String(),
        'p_estado': estado,
      },
    );
    return id as String;
  }

  Future<void> actualizarAlerta({
    required String id,
    required String tipo,
    required String descripcion,
    required DateTime fechaEvento,
    required String estado,
  }) async {
    await _client
        .from('alerta')
        .update({
          'tipo': tipo,
          'descripcion': descripcion,
          'fecha_evento': fechaEvento.toUtc().toIso8601String(),
          'estado': estado,
        })
        .eq('id_alerta', id);
  }

  Future<void> eliminarAlerta(String id) async {
    await _client.from('alerta').delete().eq('id_alerta', id);
  }

  // Contactos SOS --------------------------------------------------------
  Future<void> crearContacto({
    required int idDestino,
    required String entidad,
    required String telefono,
    String? direccion,
    String? fuente,
  }) async {
    await _client.from('contacto_emergencia').insert({
      'id_destino': idDestino,
      'entidad': entidad,
      'telefono': telefono,
      if (direccion?.trim().isNotEmpty ?? false) 'direccion': direccion!.trim(),
      if (fuente?.trim().isNotEmpty ?? false) 'fuente': fuente!.trim(),
    });
  }

  Future<void> actualizarContacto({
    required int id,
    required int idDestino,
    required String entidad,
    required String telefono,
    String? direccion,
    String? fuente,
  }) async {
    await _client
        .from('contacto_emergencia')
        .update({
          'id_destino': idDestino,
          'entidad': entidad,
          'telefono': telefono,
          'direccion': direccion,
          'fuente': fuente,
        })
        .eq('id_contacto', id);
  }

  Future<void> eliminarContacto(int id) async {
    await _client.from('contacto_emergencia').delete().eq('id_contacto', id);
  }
}

// ─────────────────────────────────────────────────────────────
// Proveedores
// ─────────────────────────────────────────────────────────────

final contenidoRepositoryProvider = Provider<ContenidoRepository>(
  (ref) => ContenidoRepository(ref.watch(supabaseProvider)),
);

final destinosAdminProvider = FutureProvider.autoDispose<List<DestinoAdmin>>(
  (ref) => ref.watch(contenidoRepositoryProvider).listarDestinos(),
);

final categoriasLugarProvider =
    FutureProvider.autoDispose<List<CategoriaLugar>>(
      (ref) => ref.watch(contenidoRepositoryProvider).listarCategorias(),
    );

final lugaresAdminProvider = FutureProvider.autoDispose<List<LugarAdmin>>(
  (ref) => ref.watch(contenidoRepositoryProvider).listarLugares(),
);

final normasAdminProvider = FutureProvider.autoDispose<List<NormaAdmin>>(
  (ref) => ref.watch(contenidoRepositoryProvider).listarNormas(),
);

final contactosAdminProvider = FutureProvider.autoDispose<List<ContactoAdmin>>(
  (ref) => ref.watch(contenidoRepositoryProvider).listarContactos(),
);

final alertasAdminProvider = FutureProvider.autoDispose<List<AlertaAdmin>>(
  (ref) => ref.watch(contenidoRepositoryProvider).listarAlertas(),
);

/// Invalida todos los listados de contenido (llamar tras cada operación).
void refrescarContenido(WidgetRef ref) {
  ref.invalidate(destinosAdminProvider);
  ref.invalidate(categoriasLugarProvider);
  ref.invalidate(lugaresAdminProvider);
  ref.invalidate(normasAdminProvider);
  ref.invalidate(contactosAdminProvider);
  ref.invalidate(alertasAdminProvider);
  // Listados públicos: el inicio y los selectores deben ver los cambios.
  ref.invalidate(destinosProvider);
  ref.invalidate(lugaresProvider);
}

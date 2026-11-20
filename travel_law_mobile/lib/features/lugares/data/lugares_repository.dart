import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/data/auth_repository.dart';

/// Lugar (restaurante, alojamiento, atracción...) visible para los viajeros.
class LugarPublico {
  const LugarPublico({
    required this.id,
    required this.idDestino,
    required this.destino,
    required this.municipio,
    required this.idCategoria,
    required this.categoria,
    required this.nombre,
    required this.posicion,
    required this.destinoPosicion,
    this.horario,
  });

  final int id;
  final int idDestino;
  final String destino;
  final String municipio;
  final int idCategoria;
  final String categoria;
  final String nombre;
  final String? horario;
  final LatLng posicion;
  final LatLng destinoPosicion;

  factory LugarPublico.fromMap(Map<String, dynamic> m) => LugarPublico(
    id: m['id_lugar'] as int,
    idDestino: m['id_destino'] as int,
    destino: (m['destino'] as String?) ?? '',
    municipio: (m['municipio'] as String?) ?? '',
    idCategoria: m['id_categoria'] as int,
    categoria: (m['categoria'] as String?) ?? '',
    nombre: (m['nombre'] as String?) ?? '',
    horario: m['horario'] as String?,
    posicion: LatLng(
      (m['lat'] as num?)?.toDouble() ?? 0,
      (m['lng'] as num?)?.toDouble() ?? 0,
    ),
    destinoPosicion: LatLng(
      (m['destino_lat'] as num?)?.toDouble() ?? 0,
      (m['destino_lng'] as num?)?.toDouble() ?? 0,
    ),
  );
}

/// Lugares activos de destinos activos (función SQL listar_lugares_publicos).
final lugaresProvider = FutureProvider.autoDispose<List<LugarPublico>>((
  ref,
) async {
  final data = await ref.watch(supabaseProvider).rpc('listar_lugares_publicos');
  return (data as List)
      .map((e) => LugarPublico.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

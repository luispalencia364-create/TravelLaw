import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../auth/data/auth_repository.dart';

class Destino {
  const Destino({
    required this.id,
    required this.nombre,
    required this.municipio,
    required this.posicion,
  });

  final int id;
  final String nombre;
  final String municipio;
  final LatLng posicion;

  factory Destino.fromMap(Map<String, dynamic> m) {
    return Destino(
      id: m['id_destino'] as int,
      nombre: m['nombre'] as String,
      municipio: m['municipio'] as String,
      posicion: LatLng(
        (m['lat'] as num).toDouble(),
        (m['lng'] as num).toDouble(),
      ),
    );
  }
}

/// Destinos activos con coordenadas (función SQL listar_destinos).
final destinosProvider = FutureProvider.autoDispose<List<Destino>>((ref) async {
  final data = await ref.watch(supabaseProvider).rpc('listar_destinos');
  return (data as List)
      .map((e) => Destino.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

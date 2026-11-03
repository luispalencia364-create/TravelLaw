import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class Publicacion {
  const Publicacion({
    required this.id,
    required this.autor,
    required this.descripcion,
    this.fecha,
  });

  final String id;
  final String autor;
  final String descripcion;
  final DateTime? fecha;
}

/// Feed del destino: publicaciones visibles, de la más reciente a la más antigua.
/// Los nombres de los autores se piden con la función perfiles_publicos
/// (no expone correos).
final publicacionesProvider = FutureProvider.autoDispose
    .family<List<Publicacion>, int>((ref, idDestino) async {
      final client = ref.watch(supabaseProvider);
      final data = await client
          .from('publicacion')
          .select('id_publicacion, id_usuario, descripcion, fecha_creacion')
          .eq('id_destino', idDestino)
          .eq('estado', 'publicada')
          .order('fecha_creacion', ascending: false)
          .limit(50);

      final ids = data.map((m) => m['id_usuario'] as String).toSet().toList();
      final nombres = <String, String>{};
      if (ids.isNotEmpty) {
        final perfiles = await client.rpc(
          'perfiles_publicos',
          params: {'p_ids': ids},
        );
        for (final p in (perfiles as List)) {
          final mapa = Map<String, dynamic>.from(p as Map);
          nombres[mapa['id_usuario'] as String] = mapa['nombre'] as String;
        }
      }

      return data
          .map(
            (m) => Publicacion(
              id: m['id_publicacion'] as String,
              autor: nombres[m['id_usuario'] as String] ?? 'Viajero',
              descripcion: m['descripcion'] as String,
              fecha: parseFecha(m['fecha_creacion']),
            ),
          )
          .toList();
    });

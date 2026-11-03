import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class Norma {
  const Norma({
    required this.id,
    required this.tipo,
    required this.tituloEs,
    this.tituloEn,
    required this.contenidoEs,
    this.contenidoEn,
    this.fuente,
    this.fechaActualizacion,
  });

  final int id;
  final String tipo;
  final String tituloEs;
  final String? tituloEn;
  final String contenidoEs;
  final String? contenidoEn;
  final String? fuente;
  final DateTime? fechaActualizacion;

  factory Norma.fromMap(Map<String, dynamic> m) => Norma(
    id: m['id_norma'] as int,
    tipo: (m['tipo'] as String?) ?? 'legal',
    tituloEs: m['titulo_es'] as String,
    tituloEn: m['titulo_en'] as String?,
    contenidoEs: m['contenido_es'] as String,
    contenidoEn: m['contenido_en'] as String?,
    fuente: m['fuente'] as String?,
    fechaActualizacion: parseFecha(m['fecha_actualizacion']),
  );
}

class ZonaRestringida {
  const ZonaRestringida({
    required this.id,
    required this.nombre,
    this.normaEs,
    this.normaEn,
  });

  final int id;
  final String nombre;
  final String? normaEs;
  final String? normaEn;

  factory ZonaRestringida.fromMap(Map<String, dynamic> m) {
    final norma = m['norma'];
    return ZonaRestringida(
      id: m['id_zona'] as int,
      nombre: m['nombre'] as String,
      normaEs: norma is Map ? norma['titulo_es'] as String? : null,
      normaEn: norma is Map ? norma['titulo_en'] as String? : null,
    );
  }
}

/// Normas vigentes del destino (RN-07: con fuente y fecha de actualización).
final normasProvider = FutureProvider.autoDispose.family<List<Norma>, int>((
  ref,
  idDestino,
) async {
  final data = await ref
      .watch(supabaseProvider)
      .from('norma')
      .select(
        'id_norma, tipo, titulo_es, titulo_en, contenido_es, contenido_en, '
        'fuente, fecha_actualizacion',
      )
      .eq('id_destino', idDestino)
      .eq('vigente', true)
      .order('titulo_es');
  return data.map(Norma.fromMap).toList();
});

final zonasProvider = FutureProvider.autoDispose
    .family<List<ZonaRestringida>, int>((ref, idDestino) async {
      final data = await ref
          .watch(supabaseProvider)
          .from('zona_restringida')
          .select('id_zona, nombre, norma(titulo_es, titulo_en)')
          .eq('id_destino', idDestino)
          .order('nombre');
      return data.map(ZonaRestringida.fromMap).toList();
    });

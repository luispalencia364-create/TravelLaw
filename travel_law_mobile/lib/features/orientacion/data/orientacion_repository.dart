import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class Guia {
  const Guia({
    required this.id,
    required this.categoria,
    required this.tipo,
    required this.tituloEs,
    this.tituloEn,
    required this.contenidoEs,
    this.contenidoEn,
  });

  final int id;
  final String categoria;
  final String tipo;
  final String tituloEs;
  final String? tituloEn;
  final String contenidoEs;
  final String? contenidoEn;

  factory Guia.fromMap(Map<String, dynamic> m) {
    final cat = m['categoria_guia'];
    return Guia(
      id: m['id_guia'] as int,
      categoria: cat is Map ? (cat['nombre'] as String? ?? '') : '',
      tipo: (m['tipo'] as String?) ?? 'guia',
      tituloEs: m['titulo_es'] as String,
      tituloEn: m['titulo_en'] as String?,
      contenidoEs: m['contenido_es'] as String,
      contenidoEn: m['contenido_en'] as String?,
    );
  }
}

/// Guías y preguntas frecuentes del destino, con su categoría.
final guiasProvider = FutureProvider.autoDispose.family<List<Guia>, int>((
  ref,
  idDestino,
) async {
  final data = await ref
      .watch(supabaseProvider)
      .from('guia')
      .select(
        'id_guia, tipo, titulo_es, titulo_en, contenido_es, contenido_en, '
        'categoria_guia(nombre)',
      )
      .eq('id_destino', idDestino)
      .order('titulo_es');
  return data.map(Guia.fromMap).toList();
});

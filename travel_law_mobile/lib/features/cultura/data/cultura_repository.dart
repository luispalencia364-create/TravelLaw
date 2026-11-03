import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';

class Expresion {
  const Expresion({
    required this.id,
    required this.expresion,
    required this.significadoEs,
    this.significadoEn,
  });

  final int id;
  final String expresion;
  final String significadoEs;
  final String? significadoEn;

  factory Expresion.fromMap(Map<String, dynamic> m) => Expresion(
    id: m['id_expresion'] as int,
    expresion: m['expresion'] as String,
    significadoEs: m['significado_es'] as String,
    significadoEn: m['significado_en'] as String?,
  );
}

/// Expresiones locales del destino (traductor cultural, sin IA).
final expresionesProvider = FutureProvider.autoDispose
    .family<List<Expresion>, int>((ref, idDestino) async {
      final data = await ref
          .watch(supabaseProvider)
          .from('expresion_cultural')
          .select('id_expresion, expresion, significado_es, significado_en')
          .eq('id_destino', idDestino)
          .order('expresion');
      return data.map(Expresion.fromMap).toList();
    });

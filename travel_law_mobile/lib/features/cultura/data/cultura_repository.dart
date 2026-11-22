import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class Expresion {
  const Expresion({
    required this.id,
    required this.expresion,
    required this.significadoEs,
    this.significadoEn,
    this.estado = 'aprobada',
    this.idUsuario,
    this.fechaCreacion,
  });

  final int id;
  final String expresion;
  final String significadoEs;
  final String? significadoEn;
  final String estado;
  final String? idUsuario;
  final DateTime? fechaCreacion;

  bool get esPendiente => estado == 'pendiente';
  bool get esAprobada => estado == 'aprobada';

  factory Expresion.fromMap(Map<String, dynamic> m) => Expresion(
        id: m['id_expresion'] as int,
        expresion: m['expresion'] as String,
        significadoEs: m['significado_es'] as String,
        significadoEn: m['significado_en'] as String?,
        estado: (m['estado'] as String?) ?? 'aprobada',
        idUsuario: m['id_usuario'] as String?,
        fechaCreacion: parseFecha(m['fecha_creacion']),
      );
}

final expresionesProvider = FutureProvider.autoDispose
    .family<List<Expresion>, int>((ref, idDestino) async {
  final data = await ref
      .watch(supabaseProvider)
      .from('expresion_cultural')
      .select(
        'id_expresion, expresion, significado_es, significado_en, '
        'estado, id_usuario, fecha_creacion',
      )
      .eq('id_destino', idDestino)
      .order('expresion');
  return data.map(Expresion.fromMap).toList();
});

final expresionesPendientesProvider =
    FutureProvider.autoDispose<List<Expresion>>((ref) async {
  final data = await ref
      .watch(supabaseProvider)
      .from('expresion_cultural')
      .select(
        'id_expresion, id_destino, expresion, significado_es, significado_en, '
        'estado, id_usuario, fecha_creacion',
      )
      .eq('estado', 'pendiente')
      .order('fecha_creacion', ascending: false);
  return data.map(Expresion.fromMap).toList();
});

Future<void> crearExpresion(
  WidgetRef ref,
  int idDestino,
  String expresion,
  String significadoEs,
  String? significadoEn,
) async {
  final uid = ref.read(supabaseProvider).auth.currentUser?.id;
  if (uid == null) throw StateError('Sesión no disponible');
  await ref.read(supabaseProvider).from('expresion_cultural').insert({
    'id_destino': idDestino,
    'expresion': expresion,
    'significado_es': significadoEs,
    'significado_en': significadoEn,
    'id_usuario': uid,
    'estado': 'pendiente',
  });
}

Future<void> moderarExpresion(WidgetRef ref, int id, String accion) async {
  await ref.read(supabaseProvider).rpc(
        'moderar_expresion',
        params: {'p_id_expresion': id, 'p_accion': accion},
      );
}

Future<void> eliminarExpresion(WidgetRef ref, int id) async {
  await ref.read(supabaseProvider).from('expresion_cultural').delete().eq(
        'id_expresion',
        id,
      );
}
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class PrecioReferencia {
  const PrecioReferencia({
    required this.id,
    required this.servicio,
    required this.minimo,
    required this.maximo,
    this.lugar,
    this.fuente,
    this.fechaActualizacion,
  });

  final int id;
  final String servicio;
  final double minimo;
  final double maximo;
  final String? lugar;
  final String? fuente;
  final DateTime? fechaActualizacion;

  factory PrecioReferencia.fromMap(Map<String, dynamic> m) {
    final lugar = m['lugar'];
    return PrecioReferencia(
      id: m['id_precio'] as int,
      servicio: m['servicio'] as String,
      minimo: (m['precio_min'] as num).toDouble(),
      maximo: (m['precio_max'] as num).toDouble(),
      lugar: lugar is Map ? lugar['nombre'] as String? : null,
      fuente: m['fuente'] as String?,
      fechaActualizacion: parseFecha(m['fecha_actualizacion']),
    );
  }
}

class ReporteCobro {
  const ReporteCobro({
    required this.id,
    required this.servicio,
    required this.precioPagado,
    required this.estado,
    this.fecha,
  });

  final String id;
  final String servicio;
  final double precioPagado;
  final String estado;
  final DateTime? fecha;

  factory ReporteCobro.fromMap(Map<String, dynamic> m) => ReporteCobro(
    id: m['id_reporte'] as String,
    servicio: m['servicio'] as String,
    precioPagado: (m['precio_pagado'] as num).toDouble(),
    estado: (m['estado'] as String?) ?? 'pendiente_revision',
    fecha: parseFecha(m['fecha']),
  );
}

/// Precios de referencia del destino; los de un lugar traen su nombre.
final preciosProvider = FutureProvider.autoDispose
    .family<List<PrecioReferencia>, int>((ref, idDestino) async {
      final data = await ref
          .watch(supabaseProvider)
          .from('precio_referencia')
          .select(
            'id_precio, servicio, precio_min, precio_max, fuente, '
            'fecha_actualizacion, lugar(nombre)',
          )
          .eq('id_destino', idDestino)
          .order('servicio');
      return data.map(PrecioReferencia.fromMap).toList();
    });

/// Reportes de cobro abusivo hechos por el usuario.
final misReportesCobroProvider = FutureProvider.autoDispose<List<ReporteCobro>>(
  (ref) async {
    final client = ref.watch(supabaseProvider);
    final uid = client.auth.currentUser?.id;
    if (uid == null) return const <ReporteCobro>[];
    final data = await client
        .from('reporte_cobro')
        .select('id_reporte, servicio, precio_pagado, fecha, estado')
        .eq('id_usuario', uid)
        .order('fecha', ascending: false);
    return data.map(ReporteCobro.fromMap).toList();
  },
);

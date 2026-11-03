import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

class ContactoEmergencia {
  const ContactoEmergencia({
    required this.id,
    required this.entidad,
    required this.telefono,
    this.direccion,
    this.fuente,
    this.fechaActualizacion,
  });

  final int id;
  final String entidad;
  final String telefono;
  final String? direccion;
  final String? fuente;
  final DateTime? fechaActualizacion;

  factory ContactoEmergencia.fromMap(Map<String, dynamic> m) =>
      ContactoEmergencia(
        id: m['id_contacto'] as int,
        entidad: m['entidad'] as String,
        telefono: m['telefono'] as String,
        direccion: m['direccion'] as String?,
        fuente: m['fuente'] as String?,
        fechaActualizacion: parseFecha(m['fecha_actualizacion']),
      );
}

/// Contactos oficiales de emergencia del destino (RN-07: fuente y fecha).
final contactosProvider = FutureProvider.autoDispose
    .family<List<ContactoEmergencia>, int>((ref, idDestino) async {
      final data = await ref
          .watch(supabaseProvider)
          .from('contacto_emergencia')
          .select(
            'id_contacto, entidad, telefono, direccion, fuente, fecha_actualizacion',
          )
          .eq('id_destino', idDestino)
          .order('entidad');
      return data.map(ContactoEmergencia.fromMap).toList();
    });

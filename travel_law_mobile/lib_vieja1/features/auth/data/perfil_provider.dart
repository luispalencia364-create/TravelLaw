import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import 'auth_repository.dart';

class Perfil {
  const Perfil({
    required this.nombre,
    required this.email,
    required this.rol,
    required this.idioma,
    required this.estado,
    this.fechaRegistro,
  });

  final String nombre;
  final String email;
  final String rol;
  final String idioma;
  final String estado;
  final DateTime? fechaRegistro;

  factory Perfil.fromMap(Map<String, dynamic> m) {
    final rolMap = m['rol'];
    return Perfil(
      nombre: (m['nombre'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      rol: rolMap is Map
          ? (rolMap['nombre'] as String? ?? 'turista')
          : 'turista',
      idioma: (m['idioma'] as String?) ?? 'es',
      estado: (m['estado'] as String?) ?? 'activo',
      fechaRegistro: DateTime.tryParse(m['fecha_registro']?.toString() ?? '')
          ?.toLocal(),
    );
  }

  String get rolEtiqueta => capitalizar(rol);
  String get idiomaEtiqueta => idioma == 'en' ? 'English' : 'Español';
  String get estadoEtiqueta => capitalizar(estado);
  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();

  /// Solo el primer nombre, para el saludo.
  String get primerNombre {
    final partes = nombre.trim().split(' ');
    return partes.isEmpty ? nombre : partes.first;
  }
}

/// Perfil del usuario con sesión (se recarga si cambia la sesión).
final perfilProvider = FutureProvider.autoDispose<Perfil?>((ref) async {
  ref.watch(authStateProvider);
  final datos = await ref.watch(authRepositoryProvider).perfilActual();
  return datos == null ? null : Perfil.fromMap(datos);
});

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import 'auth_repository.dart';

class Perfil {
  const Perfil({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.idioma,
    required this.estado,
    required this.esSuperAdmin,
    this.fechaRegistro,
  });

  final String id;
  final String nombre;
  final String email;
  final String rol;
  final String idioma;
  final String estado;
  final bool esSuperAdmin;
  final DateTime? fechaRegistro;

  factory Perfil.fromMap(Map<String, dynamic> m) {
    final rolMap = m['rol'];
    return Perfil(
      id: (m['id_usuario'] as String?) ?? '',
      nombre: (m['nombre'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      rol: rolMap is Map
          ? (rolMap['nombre'] as String? ?? 'turista')
          : 'turista',
      idioma: (m['idioma'] as String?) ?? 'es',
      estado: (m['estado'] as String?) ?? 'activo',
      esSuperAdmin: (m['es_super_admin'] as bool?) ?? false,
      fechaRegistro: parseFecha(m['fecha_registro']),
    );
  }

  bool get esAdministrador => rol == 'administrador';
  bool get esModerador => rol == 'moderador';

  String get rolEtiqueta {
    if (esSuperAdmin) return 'Superadministrador';
    return capitalizar(rol);
  }

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

/// Idioma preferido del contenido ('es' o 'en'), tomado del perfil.
final idiomaProvider = Provider<String>((ref) {
  return ref
      .watch(perfilProvider)
      .maybeWhen(data: (p) => p?.idioma ?? 'es', orElse: () => 'es');
});

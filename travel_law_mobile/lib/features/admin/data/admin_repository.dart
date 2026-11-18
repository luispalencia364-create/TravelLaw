import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

/// Cuenta mostrada en el panel de administración.
class UsuarioAdmin {
  const UsuarioAdmin({
    required this.id,
    required this.nombre,
    required this.email,
    required this.rol,
    required this.estado,
    required this.idioma,
    required this.esSuperAdmin,
    this.fechaRegistro,
  });

  final String id;
  final String nombre;
  final String email;
  final String rol;
  final String estado;
  final String idioma;
  final bool esSuperAdmin;
  final DateTime? fechaRegistro;

  factory UsuarioAdmin.fromMap(Map<String, dynamic> m) {
    final rolMap = m['rol'];
    return UsuarioAdmin(
      id: (m['id_usuario'] as String?) ?? '',
      nombre: (m['nombre'] as String?) ?? '',
      email: (m['email'] as String?) ?? '',
      rol: rolMap is Map
          ? (rolMap['nombre'] as String? ?? 'turista')
          : 'turista',
      estado: (m['estado'] as String?) ?? 'activo',
      idioma: (m['idioma'] as String?) ?? 'es',
      esSuperAdmin: (m['es_super_admin'] as bool?) ?? false,
      fechaRegistro: parseFecha(m['fecha_registro']),
    );
  }

  bool get esAdministrador => rol == 'administrador';
  bool get esModerador => rol == 'moderador';
  bool get estaActivo => estado == 'activo';
  bool get estaSuspendido => estado == 'suspendido';
  String get inicial => nombre.isEmpty ? '?' : nombre[0].toUpperCase();

  String get rolEtiqueta {
    if (esSuperAdmin) return 'Superadministrador';
    return capitalizar(rol);
  }

  String get estadoEtiqueta => capitalizar(estado);
}

class AdminRepository {
  AdminRepository(this._client);

  final SupabaseClient _client;

  /// Lista todos los perfiles. La política RLS solo permite esta consulta
  /// al rol administrador.
  Future<List<UsuarioAdmin>> listarUsuarios() async {
    final data = await _client
        .from('usuario')
        .select(
          'id_usuario, nombre, email, idioma, estado, fecha_registro, '
          'es_super_admin, rol(nombre)',
        )
        .order('es_super_admin', ascending: false)
        .order('fecha_registro', ascending: true);

    return (data as List)
        .map(
          (m) => UsuarioAdmin.fromMap(Map<String, dynamic>.from(m as Map)),
        )
        .toList();
  }

  /// Crea una cuenta con rol administrador o moderador.
  Future<String> crearUsuario({
    required String nombre,
    required String email,
    required String password,
    required String rol,
  }) async {
    final id = await _client.rpc(
      'admin_crear_usuario',
      params: {
        'p_nombre': nombre,
        'p_email': email,
        'p_password': password,
        'p_rol': rol,
      },
    );
    return id as String;
  }

  /// Cambia rol, estado o el flag de superadministrador.
  Future<void> actualizarUsuario({
    required String id,
    String? rol,
    String? estado,
    bool? esSuperAdmin,
  }) async {
    final params = <String, dynamic>{'p_id': id};
    if (rol != null) params['p_rol'] = rol;
    if (estado != null) params['p_estado'] = estado;
    if (esSuperAdmin != null) params['p_es_super_admin'] = esSuperAdmin;

    await _client.rpc('admin_actualizar_usuario', params: params);
  }

  /// Elimina la cuenta de Auth (y su perfil en cascada).
  Future<void> eliminarUsuario(String id) async {
    await _client.rpc('admin_eliminar_usuario', params: {'p_id': id});
  }
}

final adminRepositoryProvider = Provider<AdminRepository>(
  (ref) => AdminRepository(ref.watch(supabaseProvider)),
);

/// Todos los usuarios de la plataforma, ordenados con el superadministrador
/// primero.
final usuariosAdminProvider = FutureProvider.autoDispose<List<UsuarioAdmin>>(
  (ref) => ref.watch(adminRepositoryProvider).listarUsuarios(),
);

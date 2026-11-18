import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

final supabaseProvider = Provider<SupabaseClient>(
  (ref) => Supabase.instance.client,
);

/// Eventos de sesión (inicio, cierre, renovación de token).
final authStateProvider = StreamProvider<AuthState>(
  (ref) => ref.watch(supabaseProvider).auth.onAuthStateChange,
);

final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => AuthRepository(ref.watch(supabaseProvider)),
);

class AuthRepository {
  AuthRepository(this._client);

  final SupabaseClient _client;

  Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) {
    return _client.auth.signInWithPassword(email: email, password: password);
  }

  /// [rol] solo puede ser 'turista' o 'residente'. El servidor ignora
  /// cualquier otro valor (el trigger handle_new_user de la base de datos).
  Future<AuthResponse> signUp({
    required String nombre,
    required String email,
    required String password,
    required String rol,
    String idioma = 'es',
  }) {
    return _client.auth.signUp(
      email: email,
      password: password,
      data: {'nombre': nombre, 'rol': rol, 'idioma': idioma},
    );
  }

  Future<void> sendPasswordReset(String email) {
    return _client.auth.resetPasswordForEmail(email);
  }

  Future<void> signOut() => _client.auth.signOut();

  /// Perfil del usuario con sesión: datos personales y rol.
  Future<Map<String, dynamic>?> perfilActual() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;
    return _client
        .from('usuario')
        .select(
          'id_usuario, nombre, email, idioma, estado, fecha_registro, '
          'es_super_admin, rol(nombre)',
        )
        .eq('id_usuario', uid)
        .maybeSingle();
  }
}

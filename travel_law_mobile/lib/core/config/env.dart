/// Credenciales públicas de Supabase, inyectadas al compilar con
/// --dart-define-from-file=env.json (el archivo env.json NO se sube a Git).
///
/// Usa la URL del proyecto y la clave pública (anon / publishable).
/// NUNCA pongas aquí la clave service_role ni la contraseña de la base de datos.
class Env {
  const Env._();

  static const String supabaseUrl = String.fromEnvironment('SUPABASE_URL');
  static const String supabaseAnonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
  );

  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}

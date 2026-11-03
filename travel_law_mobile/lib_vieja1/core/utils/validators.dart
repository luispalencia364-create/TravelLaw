/// Validaciones en tiempo real de los formularios (RI-01).
class Validators {
  const Validators._();

  static final RegExp _emailRegex = RegExp(
    r'^[A-Za-z0-9._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$',
  );

  static String? email(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu correo electrónico.';
    if (!_emailRegex.hasMatch(v)) {
      return 'El formato del correo no es válido (ej. nombre@correo.com).';
    }
    return null;
  }

  static String? nombre(String? value) {
    final v = value?.trim() ?? '';
    if (v.isEmpty) return 'Ingresa tu nombre.';
    if (v.length < 2) return 'El nombre es demasiado corto.';
    return null;
  }

  /// Contraseña obligatoria al iniciar sesión (sin reglas de formato).
  static String? passwordRequired(String? value) {
    if ((value ?? '').isEmpty) return 'Ingresa tu contraseña.';
    return null;
  }

  /// Regla para crear una contraseña nueva.
  static String? newPassword(String? value) {
    final v = value ?? '';
    if (v.isEmpty) return 'Crea una contraseña.';
    if (v.length < 8) return 'Debe tener al menos 8 caracteres.';
    if (!RegExp(r'[A-Za-z]').hasMatch(v) || !RegExp(r'[0-9]').hasMatch(v)) {
      return 'Debe incluir letras y números.';
    }
    return null;
  }
}

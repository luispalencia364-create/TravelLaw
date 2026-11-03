import 'package:supabase_flutter/supabase_flutter.dart';

/// Convierte errores de autenticación en mensajes descriptivos en español.
String authErrorMessage(Object error) {
  if (error is AuthException) {
    switch (error.code) {
      case 'invalid_credentials':
        return 'Correo o contraseña incorrectos.';
      case 'email_not_confirmed':
        return 'Debes confirmar tu correo antes de iniciar sesión. '
            'Revisa tu bandeja de entrada.';
      case 'user_already_exists':
      case 'email_exists':
        return 'Ya existe una cuenta con ese correo.';
      case 'weak_password':
        return 'La contraseña es demasiado débil. Usa una más larga y variada.';
      case 'over_email_send_rate_limit':
      case 'over_request_rate_limit':
        return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
      case 'signup_disabled':
        return 'El registro está deshabilitado por el momento.';
    }

    final m = error.message.toLowerCase();
    if (m.contains('invalid login')) return 'Correo o contraseña incorrectos.';
    if (m.contains('already registered')) {
      return 'Ya existe una cuenta con ese correo.';
    }
    if (m.contains('email not confirmed')) {
      return 'Debes confirmar tu correo antes de iniciar sesión.';
    }
    if (m.contains('rate limit')) {
      return 'Demasiados intentos. Espera unos minutos e inténtalo de nuevo.';
    }
    if (m.contains('database error')) {
      return 'No se pudo crear tu perfil. Inténtalo de nuevo más tarde.';
    }
  }

  final text = error.toString();
  if (text.contains('SocketException') ||
      text.contains('ClientException') ||
      text.contains('Failed host lookup')) {
    return 'Sin conexión a internet. Revisa tu red e inténtalo de nuevo.';
  }
  return 'No se pudo completar la operación. Inténtalo de nuevo.';
}

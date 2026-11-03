import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../features/alertas/presentation/alertas_page.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/presentation/forgot_password_page.dart';
import '../features/auth/presentation/login_page.dart';
import '../features/auth/presentation/register_page.dart';
import '../features/comunidad/presentation/comunidad_page.dart';
import '../features/configuracion/presentation/configuracion_page.dart';
import '../features/cultura/presentation/cultura_page.dart';
import '../features/descargas/presentation/descargas_page.dart';
import '../features/home/presentation/home_page.dart';
import '../features/legal/presentation/legal_page.dart';
import '../features/orientacion/presentation/orientacion_page.dart';
import '../features/precios/presentation/precios_page.dart';
import '../features/sos/presentation/sos_page.dart';
import 'rutas.dart';

/// Avisa a go_router cada vez que cambia la sesión para reevaluar el redirect.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _subscription = stream.listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

const _rutasPublicas = {'/login', '/registro', '/recuperar'};

final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final refresh = _AuthRefresh(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    initialLocation: '/',
    refreshListenable: refresh,
    redirect: (context, state) {
      final haySesion = client.auth.currentSession != null;
      final enRutaPublica = _rutasPublicas.contains(state.matchedLocation);

      if (!haySesion && !enRutaPublica) return '/login';
      if (haySesion && enRutaPublica) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/', builder: (context, state) => const HomePage()),
      GoRoute(path: '/login', builder: (context, state) => const LoginPage()),
      GoRoute(
        path: '/registro',
        builder: (context, state) => const RegisterPage(),
      ),
      GoRoute(
        path: '/recuperar',
        builder: (context, state) => const ForgotPasswordPage(),
      ),
      GoRoute(
        path: Rutas.legal,
        builder: (context, state) => const LegalPage(),
      ),
      GoRoute(
        path: Rutas.cultura,
        builder: (context, state) => const CulturaPage(),
      ),
      GoRoute(
        path: Rutas.alertas,
        builder: (context, state) => const AlertasPage(),
      ),
      GoRoute(
        path: Rutas.precios,
        builder: (context, state) => const PreciosPage(),
      ),
      GoRoute(
        path: Rutas.comunidad,
        builder: (context, state) => const ComunidadPage(),
      ),
      GoRoute(
        path: Rutas.orientacion,
        builder: (context, state) => const OrientacionPage(),
      ),
      GoRoute(
        path: Rutas.descargas,
        builder: (context, state) => const DescargasPage(),
      ),
      GoRoute(path: Rutas.sos, builder: (context, state) => const SosPage()),
      GoRoute(
        path: Rutas.configuracion,
        builder: (context, state) => const ConfiguracionPage(),
      ),
    ],
  );
});

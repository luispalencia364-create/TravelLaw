import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../features/auth/data/auth_repository.dart';
import '../features/auth/data/perfil_provider.dart';
import '../features/auth/presentation/cuenta_suspendida_page.dart';
import 'router.dart';

class TravelLawApp extends ConsumerStatefulWidget {
  const TravelLawApp({super.key});

  @override
  ConsumerState<TravelLawApp> createState() => _TravelLawAppState();
}

class _TravelLawAppState extends ConsumerState<TravelLawApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Al volver a la app se revisa el perfil: si un administrador suspendió
    // la cuenta mientras estaba en segundo plano, se bloquea el acceso.
    if (state == AppLifecycleState.resumed) {
      ref.invalidate(perfilProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(routerProvider);
    final client = ref.watch(supabaseProvider);

    // Se observa el estado de autenticación para reconstruir la app cuando
    // cambia la sesión (y así evaluar una posible suspensión).
    ref.watch(authStateProvider);
    final haySesion = client.auth.currentSession != null;

    final perfil = haySesion ? ref.watch(perfilProvider) : null;
    final perfilActual = perfil?.value;
    final suspendido =
        perfilActual != null && perfilActual.estado != 'activo';

    if (suspendido) {
      return MaterialApp(
        title: 'TravelLaw',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: ThemeMode.system,
        home: const CuentaSuspendidaPage(),
      );
    }

    return MaterialApp.router(
      title: 'TravelLaw',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ThemeMode.system,
      routerConfig: router,
    );
  }
}

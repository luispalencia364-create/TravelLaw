import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/perfil_provider.dart';

/// Menú lateral con los módulos de TravelLaw.
/// Los módulos aún no implementados muestran "próximamente".
class AppDrawer extends ConsumerWidget {
  const AppDrawer({super.key, required this.onPerfil});

  /// Abre la hoja de perfil (la ejecuta la pantalla principal).
  final VoidCallback onPerfil;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider);
    final p = perfil.when(
      skipLoadingOnReload: true,
      data: (v) => v,
      loading: () => null,
      error: (_, __) => null,
    );

    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          UserAccountsDrawerHeader(
            accountName: Text(p?.nombre ?? 'TravelLaw'),
            accountEmail: Text(
              p == null ? '' : '${p.email}  ·  ${p.rolEtiqueta}',
            ),
            currentAccountPicture: CircleAvatar(child: Text(p?.inicial ?? 'T')),
          ),
          ListTile(
            leading: const Icon(Icons.home_outlined),
            title: const Text('Inicio y mapa'),
            selected: true,
            onTap: () => Navigator.of(context).pop(),
          ),
          _modulo(context, Icons.gavel_outlined, 'Legal y normativa'),
          _modulo(context, Icons.translate, 'Cultura y traductor'),
          _modulo(context, Icons.warning_amber_outlined, 'Alertas y reportes'),
          _modulo(context, Icons.request_quote_outlined, 'Precios y cobros'),
          _modulo(context, Icons.groups_outlined, 'Comunidad de viajeros'),
          _modulo(context, Icons.help_outline, 'Centro de orientación'),
          _modulo(
            context,
            Icons.download_for_offline_outlined,
            'Descargas offline',
          ),
          _modulo(context, Icons.sos_outlined, 'Emergencias (SOS)'),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Mi perfil'),
            onTap: () {
              Navigator.of(context).pop();
              onPerfil();
            },
          ),
          _modulo(context, Icons.settings_outlined, 'Configuración e idioma'),
          ListTile(
            leading: const Icon(Icons.logout),
            title: const Text('Cerrar sesión'),
            onTap: () {
              final repo = ref.read(authRepositoryProvider);
              Navigator.of(context).pop();
              repo.signOut();
            },
          ),
        ],
      ),
    );
  }

  Widget _modulo(BuildContext context, IconData icono, String nombre) {
    return ListTile(
      leading: Icon(icono),
      title: Text(nombre),
      onTap: () {
        final messenger = ScaffoldMessenger.of(context);
        Navigator.of(context).pop();
        messenger
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(content: Text('$nombre: disponible próximamente.')),
          );
      },
    );
  }
}

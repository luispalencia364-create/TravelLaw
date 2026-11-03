import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../auth/data/auth_repository.dart';
import '../../../auth/data/perfil_provider.dart';

/// Hoja inferior con todos los datos del usuario.
class PerfilSheet extends ConsumerWidget {
  const PerfilSheet({super.key});

  String _fecha(DateTime? d) {
    if (d == null) return '—';
    return '${d.day.toString().padLeft(2, '0')}/'
        '${d.month.toString().padLeft(2, '0')}/${d.year}';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: perfil.when(
          skipLoadingOnReload: true,
          loading: () => const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          ),
          error: (e, _) => Padding(
            padding: const EdgeInsets.all(16),
            child: Text('No se pudo cargar tu perfil: $e'),
          ),
          data: (p) {
            if (p == null) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Text('No hay un perfil disponible.'),
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: CircleAvatar(
                    radius: 32,
                    child: Text(
                      p.inicial,
                      style: Theme.of(context).textTheme.headlineMedium,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  p.nombre,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                _Dato(Icons.email_outlined, 'Correo', p.email),
                _Dato(Icons.badge_outlined, 'Rol', p.rolEtiqueta),
                _Dato(Icons.language, 'Idioma', p.idiomaEtiqueta),
                _Dato(Icons.verified_user_outlined, 'Estado', p.estadoEtiqueta),
                _Dato(
                  Icons.calendar_today_outlined,
                  'Miembro desde',
                  _fecha(p.fechaRegistro),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  icon: const Icon(Icons.logout),
                  label: const Text('Cerrar sesión'),
                  onPressed: () {
                    // Se captura antes de cerrar la hoja: después ya no hay ref.
                    final repo = ref.read(authRepositoryProvider);
                    Navigator.of(context).pop();
                    repo.signOut();
                  },
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Dato extends StatelessWidget {
  const _Dato(this.icono, this.etiqueta, this.valor);

  final IconData icono;
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(icono),
      title: Text(etiqueta, style: Theme.of(context).textTheme.bodySmall),
      subtitle: Text(valor, style: Theme.of(context).textTheme.bodyLarge),
    );
  }
}

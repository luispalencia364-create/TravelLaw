import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/perfil_provider.dart';

class ConfiguracionPage extends ConsumerStatefulWidget {
  const ConfiguracionPage({super.key});

  @override
  ConsumerState<ConfiguracionPage> createState() => _ConfiguracionPageState();
}

class _ConfiguracionPageState extends ConsumerState<ConfiguracionPage> {
  bool _guardando = false;

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _cambiarIdioma(String idioma) async {
    setState(() => _guardando = true);
    try {
      final client = ref.read(supabaseProvider);
      final uid = client.auth.currentUser?.id;
      if (uid == null) return;
      await client
          .from('usuario')
          .update({'idioma': idioma})
          .eq('id_usuario', uid);
      ref.invalidate(perfilProvider);
      _mensaje(idioma == 'en' ? 'Language saved.' : 'Idioma guardado.');
    } catch (_) {
      _mensaje('No se pudo guardar. Revisa tu conexión.');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final idioma = ref.watch(idiomaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Configuración e idioma')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Idioma del contenido',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          const Text(
            'Normas, guías y expresiones se muestran en este idioma cuando '
            'hay traducción disponible.',
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'es', label: Text('Español')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {idioma},
            onSelectionChanged: _guardando
                ? null
                : (s) => _cambiarIdioma(s.first),
          ),
          if (_guardando) ...[
            const SizedBox(height: 12),
            const LinearProgressIndicator(),
          ],
          const SizedBox(height: 24),
          const Text(
            'La interfaz de la app (menús y botones) se traducirá en una '
            'próxima versión.',
          ),
        ],
      ),
    );
  }
}

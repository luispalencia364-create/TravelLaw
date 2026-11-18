import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../../destinos/data/destinos_repository.dart';
import '../data/comunidad_repository.dart';

/// Formulario para que un viajero publique una recomendación o experiencia
/// en el feed de la comunidad del destino.
class CrearPublicacionDialog extends ConsumerStatefulWidget {
  const CrearPublicacionDialog({super.key, required this.destino});

  final Destino destino;

  @override
  ConsumerState<CrearPublicacionDialog> createState() =>
      _CrearPublicacionDialogState();
}

class _CrearPublicacionDialogState
    extends ConsumerState<CrearPublicacionDialog> {
  final _form = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      final client = ref.read(supabaseProvider);
      final uid = client.auth.currentUser?.id;
      if (uid == null) {
        throw StateError('Sesión no disponible');
      }
      await client.from('publicacion').insert({
        'id_usuario': uid,
        'id_destino': widget.destino.id,
        'descripcion': _descripcion.text.trim(),
        'estado': 'publicada',
      });
      if (!mounted) return;
      ref.invalidate(publicacionesProvider(widget.destino.id));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error =
            'No se pudo publicar. Verifica tu conexión e inténtalo de '
            'nuevo.';
      });
      debugPrint('Error al crear publicación: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Nueva publicación'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Destino: ${widget.destino.nombre}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcion,
                decoration: const InputDecoration(
                  labelText: '¿Qué quieres compartir?',
                  alignLabelWithHint: true,
                  hintText: 'Recomendaciones, experiencias, consejos…',
                ),
                maxLines: 5,
                maxLength: 1000,
                enabled: !_guardando,
                validator: (v) {
                  final texto = v?.trim() ?? '';
                  if (texto.length < 10) {
                    return 'Escribe al menos 10 caracteres.';
                  }
                  return null;
                },
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: scheme.error)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _guardando ? null : () => Navigator.pop(context, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _guardando ? null : _guardar,
          child: _guardando
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Publicar'),
        ),
      ],
    );
  }
}

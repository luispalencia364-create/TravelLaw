import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../destinos/data/destinos_repository.dart';
import '../data/comunidad_repository.dart';

/// Formulario para que un viajero publique una recomendación o experiencia
/// en el feed de la comunidad del destino, con fotos opcionales.
class CrearPublicacionDialog extends ConsumerStatefulWidget {
  const CrearPublicacionDialog({super.key, required this.destino});

  final Destino destino;

  @override
  ConsumerState<CrearPublicacionDialog> createState() =>
      _CrearPublicacionDialogState();
}

class _CrearPublicacionDialogState
    extends ConsumerState<CrearPublicacionDialog> {
  static const _maxFotos = 5;

  final _form = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  final List<_FotoSeleccionada> _fotos = [];
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirFotos() async {
    final restantes = _maxFotos - _fotos.length;
    if (restantes <= 0) return;

    try {
      final picker = ImagePicker();
      final seleccionadas = await picker.pickMultiImage(
        imageQuality: 85,
        maxWidth: 1600,
        maxHeight: 1600,
      );
      if (!mounted || seleccionadas.isEmpty) return;

      final nuevas = <_FotoSeleccionada>[];
      for (final file in seleccionadas.take(restantes)) {
        final bytes = await file.readAsBytes();
        nuevas.add(_FotoSeleccionada(file: file, bytes: bytes));
      }
      if (!mounted) return;
      setState(() {
        _fotos.addAll(nuevas);
        _error = null;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = 'No se pudieron cargar las fotos seleccionadas.';
        });
      }
      debugPrint('Error al elegir fotos: $e');
    }
  }

  void _quitarFoto(int index) {
    setState(() => _fotos.removeAt(index));
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await ref
          .read(comunidadRepositoryProvider)
          .crearPublicacion(
            widget.destino.id,
            _descripcion.text.trim(),
            _fotos.map((f) => f.file).toList(),
          );
      if (!mounted) return;
      ref.invalidate(comunidadFeedProvider);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _error =
              'No se pudo publicar. Verifica tu conexión e inténtalo de '
              'nuevo.';
        });
      }
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
              const SizedBox(height: 4),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Fotos (${_fotos.length}/$_maxFotos)',
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _guardando || _fotos.length >= _maxFotos
                        ? null
                        : _elegirFotos,
                    icon: const Icon(Icons.add_a_photo_outlined, size: 18),
                    label: const Text('Añadir'),
                  ),
                ],
              ),
              if (_fotos.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: 92,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _fotos.length,
                    separatorBuilder: (_, _) => const SizedBox(width: 8),
                    itemBuilder: (context, i) => _MiniaturaFoto(
                      foto: _fotos[i],
                      habilitado: !_guardando,
                      onRemove: () => _quitarFoto(i),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Text(
                'Puedes adjuntar hasta $_maxFotos fotos. Se optimizan '
                'automáticamente antes de subirlas.',
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: scheme.outline),
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
              ? SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Theme.of(context).colorScheme.onPrimary,
                  ),
                )
              : const Text('Publicar'),
        ),
      ],
    );
  }
}

class _FotoSeleccionada {
  const _FotoSeleccionada({required this.file, required this.bytes});

  final XFile file;
  final Uint8List bytes;
}

class _MiniaturaFoto extends StatelessWidget {
  const _MiniaturaFoto({
    required this.foto,
    required this.onRemove,
    required this.habilitado,
  });

  final _FotoSeleccionada foto;
  final VoidCallback onRemove;
  final bool habilitado;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 92,
      height: 92,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Image.memory(foto.bytes, fit: BoxFit.cover),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: IconButton.filled(
              visualDensity: VisualDensity.compact,
              tooltip: 'Quitar foto',
              onPressed: habilitado ? onRemove : null,
              icon: const Icon(Icons.close, size: 16),
            ),
          ),
        ],
      ),
    );
  }
}

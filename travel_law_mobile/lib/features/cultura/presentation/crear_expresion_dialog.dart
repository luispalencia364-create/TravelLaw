import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../destinos/data/destinos_repository.dart';
import '../data/cultura_repository.dart';

class CrearExpresionDialog extends ConsumerStatefulWidget {
  const CrearExpresionDialog({super.key, required this.destino});

  final Destino destino;

  @override
  ConsumerState<CrearExpresionDialog> createState() =>
      _CrearExpresionDialogState();
}

class _CrearExpresionDialogState extends ConsumerState<CrearExpresionDialog> {
  final _form = GlobalKey<FormState>();
  final _expresion = TextEditingController();
  final _significadoEs = TextEditingController();
  final _significadoEn = TextEditingController();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _expresion.dispose();
    _significadoEs.dispose();
    _significadoEn.dispose();
    super.dispose();
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    setState(() {
      _guardando = true;
      _error = null;
    });
    try {
      await crearExpresion(
        ref,
        widget.destino.id,
        _expresion.text.trim(),
        _significadoEs.text.trim(),
        _significadoEn.text.trim().isEmpty ? null : _significadoEn.text.trim(),
      );
      if (!mounted) return;
      ref.invalidate(expresionesProvider(widget.destino.id));
      ref.invalidate(expresionesPendientesProvider);
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'No se pudo crear la expresión: $e');
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Nueva expresión cultural'),
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
                controller: _expresion,
                decoration: const InputDecoration(
                  labelText: 'Expresión local',
                ),
                enabled: !_guardando,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _significadoEs,
                decoration: const InputDecoration(
                  labelText: 'Significado (español)',
                ),
                maxLines: 3,
                enabled: !_guardando,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _significadoEn,
                decoration: const InputDecoration(
                  labelText: 'Significado (inglés, opcional)',
                ),
                maxLines: 3,
                enabled: !_guardando,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              : const Text('Enviar'),
        ),
      ],
    );
  }
}
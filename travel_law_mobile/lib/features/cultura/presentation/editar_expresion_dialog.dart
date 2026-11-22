import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/data/auth_repository.dart';
import '../data/cultura_repository.dart';

class EditarExpresionDialog extends ConsumerStatefulWidget {
  const EditarExpresionDialog({super.key, required this.expresion});

  final Expresion expresion;

  @override
  ConsumerState<EditarExpresionDialog> createState() =>
      _EditarExpresionDialogState();
}

class _EditarExpresionDialogState extends ConsumerState<EditarExpresionDialog> {
  final _form = GlobalKey<FormState>();
  late final TextEditingController _expresion;
  late final TextEditingController _significadoEs;
  late final TextEditingController _significadoEn;
  bool _guardando = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _expresion = TextEditingController(text: widget.expresion.expresion);
    _significadoEs =
        TextEditingController(text: widget.expresion.significadoEs);
    _significadoEn =
        TextEditingController(text: widget.expresion.significadoEn ?? '');
  }

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
      await ref.read(supabaseProvider).from('expresion_cultural').update({
        'expresion': _expresion.text.trim(),
        'significado_es': _significadoEs.text.trim(),
        'significado_en': _significadoEn.text.trim().isEmpty
            ? null
            : _significadoEn.text.trim(),
      }).eq('id_expresion', widget.expresion.id);
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => _error = 'No se pudo actualizar: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Editar expresión'),
      content: Form(
        key: _form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _expresion,
                decoration: const InputDecoration(labelText: 'Expresión local'),
                enabled: !_guardando,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _significadoEs,
                decoration:
                    const InputDecoration(labelText: 'Significado (español)'),
                maxLines: 3,
                enabled: !_guardando,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Requerido' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _significadoEn,
                decoration:
                    const InputDecoration(labelText: 'Significado (inglés, opcional)'),
                maxLines: 3,
                enabled: !_guardando,
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!,
                    style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
              : const Text('Guardar'),
        ),
      ],
    );
  }
}
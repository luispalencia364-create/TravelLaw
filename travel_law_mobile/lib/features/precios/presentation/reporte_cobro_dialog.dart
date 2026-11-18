import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../destinos/data/destinos_repository.dart';
import '../data/precios_repository.dart';

/// Formulario para que un viajero reporte un cobro abusivo.
///
/// El reporte se inserta con estado `pendiente_revision` y queda visible
/// solo para su autor y para el staff hasta que sea revisado.
class ReporteCobroDialog extends ConsumerStatefulWidget {
  const ReporteCobroDialog({super.key, required this.destino});

  final Destino destino;

  @override
  ConsumerState<ReporteCobroDialog> createState() => _ReporteCobroDialogState();
}

class _ReporteCobroDialogState extends ConsumerState<ReporteCobroDialog> {
  final _form = GlobalKey<FormState>();
  final _servicio = TextEditingController();
  final _precio = TextEditingController();
  DateTime _fecha = DateTime.now();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _servicio.dispose();
    _precio.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fecha,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      helpText: 'Fecha del cobro',
    );
    if (fecha == null || !mounted) return;
    setState(() => _fecha = fecha);
  }

  double? _parsePrecio(String texto) {
    final limpio = texto.trim().replaceAll(RegExp(r'[^0-9.,]'), '');
    if (limpio.isEmpty) return null;
    final normalizado = limpio.replaceAll('.', '').replaceAll(',', '.');
    return double.tryParse(normalizado);
  }

  Future<void> _guardar() async {
    if (!_form.currentState!.validate()) return;
    final precio = _parsePrecio(_precio.text);
    if (precio == null) return;
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
      await client.from('reporte_cobro').insert({
        'id_usuario': uid,
        'id_destino': widget.destino.id,
        'servicio': _servicio.text.trim(),
        'precio_pagado': precio,
        'fecha': _fecha.toUtc().toIso8601String(),
        'ubicacion':
            'POINT(${widget.destino.posicion.longitude} '
            '${widget.destino.posicion.latitude})',
        'estado': 'pendiente_revision',
      });
      if (!mounted) return;
      ref.invalidate(misReportesCobroProvider);
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error =
            'No se pudo enviar el reporte. Verifica tu conexión e '
            'inténtalo de nuevo.';
      });
      debugPrint('Error al crear reporte de cobro: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Reportar cobro'),
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
                controller: _servicio,
                decoration: const InputDecoration(
                  labelText: 'Servicio o producto',
                  prefixIcon: Icon(Icons.storefront_outlined),
                  hintText: 'Taxi, restaurante, tour…',
                ),
                maxLength: 150,
                enabled: !_guardando,
                validator: (v) {
                  if ((v?.trim().isEmpty ?? true)) {
                    return 'Indica el servicio o producto.';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _precio,
                decoration: const InputDecoration(
                  labelText: 'Precio que te cobraron',
                  prefixIcon: Icon(Icons.payments_outlined),
                  hintText: 'Ej: 25000',
                ),
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                enabled: !_guardando,
                validator: (v) {
                  final precio = _parsePrecio(v ?? '');
                  if (precio == null || precio <= 0) {
                    return 'Escribe un precio válido.';
                  }
                  return null;
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Fecha del cobro'),
                subtitle: Text(formatearFecha(_fecha)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _guardando ? null : _elegirFecha,
              ),
              const SizedBox(height: 4),
              Text(
                'Tu reporte quedará en revisión y solo tú y el equipo de '
                'moderación podrán verlo.',
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

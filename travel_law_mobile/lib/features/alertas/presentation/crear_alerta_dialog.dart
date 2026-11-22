import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destinos_repository.dart';
import '../data/alertas_repository.dart';

/// Formulario para que cualquier viajero reporte una alerta.
///
/// La alerta se inserta con estado `pendiente_moderacion`: no se publica
/// hasta que un moderador o administrador la verifique desde el panel.
class CrearAlertaDialog extends ConsumerStatefulWidget {
  const CrearAlertaDialog({super.key, required this.destino});

  final Destino destino;

  @override
  ConsumerState<CrearAlertaDialog> createState() => _CrearAlertaDialogState();
}

class _CrearAlertaDialogState extends ConsumerState<CrearAlertaDialog> {
  static const _tipos = {
    'riesgo': 'Riesgo',
    'emergencia': 'Emergencia',
    'cierre_vial': 'Cierre vial',
    'clima': 'Clima',
    'otro': 'Otro',
  };

  final _form = GlobalKey<FormState>();
  final _descripcion = TextEditingController();
  String _tipo = 'riesgo';
  DateTime _fechaEvento = DateTime.now();
  bool _guardando = false;
  String? _error;

  @override
  void dispose() {
    _descripcion.dispose();
    super.dispose();
  }

  Future<void> _elegirFecha() async {
    final fecha = await showDatePicker(
      context: context,
      initialDate: _fechaEvento,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 30)),
      helpText: 'Fecha del evento',
    );
    if (fecha == null || !mounted) return;
    setState(() {
      _fechaEvento = DateTime(
        fecha.year,
        fecha.month,
        fecha.day,
        _fechaEvento.hour,
        _fechaEvento.minute,
      );
    });
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
      await client.from('alerta').insert({
        'id_usuario': uid,
        'id_destino': widget.destino.id,
        'tipo': _tipo,
        'descripcion': _descripcion.text.trim(),
        'fecha_evento': _fechaEvento.toUtc().toIso8601String(),
        'ubicacion':
            'POINT(${widget.destino.posicion.longitude} '
            '${widget.destino.posicion.latitude})',
        'estado': (ref.read(perfilProvider).asData?.value?.esModerador == true ||
            ref.read(perfilProvider).asData?.value?.esAdministrador == true)
            ? 'verificada'
            : 'pendiente_moderacion',
      });
      if (!mounted) return;
      ref.invalidate(misAlertasProvider);
      ref.invalidate(alertasDestinoProvider(widget.destino.id));
      Navigator.pop(context, true);
    } catch (e) {
      setState(() {
        _error =
            'No se pudo enviar la alerta. Verifica tu conexión e '
            'inténtalo de nuevo.';
      });
      debugPrint('Error al crear alerta: $e');
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Reportar alerta'),
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
              DropdownButtonFormField<String>(
                initialValue: _tipo,
                decoration: const InputDecoration(
                  labelText: 'Tipo de alerta',
                  prefixIcon: Icon(Icons.warning_amber_outlined),
                ),
                items: [
                  for (final e in _tipos.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: _guardando
                    ? null
                    : (v) => setState(() => _tipo = v ?? 'riesgo'),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _descripcion,
                decoration: const InputDecoration(
                  labelText: 'Descripción',
                  alignLabelWithHint: true,
                  hintText: '¿Qué está pasando y en qué lugar exacto?',
                ),
                maxLines: 4,
                maxLength: 500,
                enabled: !_guardando,
                validator: (v) {
                  final texto = v?.trim() ?? '';
                  if (texto.length < 10) {
                    return 'Describe la situación (mínimo 10 caracteres).';
                  }
                  return null;
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.event_outlined),
                title: const Text('Fecha del evento'),
                subtitle: Text(formatearFecha(_fechaEvento)),
                trailing: const Icon(Icons.edit_calendar_outlined),
                onTap: _guardando ? null : _elegirFecha,
              ),
              const SizedBox(height: 4),
              Text(
                'La alerta quedará pendiente de revisión por un moderador '
                'antes de publicarse.',
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/sos_repository.dart';

class SosPage extends ConsumerWidget {
  const SosPage({super.key});

  /// RN-05: pide confirmación y abre el marcador del teléfono (no llama solo).
  Future<void> _llamar(BuildContext context, ContactoEmergencia c) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        icon: const Icon(Icons.phone_in_talk_outlined),
        title: Text('Llamar a ${c.entidad}'),
        content: Text('Se abrirá el marcador con el número ${c.telefono}.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir marcador'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    final abierto = await launchUrl(Uri(scheme: 'tel', path: c.telefono));
    if (!abierto && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No se pudo abrir el marcador del teléfono.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Emergencias (SOS)'),
        backgroundColor: scheme.errorContainer,
        foregroundColor: scheme.onErrorContainer,
      ),
      body: ConDestino(
        builder: (context, destino) => Consumer(
          builder: (context, ref, _) => AsyncListView<ContactoEmergencia>(
            value: ref.watch(contactosProvider(destino.id)),
            emptyIcon: Icons.sos_outlined,
            emptyMessage: 'Sin contactos de emergencia en ${destino.nombre}',
            onRefresh: () async {
              await ref.refresh(contactosProvider(destino.id).future);
            },
            itemBuilder: (context, c) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                leading: Icon(Icons.local_phone_outlined, color: scheme.error),
                title: Text(c.entidad),
                subtitle: Text(
                  [
                    c.telefono,
                    if (c.direccion != null && c.direccion!.isNotEmpty)
                      c.direccion!,
                    if (c.fuente != null && c.fuente!.isNotEmpty)
                      'Fuente: ${c.fuente}  ·  ${formatearFecha(c.fechaActualizacion)}',
                  ].join('\n'),
                ),
                isThreeLine: true,
                trailing: IconButton.filled(
                  tooltip: 'Llamar',
                  style: IconButton.styleFrom(backgroundColor: scheme.error),
                  icon: const Icon(Icons.call),
                  onPressed: () => _llamar(context, c),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

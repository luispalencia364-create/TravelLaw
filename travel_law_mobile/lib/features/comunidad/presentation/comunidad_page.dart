import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/comunidad_repository.dart';
import 'crear_publicacion_dialog.dart';

class ComunidadPage extends ConsumerWidget {
  const ComunidadPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).asData?.value;
    final destino = ref.watch(destinoEfectivoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad de viajeros')),
      floatingActionButton: perfil != null && destino != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final creada = await showDialog<bool>(
                  context: context,
                  builder: (_) => CrearPublicacionDialog(destino: destino),
                );
                if (creada == true && context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        '¡Publicación compartida con la comunidad!',
                      ),
                    ),
                  );
                }
              },
              icon: const Icon(Icons.edit_outlined),
              label: const Text('Publicar'),
            )
          : null,
      body: ConDestino(
        builder: (context, destino) => Consumer(
          builder: (context, ref, _) => AsyncListView<Publicacion>(
            value: ref.watch(publicacionesProvider(destino.id)),
            emptyIcon: Icons.groups_outlined,
            emptyMessage: 'Sin publicaciones en ${destino.nombre}',
            emptyDetail:
                'Aquí verás recomendaciones y fotos de otros viajeros.',
            onRefresh: () async {
              ref.invalidate(publicacionesProvider(destino.id));
              await ref.read(publicacionesProvider(destino.id).future);
            },
            itemBuilder: (context, p) => Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        CircleAvatar(
                          radius: 16,
                          child: Text(
                            p.autor.isEmpty ? '?' : p.autor[0].toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            p.autor,
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        Text(
                          fechaRelativa(p.fecha),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(p.descripcion),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

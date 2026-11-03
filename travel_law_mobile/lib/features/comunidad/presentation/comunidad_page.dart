import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/comunidad_repository.dart';

class ComunidadPage extends StatelessWidget {
  const ComunidadPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad de viajeros')),
      body: ConDestino(
        builder: (context, destino) => Consumer(
          builder: (context, ref, _) => AsyncListView<Publicacion>(
            value: ref.watch(publicacionesProvider(destino.id)),
            emptyIcon: Icons.groups_outlined,
            emptyMessage: 'Sin publicaciones en ${destino.nombre}',
            emptyDetail:
                'Aquí verás recomendaciones y fotos de otros viajeros.',
            onRefresh: () async {
              await ref.refresh(publicacionesProvider(destino.id).future);
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

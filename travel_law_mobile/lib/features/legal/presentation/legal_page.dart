import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destinos_repository.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/legal_repository.dart';

class LegalPage extends StatelessWidget {
  const LegalPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Legal y normativa'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Normas'),
              Tab(text: 'Zonas restringidas'),
            ],
          ),
        ),
        body: ConDestino(
          builder: (context, destino) => TabBarView(
            children: [
              _NormasTab(destino: destino),
              _ZonasTab(destino: destino),
            ],
          ),
        ),
      ),
    );
  }
}

class _NormasTab extends ConsumerWidget {
  const _NormasTab({required this.destino});

  final Destino destino;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idioma = ref.watch(idiomaProvider);
    final normas = ref.watch(normasProvider(destino.id));

    return AsyncListView<Norma>(
      value: normas,
      emptyIcon: Icons.gavel_outlined,
      emptyMessage: 'Sin normas registradas para ${destino.nombre}',
      onRefresh: () async {
        await ref.refresh(normasProvider(destino.id).future);
      },
      itemBuilder: (context, n) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ExpansionTile(
          shape: const Border(),
          collapsedShape: const Border(),
          title: Text(textoIdioma(idioma, n.tituloEs, n.tituloEn)),
          subtitle: Text(
            '${capitalizar(n.tipo)}  ·  Actualizado ${formatearFecha(n.fechaActualizacion)}',
          ),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          expandedCrossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(textoIdioma(idioma, n.contenidoEs, n.contenidoEn)),
            if (n.fuente != null && n.fuente!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Fuente: ${n.fuente}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ZonasTab extends ConsumerWidget {
  const _ZonasTab({required this.destino});

  final Destino destino;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final idioma = ref.watch(idiomaProvider);
    final zonas = ref.watch(zonasProvider(destino.id));

    return AsyncListView<ZonaRestringida>(
      value: zonas,
      emptyIcon: Icons.block_outlined,
      emptyMessage: 'Sin zonas restringidas en ${destino.nombre}',
      onRefresh: () async {
        await ref.refresh(zonasProvider(destino.id).future);
      },
      itemBuilder: (context, z) => Card(
        margin: const EdgeInsets.only(bottom: 8),
        child: ListTile(
          leading: const Icon(Icons.block_outlined),
          title: Text(z.nombre),
          subtitle: Text(
            z.normaEs == null
                ? 'Sin norma asociada'
                : 'Norma: ${textoIdioma(idioma, z.normaEs!, z.normaEn)}',
          ),
        ),
      ),
    );
  }
}

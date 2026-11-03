import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/cultura_repository.dart';

class CulturaPage extends ConsumerStatefulWidget {
  const CulturaPage({super.key});

  @override
  ConsumerState<CulturaPage> createState() => _CulturaPageState();
}

class _CulturaPageState extends ConsumerState<CulturaPage> {
  String _consulta = '';

  @override
  Widget build(BuildContext context) {
    final idioma = ref.watch(idiomaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Cultura y traductor')),
      body: ConDestino(
        builder: (context, destino) => Consumer(
          builder: (context, ref, _) {
            final expresiones = ref.watch(expresionesProvider(destino.id));
            final q = normalizar(_consulta.trim());
            final filtradas = expresiones.whenData(
              (lista) => q.isEmpty
                  ? lista
                  : lista
                        .where(
                          (e) => normalizar(
                            '${e.expresion} ${e.significadoEs} ${e.significadoEn ?? ''}',
                          ).contains(q),
                        )
                        .toList(),
            );

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    onChanged: (v) => setState(() => _consulta = v),
                    decoration: InputDecoration(
                      hintText: 'Busca una expresión local',
                      prefixIcon: const Icon(Icons.translate),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: AsyncListView<Expresion>(
                    value: filtradas,
                    emptyIcon: Icons.translate,
                    emptyMessage: q.isEmpty
                        ? 'Sin expresiones culturales en ${destino.nombre}'
                        : 'Sin resultados para "$_consulta"',
                    onRefresh: () async {
                      await ref.refresh(expresionesProvider(destino.id).future);
                    },
                    itemBuilder: (context, e) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(e.expresion),
                        subtitle: Text(
                          textoIdioma(idioma, e.significadoEs, e.significadoEn),
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/orientacion_repository.dart';

const _categorias = ['Legal', 'Cultural', 'Cobros', 'Seguridad'];

/// Centro de orientación (RI-05): búsqueda, categorías y acordeones.
class OrientacionPage extends ConsumerStatefulWidget {
  const OrientacionPage({super.key});

  @override
  ConsumerState<OrientacionPage> createState() => _OrientacionPageState();
}

class _OrientacionPageState extends ConsumerState<OrientacionPage> {
  String _consulta = '';
  String? _categoria; // null = todas

  @override
  Widget build(BuildContext context) {
    final idioma = ref.watch(idiomaProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Centro de orientación')),
      body: ConDestino(
        builder: (context, destino) => Consumer(
          builder: (context, ref, _) {
            final guias = ref.watch(guiasProvider(destino.id));
            final q = normalizar(_consulta.trim());
            final filtradas = guias.whenData(
              (lista) => lista.where((g) {
                if (_categoria != null && g.categoria != _categoria)
                  return false;
                if (q.isEmpty) return true;
                final texto = normalizar(
                  '${g.tituloEs} ${g.tituloEn ?? ''} ${g.contenidoEs} ${g.contenidoEn ?? ''}',
                );
                return texto.contains(q);
              }).toList(),
            );
            final hayFiltro = q.isNotEmpty || _categoria != null;

            return Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  child: TextField(
                    onChanged: (v) => setState(() => _consulta = v),
                    decoration: InputDecoration(
                      hintText: 'Buscar en guías y preguntas frecuentes',
                      prefixIcon: const Icon(Icons.search),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  height: 52,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: ChoiceChip(
                          label: const Text('Todas'),
                          selected: _categoria == null,
                          onSelected: (_) => setState(() => _categoria = null),
                        ),
                      ),
                      for (final c in _categorias)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: ChoiceChip(
                            label: Text(c),
                            selected: _categoria == c,
                            onSelected: (_) => setState(() => _categoria = c),
                          ),
                        ),
                    ],
                  ),
                ),
                Expanded(
                  child: AsyncListView<Guia>(
                    value: filtradas,
                    emptyIcon: Icons.help_outline,
                    emptyMessage: hayFiltro
                        ? 'Sin resultados con ese filtro'
                        : 'Sin guías ni preguntas frecuentes en ${destino.nombre}',
                    onRefresh: () async {
                      await ref.refresh(guiasProvider(destino.id).future);
                    },
                    itemBuilder: (context, g) => Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ExpansionTile(
                        shape: const Border(),
                        collapsedShape: const Border(),
                        leading: Icon(
                          g.tipo == 'faq'
                              ? Icons.quiz_outlined
                              : Icons.menu_book_outlined,
                        ),
                        title: Text(
                          textoIdioma(idioma, g.tituloEs, g.tituloEn),
                        ),
                        subtitle: Text(
                          '${g.categoria}  ·  ${g.tipo == 'faq' ? 'Pregunta frecuente' : 'Guía'}',
                        ),
                        childrenPadding: const EdgeInsets.fromLTRB(
                          16,
                          0,
                          16,
                          16,
                        ),
                        expandedCrossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            textoIdioma(idioma, g.contenidoEs, g.contenidoEn),
                          ),
                        ],
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

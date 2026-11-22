import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../auth/data/auth_repository.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/cultura_repository.dart';
import 'crear_expresion_dialog.dart';
import 'editar_expresion_dialog.dart';

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
    final destino = ref.watch(destinoEfectivoProvider);
    final perfil = ref.watch(perfilProvider).asData?.value;
    final esStaff = perfil?.esModerador == true || perfil?.esAdministrador == true;

    return Scaffold(
      appBar: AppBar(title: const Text('Cultura y traductor')),
      floatingActionButton: destino == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () async {
                final ok = await showDialog<bool>(
                  context: context,
                  builder: (_) => CrearExpresionDialog(destino: destino),
                );
                if (ok == true) {
                  ref.invalidate(expresionesProvider(destino.id));
                  ref.invalidate(expresionesPendientesProvider);
                }
              },
              icon: const Icon(Icons.add),
              label: const Text('Nueva expresión'),
            ),
      body: ConDestino(
        builder: (context, d) {
          final expresiones = ref.watch(expresionesProvider(d.id));
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
                      ? 'Sin expresiones culturales en ${d.nombre}'
                      : 'Sin resultados para "$_consulta"',
                  onRefresh: () async {
                    await ref.refresh(expresionesProvider(d.id).future);
                  },
                  itemBuilder: (context, e) {
                    final esAutor = perfil?.id == e.idUsuario;
                    final puedeEditar =
                        esStaff || (esAutor && e.esPendiente);
                    final puedeEliminar =
                        esStaff || (esAutor && e.esPendiente);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      child: ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Row(
                          children: [
                            Expanded(child: Text(e.expresion)),
                            if (e.esPendiente)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Pendiente',
                                  style: Theme.of(context)
                                      .textTheme
                                      .labelSmall
                                      ?.copyWith(
                                        color: Theme.of(context)
                                            .colorScheme
                                            .onTertiaryContainer,
                                      ),
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          textoIdioma(idioma, e.significadoEs, e.significadoEn),
                        ),
                        trailing: (puedeEditar || puedeEliminar)
                            ? Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (puedeEditar)
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined),
                                      tooltip: 'Editar',
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (_) =>
                                              EditarExpresionDialog(
                                            expresion: e,
                                          ),
                                        );
                                        if (ok == true) {
                                          ref.invalidate(
                                              expresionesProvider(d.id));
                                        }
                                      },
                                    ),
                                  if (puedeEliminar)
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .error),
                                      tooltip: 'Eliminar',
                                      onPressed: () async {
                                        final ok = await showDialog<bool>(
                                          context: context,
                                          builder: (ctx) => AlertDialog(
                                            title: const Text(
                                                'Eliminar expresión'),
                                            content: Text(
                                                '¿Eliminar "${e.expresion}"?'),
                                            actions: [
                                              TextButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, false),
                                                child: const Text('Cancelar'),
                                              ),
                                              FilledButton(
                                                onPressed: () =>
                                                    Navigator.pop(ctx, true),
                                                child: const Text('Eliminar'),
                                              ),
                                            ],
                                          ),
                                        );
                                        if (ok == true) {
                                          await ref
                                              .read(supabaseProvider)
                                              .from('expresion_cultural')
                                              .delete()
                                              .eq('id_expresion', e.id);
                                          ref.invalidate(
                                              expresionesProvider(d.id));
                                          ref.invalidate(
                                              expresionesPendientesProvider);
                                        }
                                      },
                                    ),
                                ],
                              )
                            : null,
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../data/destino_activo_provider.dart';
import '../data/destinos_repository.dart';

/// Barra "Destino: X ▾" que permite cambiar el destino de un módulo.
class DestinoSelector extends ConsumerWidget {
  const DestinoSelector({super.key, required this.destino});

  final Destino destino;

  void _elegir(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => Consumer(
        builder: (context, ref2, _) {
          final lista = ref2
              .watch(destinosProvider)
              .maybeWhen(data: (l) => l, orElse: () => const <Destino>[]);
          return _SelectorDestinos(
            destinos: lista,
            seleccionado: destino.id,
            onSeleccionar: (id) {
              ref.read(destinoActivoProvider.notifier).seleccionar(id);
              Navigator.of(sheetContext).pop();
            },
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
      child: InkWell(
        onTap: () => _elegir(context, ref),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              Icon(Icons.place_outlined, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Destino: ${destino.nombre}',
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              const Icon(Icons.expand_more),
            ],
          ),
        ),
      ),
    );
  }
}

/// Lista de destinos con buscador por nombre o municipio.
class _SelectorDestinos extends StatefulWidget {
  const _SelectorDestinos({
    required this.destinos,
    required this.seleccionado,
    required this.onSeleccionar,
  });

  final List<Destino> destinos;
  final int seleccionado;
  final ValueChanged<int> onSeleccionar;

  @override
  State<_SelectorDestinos> createState() => _SelectorDestinosState();
}

class _SelectorDestinosState extends State<_SelectorDestinos> {
  String _consulta = '';

  @override
  Widget build(BuildContext context) {
    final q = normalizar(_consulta.trim());
    final filtrados = q.isEmpty
        ? widget.destinos
        : widget.destinos
              .where(
                (d) => normalizar('${d.nombre} ${d.municipio}').contains(q),
              )
              .toList();

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: TextField(
              decoration: const InputDecoration(
                hintText: 'Buscar destino por nombre',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
              ),
              onChanged: (v) => setState(() => _consulta = v),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                if (filtrados.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'No se encontraron destinos para "$_consulta".',
                      textAlign: TextAlign.center,
                    ),
                  ),
                for (final d in filtrados)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(d.nombre),
                    subtitle: Text(d.municipio),
                    selected: d.id == widget.seleccionado,
                    onTap: () => widget.onSeleccionar(d.id),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Envuelve el contenido de un módulo con el selector de destino.
/// Si aún no hay destinos, muestra carga o el estado vacío.
class ConDestino extends ConsumerWidget {
  const ConDestino({super.key, required this.builder});

  final Widget Function(BuildContext context, Destino destino) builder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final destino = ref.watch(destinoEfectivoProvider);
    final cargando = ref.watch(destinosProvider).isLoading;

    if (destino == null) {
      return cargando
          ? const Center(child: CircularProgressIndicator())
          : const EmptyState(
              icon: Icons.place_outlined,
              message: 'Sin destinos disponibles',
            );
    }

    return Column(
      children: [
        DestinoSelector(destino: destino),
        Expanded(child: builder(context, destino)),
      ],
    );
  }
}

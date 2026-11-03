import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
      builder: (sheetContext) => SafeArea(
        child: Consumer(
          builder: (context, ref2, _) {
            final lista = ref2
                .watch(destinosProvider)
                .maybeWhen(data: (l) => l, orElse: () => const <Destino>[]);
            return ListView(
              shrinkWrap: true,
              children: [
                for (final d in lista)
                  ListTile(
                    leading: const Icon(Icons.place_outlined),
                    title: Text(d.nombre),
                    subtitle: Text(d.municipio),
                    selected: d.id == destino.id,
                    onTap: () {
                      ref
                          .read(destinoActivoProvider.notifier)
                          .seleccionar(d.id);
                      Navigator.of(sheetContext).pop();
                    },
                  ),
              ],
            );
          },
        ),
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

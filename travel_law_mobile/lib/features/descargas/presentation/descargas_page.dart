import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/widgets/empty_state.dart';
import '../../auth/data/auth_repository.dart';
import '../data/descargas_service.dart';

String _tamano(num bytes) {
  if (bytes < 1024) return '${bytes.round()} B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
}

class DescargasPage extends ConsumerStatefulWidget {
  const DescargasPage({super.key});

  @override
  ConsumerState<DescargasPage> createState() => _DescargasPageState();
}

class _DescargasPageState extends ConsumerState<DescargasPage> {
  final Set<int> _ocupados = {};

  void _mensaje(String texto) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(texto)));
  }

  Future<void> _descargar(CatalogoItem item) async {
    setState(() => _ocupados.add(item.idDestino));
    try {
      final client = ref.read(supabaseProvider);
      final paquete = await client.rpc(
        'paquete_destino',
        params: {'p_id_destino': item.idDestino},
      );
      await ref
          .read(descargasServiceProvider)
          .guardar(item.idDestino, Map<String, dynamic>.from(paquete as Map));
      try {
        // Estadística de descargas; si falla no invalida el paquete guardado.
        await client.rpc(
          'registrar_descarga',
          params: {'p_id_destino': item.idDestino},
        );
      } catch (_) {}
      ref.invalidate(paqueteLocalProvider(item.idDestino));
      _mensaje('Paquete de ${item.nombre} descargado.');
    } catch (_) {
      _mensaje(
        'No se pudo descargar. Revisa tu conexión e inténtalo de nuevo.',
      );
    } finally {
      if (mounted) setState(() => _ocupados.remove(item.idDestino));
    }
  }

  Future<void> _eliminar(CatalogoItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${item.nombre}'),
        content: const Text('Se borrará el paquete guardado en este teléfono.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true) return;
    await ref.read(descargasServiceProvider).eliminar(item.idDestino);
    ref.invalidate(paqueteLocalProvider(item.idDestino));
    _mensaje('Paquete eliminado.');
  }

  @override
  Widget build(BuildContext context) {
    final catalogo = ref.watch(catalogoProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Descargas offline')),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            color: Theme.of(context).colorScheme.secondaryContainer,
            padding: const EdgeInsets.all(12),
            child: Text(
              'Cada paquete guarda normas, zonas restringidas, contactos de '
              'emergencia, guías, expresiones, lugares y alertas recientes. '
              'El mapa necesita conexión.',
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSecondaryContainer,
              ),
            ),
          ),
          Expanded(
            child: AsyncListView<CatalogoItem>(
              value: catalogo,
              emptyIcon: Icons.download_for_offline_outlined,
              emptyMessage: 'Sin paquetes disponibles',
              onRefresh: () async {
                await ref.refresh(catalogoProvider.future);
              },
              itemBuilder: (context, item) => _PaqueteTile(
                item: item,
                ocupado: _ocupados.contains(item.idDestino),
                onDescargar: () => _descargar(item),
                onEliminar: () => _eliminar(item),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PaqueteTile extends ConsumerWidget {
  const _PaqueteTile({
    required this.item,
    required this.ocupado,
    required this.onDescargar,
    required this.onEliminar,
  });

  final CatalogoItem item;
  final bool ocupado;
  final VoidCallback onDescargar;
  final VoidCallback onEliminar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final local = ref
        .watch(paqueteLocalProvider(item.idDestino))
        .maybeWhen(data: (p) => p, orElse: () => null);

    final String estado;
    final String boton;
    if (local == null) {
      estado = 'No descargado  ·  ~${_tamano(item.tamanoKb * 1024)}';
      boton = 'Descargar';
    } else if (local.version != item.version) {
      estado =
          'Actualización disponible  ·  tienes la versión ${local.version}';
      boton = 'Actualizar';
    } else {
      estado =
          'Al día  ·  ${_tamano(local.bytes)}  ·  versión ${local.version}';
      boton = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(
          local == null
              ? Icons.cloud_download_outlined
              : Icons.download_done_outlined,
        ),
        title: Text(item.nombre),
        subtitle: Text(estado),
        trailing: ocupado
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (boton.isNotEmpty)
                    FilledButton.tonal(
                      onPressed: onDescargar,
                      child: Text(boton),
                    ),
                  if (local != null)
                    IconButton(
                      tooltip: 'Eliminar',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onEliminar,
                    ),
                ],
              ),
      ),
    );
  }
}

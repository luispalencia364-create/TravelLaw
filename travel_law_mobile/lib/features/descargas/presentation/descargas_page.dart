import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';

import '../../../core/permissions/permisos_almacenamiento.dart';
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
    // Sin acceso al almacenamiento no se puede escribir en Descargas/TravelLaw.
    final permiso = await PermisosAlmacenamiento.solicitar(context);
    if (!permiso) {
      _mensaje('Se necesita acceso al almacenamiento para guardar el PDF.');
      return;
    }

    setState(() => _ocupados.add(item.idDestino));
    try {
      final client = ref.read(supabaseProvider);

      // 1. Obtiene el paquete JSON desde Supabase.
      final paquete = await client.rpc(
        'paquete_destino',
        params: {'p_id_destino': item.idDestino},
      );

      final paqueteMap = Map<String, dynamic>.from(paquete as Map);

      // 2. Genera el PDF con la plantilla y lo guarda en Descargas.
      final rutaPdf = await ref
          .read(descargasServiceProvider)
          .guardar(item.idDestino, item.nombre, paqueteMap);

      // 3. Estadística de descargas (falla silenciosa).
      try {
        await client.rpc(
          'registrar_descarga',
          params: {'p_id_destino': item.idDestino},
        );
      } catch (_) {}

      // Actualiza el estado local.
      ref.invalidate(paqueteLocalProvider(item.idDestino));

      if (!mounted) return;

      // 4. Abre automáticamente el PDF generado para visualización inmediata.
      await _abrirPdf(rutaPdf);

      if (!mounted) return;

      // 5. Notificación con confirmación de guardado en el administrador de archivos.
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              'PDF guardado en tu carpeta de Descargas (TravelLaw).\n'
              'Disponible en el Administrador de archivos.',
            ),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: 'Abrir PDF',
              onPressed: () => _abrirPdf(rutaPdf),
            ),
          ),
        );
    } catch (e, st) {
      debugPrint('Error en descarga: $e\n$st');
      _mensaje('Error al descargar: $e');
    } finally {
      if (mounted) setState(() => _ocupados.remove(item.idDestino));
    }
  }

  Future<void> _abrirPdf(String ruta) async {
    try {
      final resultado = await ref.read(descargasServiceProvider).abrirPdf(ruta);
      if (resultado.type != ResultType.done && mounted) {
        if (resultado.type == ResultType.noAppToOpen) {
          _mensaje(
            'No se encontró una aplicación para abrir PDFs. '
            'Instala un lector de PDF (ej. Google PDF Viewer, Adobe).',
          );
        } else {
          _mensaje('No se pudo abrir el archivo: ${resultado.message}');
        }
      }
    } catch (e) {
      if (mounted) _mensaje('Error al abrir PDF: $e');
    }
  }

  Future<void> _eliminar(CatalogoItem item) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Eliminar ${item.nombre}'),
        content: const Text(
          'Se borrará el archivo PDF guardado en este dispositivo.',
        ),
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
    if (confirmar != true || !mounted) return;

    // En Android 11+ borrar de la carpeta pública también requiere el permiso.
    final permiso = await PermisosAlmacenamiento.solicitar(context);
    if (!permiso) {
      _mensaje('Se necesita acceso al almacenamiento para eliminar el PDF.');
      return;
    }

    await ref.read(descargasServiceProvider).eliminar(item.idDestino);
    ref.invalidate(paqueteLocalProvider(item.idDestino));
    _mensaje('PDF eliminado.');
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
              'Cada paquete genera un PDF oficial con normas, zonas restringidas, '
              'contactos de emergencia SOS, guías, expresiones y alertas recientes. '
              'Los archivos quedan en tu carpeta Descargas.',
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
              onRefresh: () => ref.refresh(catalogoProvider.future),
              itemBuilder: (context, item) => _PaqueteTile(
                item: item,
                ocupado: _ocupados.contains(item.idDestino),
                onDescargar: () => _descargar(item),
                onEliminar: () => _eliminar(item),
                onAbrir: (ruta) => _abrirPdf(ruta),
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
    required this.onAbrir,
  });

  final CatalogoItem item;
  final bool ocupado;
  final VoidCallback onDescargar;
  final VoidCallback onEliminar;
  final void Function(String ruta) onAbrir;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAsync = ref.watch(paqueteLocalProvider(item.idDestino));
    final local = localAsync.maybeWhen(data: (p) => p, orElse: () => null);

    final String estado;
    final String boton;
    if (local == null) {
      estado = 'No descargado  ·  ~${_tamano(item.tamanoKb * 1024)}';
      boton = 'Descargar';
    } else if (local.version != item.version) {
      estado = 'Actualización disponible  ·  tienes la v${local.version}';
      boton = 'Actualizar';
    } else {
      estado = 'Al día  ·  ${_tamano(local.bytes)}  ·  v${local.version}';
      boton = '';
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        onTap: local != null ? () => onAbrir(local.rutaPdf) : null,
        leading: Icon(
          local == null ? Icons.picture_as_pdf_outlined : Icons.picture_as_pdf,
          color: local != null ? Theme.of(context).colorScheme.primary : null,
        ),
        title: Text(item.nombre),
        subtitle: Text(local != null ? '$estado\nToca para abrir PDF' : estado),
        isThreeLine: local != null,
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
                  if (local != null) ...[
                    IconButton(
                      tooltip: 'Abrir PDF',
                      icon: const Icon(Icons.open_in_new_outlined),
                      onPressed: () => onAbrir(local.rutaPdf),
                    ),
                    IconButton(
                      tooltip: 'Eliminar PDF',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: onEliminar,
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

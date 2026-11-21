import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../../core/widgets/filtro_dias.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/comunidad_repository.dart';
import 'crear_publicacion_dialog.dart';

class ComunidadPage extends ConsumerStatefulWidget {
  const ComunidadPage({super.key});

  @override
  ConsumerState<ComunidadPage> createState() => _ComunidadPageState();
}

class _ComunidadPageState extends ConsumerState<ComunidadPage> {
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_alDesplazar);
  }

  @override
  void dispose() {
    _scrollController
      ..removeListener(_alDesplazar)
      ..dispose();
    super.dispose();
  }

  /// Carga la siguiente página cuando el usuario se acerca al final.
  void _alDesplazar() {
    if (!_scrollController.hasClients) return;
    final posicion = _scrollController.position;
    if (posicion.maxScrollExtent <= 0) return;
    if (posicion.pixels >= posicion.maxScrollExtent - 320) {
      ref.read(comunidadFeedProvider.notifier).cargarMas();
    }
  }

  @override
  Widget build(BuildContext context) {
    final perfil = ref.watch(perfilProvider).asData?.value;
    final destino = ref.watch(destinoEfectivoProvider);
    final dias = ref.watch(diasComunidadProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Comunidad de viajeros')),
      floatingActionButton: perfil != null && destino != null
          ? FloatingActionButton.extended(
              onPressed: () async {
                final creada = await showDialog<bool>(
                  context: context,
                  barrierDismissible: false,
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
        builder: (context, destino) => Column(
          children: [
            FiltroDias(
              valor: dias,
              onChanged: (v) =>
                  ref.read(diasComunidadProvider.notifier).cambiar(v),
            ),
            Expanded(
              child: Consumer(
                builder: (context, ref, _) {
                  final async = ref.watch(comunidadFeedProvider);
                  return async.when(
                    skipLoadingOnReload: true,
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => RefreshIndicator(
                      onRefresh: () =>
                          ref.read(comunidadFeedProvider.notifier).recargar(),
                      child: ListView(
                        controller: _scrollController,
                        physics: const AlwaysScrollableScrollPhysics(),
                        children: const [
                          SizedBox(
                            height: 420,
                            child: EmptyState(
                              icon: Icons.cloud_off_outlined,
                              message: 'No se pudo cargar la comunidad',
                              detail:
                                  'Revisa tu conexión y desliza hacia abajo '
                                  'para reintentar.',
                            ),
                          ),
                        ],
                      ),
                    ),
                    data: (estado) => RefreshIndicator(
                      onRefresh: () =>
                          ref.read(comunidadFeedProvider.notifier).recargar(),
                      child: estado.publicaciones.isEmpty
                          ? ListView(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              children: [
                                SizedBox(
                                  height: 420,
                                  child: EmptyState(
                                    icon: Icons.groups_outlined,
                                    message:
                                        'Sin publicaciones en ${destino.nombre}',
                                    detail:
                                        'Aquí verás recomendaciones, fotos y '
                                        'comentarios de otros viajeros.',
                                  ),
                                ),
                              ],
                            )
                          : ListView.builder(
                              controller: _scrollController,
                              physics: const AlwaysScrollableScrollPhysics(),
                              padding: const EdgeInsets.fromLTRB(
                                16,
                                8,
                                16,
                                24,
                              ),
                              itemCount: estado.publicaciones.length + 1,
                              itemBuilder: (context, i) {
                                if (i == estado.publicaciones.length) {
                                  return _PieFeed(estado: estado);
                                }
                                final p = estado.publicaciones[i];
                                return PublicacionCard(
                                  key: ValueKey(p.id),
                                  publicacion: p,
                                  perfil: perfil,
                                );
                              },
                            ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PieFeed extends ConsumerWidget {
  const _PieFeed({required this.estado});

  final ComunidadFeedState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (estado.cargandoMas) {
      return const Padding(
        padding: EdgeInsets.all(16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (estado.hayMas) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Center(
          child: TextButton.icon(
            onPressed: () =>
                ref.read(comunidadFeedProvider.notifier).cargarMas(),
            icon: const Icon(Icons.expand_more),
            label: const Text('Cargar más'),
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}

/// Tarjeta de una publicación con reacciones, comentarios y fotos.
class PublicacionCard extends ConsumerStatefulWidget {
  const PublicacionCard({
    super.key,
    required this.publicacion,
    required this.perfil,
  });

  final Publicacion publicacion;
  final Perfil? perfil;

  @override
  ConsumerState<PublicacionCard> createState() => _PublicacionCardState();
}

class _PublicacionCardState extends ConsumerState<PublicacionCard> {
  bool _procesandoLike = false;

  Publicacion get _p => widget.publicacion;

  bool get _esStaff =>
      widget.perfil?.esAdministrador == true ||
      widget.perfil?.esModerador == true;

  bool get _esMio => widget.perfil?.id == _p.autorId;

  Future<void> _alternarLike() async {
    setState(() => _procesandoLike = true);
    try {
      await ref
          .read(comunidadRepositoryProvider)
          .alternarMeGusta(_p.id, !_p.yoDoyMeGusta);
      await ref
          .read(comunidadFeedProvider.notifier)
          .refrescarPublicacion(_p.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo actualizar el me gusta.')),
        );
      }
      debugPrint('Error al dar me gusta: $e');
    } finally {
      if (mounted) setState(() => _procesandoLike = false);
    }
  }

  void _abrirComentarios() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: FractionallySizedBox(
          heightFactor: 0.8,
          child: ComentariosSheet(publicacion: _p),
        ),
      ),
    );
  }

  Future<void> _eliminarPublicacion() async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar publicación'),
        content: const Text(
          '¿Seguro que quieres eliminar esta publicación y sus fotos? '
          'Esta acción no se puede deshacer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await ref.read(comunidadRepositoryProvider).eliminarPublicacion(_p);
      ref.read(comunidadFeedProvider.notifier).quitarPublicacion(_p.id);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Publicación eliminada.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar la publicación.')),
        );
      }
      debugPrint('Error al eliminar publicación: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 18,
                  child: Text(
                    _p.autor.isEmpty ? '?' : _p.autor[0].toUpperCase(),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_p.autor, style: textTheme.titleSmall),
                      Text(
                        fechaRelativa(_p.fecha),
                        style: textTheme.bodySmall?.copyWith(
                          color: scheme.outline,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_esMio || _esStaff)
                  PopupMenuButton<String>(
                    tooltip: 'Opciones de la publicación',
                    onSelected: (valor) {
                      if (valor == 'eliminar') _eliminarPublicacion();
                    },
                    itemBuilder: (_) => const [
                      PopupMenuItem(
                        value: 'eliminar',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline),
                            SizedBox(width: 8),
                            Text('Eliminar publicación'),
                          ],
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Text(_p.descripcion, style: textTheme.bodyLarge),
            if (_p.evidencias.isNotEmpty) ...[
              const SizedBox(height: 12),
              _GaleriaFotos(evidencias: _p.evidencias),
            ],
            if (_p.comentarios.isNotEmpty) ...[
              const Divider(height: 20),
              for (final c in _p.comentarios.take(2))
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: RichText(
                    text: TextSpan(
                      style: textTheme.bodyMedium,
                      children: [
                        TextSpan(
                          text: '${c.autor} ',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        TextSpan(text: c.texto),
                      ],
                    ),
                  ),
                ),
              if (_p.comentarios.length > 2)
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: _abrirComentarios,
                    child: Text('Ver los ${_p.comentarios.length} comentarios'),
                  ),
                ),
            ],
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                TextButton.icon(
                  onPressed: _procesandoLike ? null : _alternarLike,
                  icon: Icon(
                    _p.yoDoyMeGusta ? Icons.favorite : Icons.favorite_border,
                    size: 20,
                    color: _p.yoDoyMeGusta ? scheme.error : null,
                  ),
                  label: Text('${_p.meGusta}'),
                ),
                TextButton.icon(
                  onPressed: _abrirComentarios,
                  icon: const Icon(Icons.chat_bubble_outline, size: 20),
                  label: Text('${_p.comentarios.length}'),
                ),
                TextButton(
                  onPressed: _abrirComentarios,
                  child: const Text('Comentar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _GaleriaFotos extends StatelessWidget {
  const _GaleriaFotos({required this.evidencias});

  final List<EvidenciaPublicacion> evidencias;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 170,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: evidencias.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final evidencia = evidencias[i];
          return GestureDetector(
            onTap: evidencia.url == null
                ? null
                : () => _verFoto(context, evidencia.url!),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: evidencia.url == null
                  ? Container(
                      width: 210,
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.broken_image_outlined),
                    )
                  : Image.network(
                      evidencia.url!,
                      width: 210,
                      height: 170,
                      fit: BoxFit.cover,
                      loadingBuilder: (context, child, progreso) {
                        if (progreso == null) return child;
                        return Container(
                          width: 210,
                          color: scheme.surfaceContainerHighest,
                          child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2),
                          ),
                        );
                      },
                      errorBuilder: (_, _, _) => Container(
                        width: 210,
                        color: scheme.surfaceContainerHighest,
                        child: const Icon(Icons.broken_image_outlined),
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }
}

void _verFoto(BuildContext context, String url) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black87,
    builder: (context) => Dialog(
      insetPadding: const EdgeInsets.all(12),
      backgroundColor: Colors.black,
      child: SizedBox(
        width: double.maxFinite,
        height: double.maxFinite,
        child: Stack(
          children: [
            InteractiveViewer(
              minScale: 1,
              maxScale: 4,
              child: Image.network(
                url,
                width: double.infinity,
                height: double.infinity,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) => const Center(
                  child: Text(
                    'No se pudo cargar la foto',
                    style: TextStyle(color: Colors.white70),
                  ),
                ),
              ),
            ),
            Positioned(
              top: 8,
              right: 8,
              child: IconButton.filledTonal(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Hoja con el hilo completo de comentarios y el campo para responder.
class ComentariosSheet extends ConsumerStatefulWidget {
  const ComentariosSheet({super.key, required this.publicacion});

  final Publicacion publicacion;

  @override
  ConsumerState<ComentariosSheet> createState() => _ComentariosSheetState();
}

class _ComentariosSheetState extends ConsumerState<ComentariosSheet> {
  final _texto = TextEditingController();
  final _scroll = ScrollController();
  bool _enviando = false;

  @override
  void dispose() {
    _texto.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Publicacion _actual(List<Publicacion>? lista) {
    if (lista == null) return widget.publicacion;
    for (final p in lista) {
      if (p.id == widget.publicacion.id) return p;
    }
    return widget.publicacion;
  }

  Future<void> _enviar() async {
    final texto = _texto.text.trim();
    if (texto.isEmpty || _enviando) return;
    setState(() => _enviando = true);
    try {
      await ref
          .read(comunidadRepositoryProvider)
          .agregarComentario(widget.publicacion.id, texto);
      _texto.clear();
      await ref
          .read(comunidadFeedProvider.notifier)
          .refrescarPublicacion(widget.publicacion.id);
      if (_scroll.hasClients) {
        _scroll.animateTo(
          _scroll.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo enviar el comentario.')),
        );
      }
      debugPrint('Error al comentar: $e');
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Future<void> _eliminar(ComentarioPublicacion comentario) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Eliminar comentario'),
        content: const Text('¿Seguro que quieres eliminar este comentario?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Eliminar'),
          ),
        ],
      ),
    );
    if (confirmar != true || !mounted) return;

    try {
      await ref
          .read(comunidadRepositoryProvider)
          .eliminarComentario(comentario.id);
      await ref
          .read(comunidadFeedProvider.notifier)
          .refrescarPublicacion(widget.publicacion.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No se pudo eliminar el comentario.')),
        );
      }
      debugPrint('Error al eliminar comentario: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final perfil = ref.watch(perfilProvider).asData?.value;
    final estado = ref.watch(comunidadFeedProvider).asData?.value;
    final publicacion = _actual(estado?.publicaciones);
    final comentarios = publicacion.comentarios;
    final esStaff =
        perfil?.esAdministrador == true || perfil?.esModerador == true;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 12, 8),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Comentarios (${comentarios.length})',
                  style: textTheme.titleMedium,
                ),
              ),
              IconButton(
                tooltip: 'Cerrar',
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: comentarios.isEmpty
              ? Center(
                  child: Text(
                    'Sé el primero en comentar.',
                    style: textTheme.bodyMedium?.copyWith(
                      color: scheme.outline,
                    ),
                  ),
                )
              : ListView.separated(
                  controller: _scroll,
                  padding: const EdgeInsets.all(16),
                  itemCount: comentarios.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final c = comentarios[i];
                    final esMio = c.autorId == perfil?.id;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        CircleAvatar(
                          radius: 14,
                          child: Text(
                            c.autor.isEmpty ? '?' : c.autor[0].toUpperCase(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      c.autor,
                                      style: textTheme.titleSmall,
                                    ),
                                  ),
                                  Text(
                                    fechaRelativa(c.fecha),
                                    style: textTheme.bodySmall?.copyWith(
                                      color: scheme.outline,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              Text(c.texto, style: textTheme.bodyMedium),
                            ],
                          ),
                        ),
                        if (esMio || esStaff)
                          IconButton(
                            tooltip: 'Eliminar comentario',
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _eliminar(c),
                            icon: const Icon(Icons.delete_outline, size: 18),
                          ),
                      ],
                    );
                  },
                ),
        ),
        const Divider(height: 1),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _texto,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _enviar(),
                    maxLength: 500,
                    decoration: const InputDecoration(
                      hintText: 'Escribe un comentario…',
                      counterText: '',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  tooltip: 'Enviar comentario',
                  onPressed: _enviando ? null : _enviar,
                  icon: _enviando
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: scheme.onPrimary,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

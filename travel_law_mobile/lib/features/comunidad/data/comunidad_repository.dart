import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';
import '../../destinos/data/destino_activo_provider.dart';

/// Foto asociada a una publicación de la comunidad.
class EvidenciaPublicacion {
  const EvidenciaPublicacion({required this.id, required this.path, this.url});

  final int id;

  /// Ruta dentro del bucket privado `evidencias` (`<uid>/<archivo>`).
  final String path;

  /// URL firmada temporal para mostrarla en la app.
  final String? url;
}

/// Comentario de una publicación.
class ComentarioPublicacion {
  const ComentarioPublicacion({
    required this.id,
    required this.autorId,
    required this.autor,
    required this.texto,
    this.fecha,
  });

  final String id;
  final String autorId;
  final String autor;
  final String texto;
  final DateTime? fecha;
}

/// Publicación del feed con sus reacciones, comentarios y fotos.
class Publicacion {
  const Publicacion({
    required this.id,
    required this.autorId,
    required this.autor,
    required this.descripcion,
    required this.meGusta,
    required this.yoDoyMeGusta,
    required this.comentarios,
    required this.evidencias,
    this.fecha,
  });

  final String id;
  final String autorId;
  final String autor;
  final String descripcion;
  final DateTime? fecha;
  final int meGusta;
  final bool yoDoyMeGusta;
  final List<ComentarioPublicacion> comentarios;
  final List<EvidenciaPublicacion> evidencias;
}

/// Una página del feed y si quedan publicaciones más antiguas por cargar.
class PaginaPublicaciones {
  const PaginaPublicaciones({required this.items, required this.hayMas});

  final List<Publicacion> items;
  final bool hayMas;
}

/// Acceso a la comunidad: publicaciones, likes, comentarios y fotos.
class ComunidadRepository {
  ComunidadRepository(this._client);

  final SupabaseClient _client;

  Future<PaginaPublicaciones> listarPublicaciones(
    int idDestino, {
    int dias = 30,
    int limite = 10,
    int offset = 0,
  }) async {
    final uid = _client.auth.currentUser?.id;
    final base = _client
        .from('publicacion')
        .select('id_publicacion, id_usuario, descripcion, fecha_creacion')
        .eq('id_destino', idDestino)
        .eq('estado', 'publicada');
    final filtrada = dias > 0
        ? base.gte(
            'fecha_creacion',
            DateTime.now()
                .subtract(Duration(days: dias))
                .toUtc()
                .toIso8601String(),
          )
        : base;

    // Se pide una fila extra para saber si quedan más páginas.
    final data = await filtrada
        .order('fecha_creacion', ascending: false)
        .range(offset, offset + limite);

    final hayMas = data.length > limite;
    final filas = hayMas ? data.take(limite).toList() : data;
    if (filas.isEmpty) {
      return const PaginaPublicaciones(items: [], hayMas: false);
    }

    final items = await _construirPublicaciones(filas, uid);
    return PaginaPublicaciones(items: items, hayMas: hayMas);
  }

  /// Recarga una sola publicación para reflejar likes o comentarios sin
  /// perder las páginas que el usuario ya cargó.
  Future<Publicacion?> obtenerPublicacion(String id) async {
    final uid = _client.auth.currentUser?.id;
    final data = await _client
        .from('publicacion')
        .select('id_publicacion, id_usuario, descripcion, fecha_creacion')
        .eq('id_publicacion', id)
        .eq('estado', 'publicada')
        .maybeSingle();
    if (data == null) return null;
    final items = await _construirPublicaciones([data], uid);
    return items.isEmpty ? null : items.first;
  }

  Future<List<Publicacion>> _construirPublicaciones(
    List<Map<String, dynamic>> filas,
    String? uid,
  ) async {
    final ids = filas.map((m) => m['id_publicacion'] as String).toList();

    final meGustas = await _client
        .from('me_gusta')
        .select('id_publicacion, id_usuario')
        .inFilter('id_publicacion', ids);

    final comentarios = await _client
        .from('comentario')
        .select('id_comentario, id_publicacion, id_usuario, texto, fecha')
        .inFilter('id_publicacion', ids)
        .order('fecha', ascending: true);

    final evidencias = await _client
        .from('evidencia')
        .select('id_evidencia, id_publicacion, url_archivo')
        .inFilter('id_publicacion', ids)
        .order('id_evidencia', ascending: true);

    final idsUsuarios = <String>{
      ...filas.map((m) => m['id_usuario'] as String),
      ...comentarios.map((m) => m['id_usuario'] as String),
    };
    final nombres = await _nombres(idsUsuarios.toList());

    final meGustaPorPublicacion = <String, int>{};
    final yoDoyMeGusta = <String>{};
    for (final m in meGustas) {
      final id = m['id_publicacion'] as String;
      meGustaPorPublicacion[id] = (meGustaPorPublicacion[id] ?? 0) + 1;
      if (m['id_usuario'] == uid) yoDoyMeGusta.add(id);
    }

    final comentariosPorPublicacion = <String, List<ComentarioPublicacion>>{};
    for (final m in comentarios) {
      final id = m['id_publicacion'] as String;
      comentariosPorPublicacion
          .putIfAbsent(id, () => [])
          .add(
            ComentarioPublicacion(
              id: m['id_comentario'] as String,
              autorId: m['id_usuario'] as String,
              autor: nombres[m['id_usuario'] as String] ?? 'Viajero',
              texto: m['texto'] as String,
              fecha: parseFecha(m['fecha']),
            ),
          );
    }

    final urlsFirmadas = await _firmarEvidencias(evidencias);
    final evidenciasPorPublicacion = <String, List<EvidenciaPublicacion>>{};
    for (final m in evidencias) {
      final id = m['id_publicacion'] as String;
      final path = m['url_archivo'] as String;
      evidenciasPorPublicacion
          .putIfAbsent(id, () => [])
          .add(
            EvidenciaPublicacion(
              id: m['id_evidencia'] as int,
              path: path,
              url: urlsFirmadas[path],
            ),
          );
    }

    return filas.map((m) {
      final id = m['id_publicacion'] as String;
      return Publicacion(
        id: id,
        autorId: m['id_usuario'] as String,
        autor: nombres[m['id_usuario'] as String] ?? 'Viajero',
        descripcion: m['descripcion'] as String,
        fecha: parseFecha(m['fecha_creacion']),
        meGusta: meGustaPorPublicacion[id] ?? 0,
        yoDoyMeGusta: yoDoyMeGusta.contains(id),
        comentarios: comentariosPorPublicacion[id] ?? const [],
        evidencias: evidenciasPorPublicacion[id] ?? const [],
      );
    }).toList();
  }

  Future<Map<String, String>> _nombres(List<String> ids) async {
    if (ids.isEmpty) return {};
    final perfiles = await _client.rpc(
      'perfiles_publicos',
      params: {'p_ids': ids},
    );
    final nombres = <String, String>{};
    for (final p in (perfiles as List)) {
      final mapa = Map<String, dynamic>.from(p as Map);
      nombres[mapa['id_usuario'] as String] = mapa['nombre'] as String;
    }
    return nombres;
  }

  /// Firma en lote las rutas del bucket privado. Si una foto falta, se
  /// omite y la interfaz muestra un marcador de imagen rota.
  Future<Map<String, String>> _firmarEvidencias(
    List<dynamic> evidencias,
  ) async {
    final paths = <String>[];
    for (final m in evidencias) {
      final path = m['url_archivo'] as String;
      if (!path.startsWith('http')) paths.add(path);
    }
    if (paths.isEmpty) return {};

    try {
      final resultados = await _client.storage
          .from('evidencias')
          .createSignedUrlsResult(paths, 3600);
      final urls = <String, String>{};
      for (final r in resultados) {
        if (r is SignedUrlSuccess) urls[r.path] = r.signedUrl;
      }
      return urls;
    } catch (e) {
      debugPrint('No se pudieron firmar las evidencias: $e');
      return {};
    }
  }

  Future<void> alternarMeGusta(String idPublicacion, bool dar) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Sesión no disponible');

    if (dar) {
      await _client
          .from('me_gusta')
          .upsert(
            {'id_publicacion': idPublicacion, 'id_usuario': uid},
            onConflict: 'id_publicacion,id_usuario',
            ignoreDuplicates: true,
          );
    } else {
      await _client
          .from('me_gusta')
          .delete()
          .eq('id_publicacion', idPublicacion)
          .eq('id_usuario', uid);
    }
  }

  Future<void> agregarComentario(String idPublicacion, String texto) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Sesión no disponible');
    await _client.from('comentario').insert({
      'id_publicacion': idPublicacion,
      'id_usuario': uid,
      'texto': texto,
    });
  }

  Future<void> eliminarComentario(String idComentario) async {
    await _client.from('comentario').delete().eq('id_comentario', idComentario);
  }

  /// Elimina la publicación y sus fotos del bucket privado.
  Future<void> eliminarPublicacion(Publicacion publicacion) async {
    await _client
        .from('publicacion')
        .delete()
        .eq('id_publicacion', publicacion.id);

    final paths = publicacion.evidencias.map((e) => e.path).toList();
    if (paths.isEmpty) return;
    try {
      await _client.storage.from('evidencias').remove(paths);
    } catch (e) {
      // La publicación ya se borró; si falla el borrado del archivo, no se
      // interrumpe la experiencia del usuario.
      debugPrint('No se pudieron borrar las fotos: $e');
    }
  }

  /// Crea la publicación y sube sus fotos. Si algo falla después de crear
  /// la publicación, se revierte para no dejar contenido a medias.
  Future<void> crearPublicacion(
    int idDestino,
    String descripcion,
    List<XFile> fotos,
  ) async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) throw StateError('Sesión no disponible');

    final paths = <String>[];
    String? idPublicacion;
    try {
      for (final foto in fotos) {
        paths.add(await _subirFoto(uid, foto));
      }

      final fila = await _client
          .from('publicacion')
          .insert({
            'id_usuario': uid,
            'id_destino': idDestino,
            'descripcion': descripcion,
            'estado': 'publicada',
          })
          .select('id_publicacion')
          .single();
      idPublicacion = fila['id_publicacion'] as String;

      if (paths.isNotEmpty) {
        await _client.from('evidencia').insert([
          for (final path in paths)
            {'id_publicacion': idPublicacion, 'url_archivo': path},
        ]);
      }
    } catch (e) {
      if (idPublicacion != null) {
        try {
          await _client
              .from('publicacion')
              .delete()
              .eq('id_publicacion', idPublicacion);
        } catch (_) {
          // Se ignora: el error original es más útil.
        }
      }
      if (paths.isNotEmpty) {
        try {
          await _client.storage.from('evidencias').remove(paths);
        } catch (_) {
          // Se ignora: el error original es más útil.
        }
      }
      rethrow;
    }
  }

  Future<String> _subirFoto(String uid, XFile foto) async {
    final original = await foto.readAsBytes();
    final bytes = await compute(_comprimirImagen, original);
    final extension = _extensionDesdeBytes(bytes);
    final path = '$uid/${_nombreAleatorio()}.$extension';

    await _client.storage
        .from('evidencias')
        .uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            contentType: _mimeDesdeExtension(extension),
            cacheControl: '3600',
          ),
        );
    return path;
  }
}

String _nombreAleatorio() {
  final random = Random.secure();
  final bytes = List<int>.generate(16, (_) => random.nextInt(256));
  return bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
}

String _extensionDesdeBytes(Uint8List bytes) {
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpg';
  }
  if (bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return 'webp';
  }
  return 'jpg';
}

String _mimeDesdeExtension(String extension) {
  return switch (extension) {
    'png' => 'image/png',
    'webp' => 'image/webp',
    _ => 'image/jpeg',
  };
}

/// Reduce y reorienta la foto antes de subirla. Se ejecuta en un isolate
/// para no bloquear la interfaz. Si el formato no se puede decodificar,
/// se sube el archivo original.
Uint8List _comprimirImagen(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final orientada = img.bakeOrientation(decoded);
  final reducida = orientada.width > 1600
      ? img.copyResize(orientada, width: 1600)
      : orientada;
  return Uint8List.fromList(img.encodeJpg(reducida, quality: 80));
}

final comunidadRepositoryProvider = Provider<ComunidadRepository>((ref) {
  return ComunidadRepository(ref.watch(supabaseProvider));
});

/// Días hacia atrás que se muestran en el feed (0 = todo).
class DiasComunidadNotifier extends Notifier<int> {
  @override
  int build() => 30;

  void cambiar(int dias) => state = dias;
}

final diasComunidadProvider = NotifierProvider<DiasComunidadNotifier, int>(
  DiasComunidadNotifier.new,
);

/// Estado del feed paginado: publicaciones cargadas, si hay más y si se
/// está pidiendo la siguiente página.
class ComunidadFeedState {
  const ComunidadFeedState({
    required this.publicaciones,
    required this.hayMas,
    this.cargandoMas = false,
  });

  final List<Publicacion> publicaciones;
  final bool hayMas;
  final bool cargandoMas;

  ComunidadFeedState copyWith({
    List<Publicacion>? publicaciones,
    bool? hayMas,
    bool? cargandoMas,
  }) {
    return ComunidadFeedState(
      publicaciones: publicaciones ?? this.publicaciones,
      hayMas: hayMas ?? this.hayMas,
      cargandoMas: cargandoMas ?? this.cargandoMas,
    );
  }
}

/// Feed del destino: publicaciones visibles, de la más reciente a la más
/// antigua, con paginación y filtro por días.
class ComunidadFeedNotifier extends AsyncNotifier<ComunidadFeedState> {
  static const _tamanoPagina = 10;

  @override
  Future<ComunidadFeedState> build() async {
    final destino = ref.watch(destinoEfectivoProvider);
    final dias = ref.watch(diasComunidadProvider);
    if (destino == null) {
      return const ComunidadFeedState(publicaciones: [], hayMas: false);
    }

    final pagina = await ref
        .watch(comunidadRepositoryProvider)
        .listarPublicaciones(
          destino.id,
          dias: dias,
          limite: _tamanoPagina,
        );
    return ComunidadFeedState(
      publicaciones: pagina.items,
      hayMas: pagina.hayMas,
    );
  }

  /// Vuelve a cargar desde la primera página (pull to refresh o cambio de
  /// destino/filtro).
  Future<void> recargar() async {
    ref.invalidateSelf();
    await future;
  }

  /// Carga la siguiente página sin perder las anteriores.
  Future<void> cargarMas() async {
    final actual = state.asData?.value;
    if (actual == null || !actual.hayMas || actual.cargandoMas) return;

    final destino = ref.read(destinoEfectivoProvider);
    if (destino == null) return;

    state = AsyncData(actual.copyWith(cargandoMas: true));
    try {
      final pagina = await ref
          .read(comunidadRepositoryProvider)
          .listarPublicaciones(
            destino.id,
            dias: ref.read(diasComunidadProvider),
            limite: _tamanoPagina,
            offset: actual.publicaciones.length,
          );
      final vigente = state.asData?.value ?? actual;
      state = AsyncData(
        vigente.copyWith(
          publicaciones: [...vigente.publicaciones, ...pagina.items],
          hayMas: pagina.hayMas,
          cargandoMas: false,
        ),
      );
    } catch (e) {
      debugPrint('No se pudo cargar más publicaciones: $e');
      state = AsyncData(actual.copyWith(cargandoMas: false));
    }
  }

  /// Refresca una publicación puntual tras un like o un comentario. Si ya
  /// no es visible (restringida o eliminada), se quita del feed.
  Future<void> refrescarPublicacion(String id) async {
    final actual = state.asData?.value;
    if (actual == null) return;

    final publicacion = await ref
        .read(comunidadRepositoryProvider)
        .obtenerPublicacion(id);
    final vigente = state.asData?.value ?? actual;
    if (publicacion == null) {
      state = AsyncData(
        vigente.copyWith(
          publicaciones: vigente.publicaciones
              .where((p) => p.id != id)
              .toList(),
        ),
      );
      return;
    }

    state = AsyncData(
      vigente.copyWith(
        publicaciones: [
          for (final p in vigente.publicaciones)
            if (p.id == id) publicacion else p,
        ],
      ),
    );
  }

  void quitarPublicacion(String id) {
    final actual = state.asData?.value;
    if (actual == null) return;
    state = AsyncData(
      actual.copyWith(
        publicaciones: actual.publicaciones
            .where((p) => p.id != id)
            .toList(),
      ),
    );
  }
}

final comunidadFeedProvider =
    AsyncNotifierProvider.autoDispose<
      ComunidadFeedNotifier,
      ComunidadFeedState
    >(ComunidadFeedNotifier.new);

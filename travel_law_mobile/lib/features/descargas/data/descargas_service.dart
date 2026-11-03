import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

/// Elemento del catálogo de paquetes (función SQL catalogo_paquetes).
class CatalogoItem {
  const CatalogoItem({
    required this.idDestino,
    required this.nombre,
    required this.municipio,
    required this.version,
    required this.tamanoKb,
  });

  final int idDestino;
  final String nombre;
  final String municipio;
  final String version;
  final double tamanoKb;

  factory CatalogoItem.fromMap(Map<String, dynamic> m) => CatalogoItem(
    idDestino: m['id_destino'] as int,
    nombre: m['nombre'] as String,
    municipio: m['municipio'] as String,
    version: m['version'] as String,
    tamanoKb: (m['tamano_kb'] as num).toDouble(),
  );
}

/// Paquete guardado en el teléfono.
class PaqueteLocal {
  const PaqueteLocal({
    required this.version,
    required this.bytes,
    this.generadoEn,
  });

  final String version;
  final int bytes;
  final DateTime? generadoEn;
}

/// Guarda cada paquete como un archivo JSON en la carpeta privada de la app.
class DescargasService {
  Future<File> _archivo(int idDestino) async {
    final base = await getApplicationDocumentsDirectory();
    final carpeta = Directory('${base.path}/paquetes');
    if (!await carpeta.exists()) await carpeta.create(recursive: true);
    return File('${carpeta.path}/destino_$idDestino.json');
  }

  Future<PaqueteLocal?> leer(int idDestino) async {
    final archivo = await _archivo(idDestino);
    if (!await archivo.exists()) return null;
    try {
      final contenido = await archivo.readAsString();
      final mapa = jsonDecode(contenido) as Map<String, dynamic>;
      return PaqueteLocal(
        version: (mapa['version'] as String?) ?? '?',
        bytes: await archivo.length(),
        generadoEn: parseFecha(mapa['generado_en']),
      );
    } catch (_) {
      return null; // archivo dañado: se trata como no descargado
    }
  }

  Future<void> guardar(int idDestino, Map<String, dynamic> paquete) async {
    final archivo = await _archivo(idDestino);
    await archivo.writeAsString(jsonEncode(paquete));
  }

  Future<void> eliminar(int idDestino) async {
    final archivo = await _archivo(idDestino);
    if (await archivo.exists()) await archivo.delete();
  }
}

final descargasServiceProvider = Provider<DescargasService>(
  (ref) => DescargasService(),
);

final catalogoProvider = FutureProvider.autoDispose<List<CatalogoItem>>((
  ref,
) async {
  final data = await ref.watch(supabaseProvider).rpc('catalogo_paquetes');
  return (data as List)
      .map((e) => CatalogoItem.fromMap(Map<String, dynamic>.from(e as Map)))
      .toList();
});

final paqueteLocalProvider = FutureProvider.autoDispose
    .family<PaqueteLocal?, int>((ref, idDestino) {
      return ref.watch(descargasServiceProvider).leer(idDestino);
    });

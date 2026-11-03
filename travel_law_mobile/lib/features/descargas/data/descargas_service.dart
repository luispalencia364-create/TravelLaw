import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../../../core/utils/text_utils.dart';
import '../../auth/data/auth_repository.dart';

// ─────────────────────────────────────────────────────────────
// Modelos
// ─────────────────────────────────────────────────────────────

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

/// Metadatos del PDF guardado en el dispositivo.
class PaqueteLocal {
  const PaqueteLocal({
    required this.version,
    required this.bytes,
    required this.rutaPdf,
    this.generadoEn,
  });

  final String version;
  final int bytes;
  final String rutaPdf; // ruta absoluta del archivo PDF en el almacenamiento
  final DateTime? generadoEn;
}

// ─────────────────────────────────────────────────────────────
// Colores del tema del PDF
// ─────────────────────────────────────────────────────────────

const _primary = PdfColor.fromInt(0xFF0B6E6E);
const _primaryLight = PdfColor.fromInt(0xFFE0F2F1);
const _errorColor = PdfColor.fromInt(0xFFB00020);
const _grey = PdfColor.fromInt(0xFF616161);
const _border = PdfColor.fromInt(0xFFBDBDBD);
const _verdeChip = PdfColor.fromInt(0xFF2E7D32);
const _verdeChipBg = PdfColor.fromInt(0xFFE8F5E9);
const _ambarChip = PdfColor.fromInt(0xFFF57F17);
const _ambarChipBg = PdfColor.fromInt(0xFFFFF9C4);

// ─────────────────────────────────────────────────────────────
// Generador de PDF (se ejecuta en isolate mediante compute())
// ─────────────────────────────────────────────────────────────

/// Limpia caracteres fuera de Latin-1 para evitar que la fuente Type1
/// (Helvetica) de `package:pdf` lance excepciones de caracteres no soportados.
String _limpiarTexto(Object? v) {
  if (v == null) return '';
  var s = v.toString().trim();
  s = s
      .replaceAll('—', '-')
      .replaceAll('–', '-')
      .replaceAll('“', '"')
      .replaceAll('”', '"')
      .replaceAll('‘', "'")
      .replaceAll('’', "'")
      .replaceAll('…', '...')
      .replaceAll('•', '*');

  final buffer = StringBuffer();
  for (final rune in s.runes) {
    if (rune <= 255) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

String _es(Map<String, dynamic> m, String campo) =>
    _limpiarTexto(m['${campo}_es'] ?? m[campo]);

String _en(Map<String, dynamic> m, String campo) =>
    _limpiarTexto(m['${campo}_en'] ?? '');

/// Punto de entrada para compute(): recibe el JSON del paquete como String.
Future<Uint8List> _buildPdfIsolate(String paqueteJson) async {
  final paquete = jsonDecode(paqueteJson) as Map<String, dynamic>;
  return await _buildPdf(paquete);
}

Future<Uint8List> _buildPdf(Map<String, dynamic> paquete) async {
  final destInfo = paquete['destino'];
  final dest = destInfo is Map
      ? Map<String, dynamic>.from(destInfo)
      : <String, dynamic>{};

  final nombreDestino = _limpiarTexto(dest['nombre'] ?? paquete['nombre']);
  final municipio = _limpiarTexto(dest['municipio'] ?? paquete['municipio']);
  final version = _limpiarTexto(paquete['version'] ?? '1');
  final generado = DateTime.now();

  final normas = (paquete['normas'] as List?) ?? [];
  final zonas = (paquete['zonas_restringidas'] as List?) ?? [];
  final contactos = (paquete['contactos_emergencia'] as List?) ?? [];
  final guias = (paquete['guias'] as List?) ?? [];
  final expresiones = (paquete['expresiones'] as List?) ?? [];
  final alertas = (paquete['alertas'] as List?) ?? [];

  // ── Widgets helpers ───────────────────────

  pw.Widget seccion(String titulo, {PdfColor color = _primary}) =>
      pw.Container(
        margin: const pw.EdgeInsets.only(top: 18, bottom: 6),
        padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: pw.BoxDecoration(
          color: _primaryLight,
          border: pw.Border(left: pw.BorderSide(color: color, width: 4)),
          //borderRadius: const pw.BorderRadius.only(
            //topRight: pw.Radius.circular(4),
            //bottomRight: pw.Radius.circular(4),
          //),
        ),
        child: pw.Text( 
          titulo,
          style: pw.TextStyle(
            fontSize: 12,
            fontWeight: pw.FontWeight.bold,
            color: color,
          ),
        ),
      );

  pw.Widget dato(String etiqueta, String valor) => pw.Padding(
        padding: const pw.EdgeInsets.symmetric(vertical: 2.5),
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            pw.SizedBox(
              width: 105,
              child: pw.Text(
                etiqueta,
                style: pw.TextStyle(
                  fontSize: 9,
                  fontWeight: pw.FontWeight.bold,
                  color: _grey,
                ),
              ),
            ),
            pw.Expanded(
              child: pw.Text(valor, style: const pw.TextStyle(fontSize: 9)),
            ),
          ],
        ),
      );

  pw.Widget tarjeta(List<pw.Widget> hijos) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 8),
        padding: const pw.EdgeInsets.all(10),
        decoration: pw.BoxDecoration(
          border: pw.Border.all(color: _border),
          borderRadius: pw.BorderRadius.circular(6),
        ),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: hijos,
        ),
      );

  pw.Widget chip(String texto, PdfColor bg, PdfColor fg) => pw.Container(
        padding: const pw.EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: pw.BoxDecoration(
          color: bg,
          borderRadius: pw.BorderRadius.circular(12),
        ),
        child: pw.Text(texto, style: pw.TextStyle(fontSize: 8, color: fg)),
      );

  // ── Secciones ─────────────────────────────

  List<pw.Widget> buildContactos() {
    if (contactos.isEmpty) return [];
    return [
      seccion('Contactos de emergencia (SOS)', color: _errorColor),
      ...contactos.map((c) {
        final m = Map<String, dynamic>.from(c as Map);
        return tarjeta([
          pw.Text(
            _limpiarTexto(m['entidad']),
            style: pw.TextStyle(
              fontSize: 10.5,
              fontWeight: pw.FontWeight.bold,
              color: _errorColor,
            ),
          ),
          pw.SizedBox(height: 5),
          dato('Telefono', _limpiarTexto(m['telefono'])),
          if (_limpiarTexto(m['direccion']).isNotEmpty)
            dato('Direccion', _limpiarTexto(m['direccion'])),
          if (_limpiarTexto(m['fuente']).isNotEmpty)
            dato('Fuente', _limpiarTexto(m['fuente'])),
          if (_limpiarTexto(m['fecha_actualizacion']).isNotEmpty)
            dato(
              'Actualizado',
              formatearFecha(parseFecha(m['fecha_actualizacion'])),
            ),
        ]);
      }),
    ];
  }

  List<pw.Widget> buildNormas() {
    if (normas.isEmpty) return [];
    return [
      seccion('Legal y normativa'),
      ...normas.map((n) {
        final m = Map<String, dynamic>.from(n as Map);
        return tarjeta([
          pw.Text(
            _es(m, 'titulo'),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
          pw.SizedBox(height: 5),
          dato('Tipo', capitalizar(_limpiarTexto(m['tipo']))),
          dato('Contenido', _es(m, 'contenido')),
          if (_limpiarTexto(m['fuente']).isNotEmpty)
            dato('Fuente', _limpiarTexto(m['fuente'])),
          if (_limpiarTexto(m['fecha_actualizacion']).isNotEmpty)
            dato(
              'Actualizado',
              formatearFecha(parseFecha(m['fecha_actualizacion'])),
            ),
          if (_en(m, 'titulo').isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              'English: ${_en(m, 'titulo')}',
              style: pw.TextStyle(
                fontSize: 8.5,
                fontStyle: pw.FontStyle.italic,
                color: _grey,
              ),
            ),
            pw.Text(
              _en(m, 'contenido'),
              style: const pw.TextStyle(fontSize: 8.5, color: _grey),
            ),
          ],
        ]);
      }),
    ];
  }

  List<pw.Widget> buildZonas() {
    if (zonas.isEmpty) return [];
    return [
      seccion('Zonas restringidas'),
      ...zonas.map((z) {
        final m = Map<String, dynamic>.from(z as Map);
        final norma = m['norma'];
        final normaTexto = norma is Map
            ? _limpiarTexto(norma['titulo_es'] ?? norma['titulo'])
            : '';
        return tarjeta([
          pw.Text(
            _limpiarTexto(z['nombre']),
            style: pw.TextStyle(fontSize: 10.5, fontWeight: pw.FontWeight.bold),
          ),
          if (normaTexto.isNotEmpty) ...[
            pw.SizedBox(height: 4),
            dato('Norma asociada', normaTexto),
          ],
        ]);
      }),
    ];
  }

  List<pw.Widget> buildGuias() {
    if (guias.isEmpty) return [];
    return [
      seccion('Centro de orientacion'),
      ...guias.map((g) {
        final m = Map<String, dynamic>.from(g as Map);
        final cat = m['categoria_guia'];
        final categoria =
            cat is Map ? _limpiarTexto(cat['nombre']) : _limpiarTexto(m['categoria'] ?? '');
        final esFaq = _limpiarTexto(m['tipo']) == 'faq';
        return tarjeta([
          pw.Row(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Expanded(
                child: pw.Text(
                  _es(m, 'titulo'),
                  style: pw.TextStyle(
                    fontSize: 10.5,
                    fontWeight: pw.FontWeight.bold,
                  ),
                ),
              ),
              pw.SizedBox(width: 8),
              chip(
                esFaq ? 'FAQ' : 'Guia',
                _primaryLight,
                _primary,
              ),
            ],
          ),
          if (categoria.isNotEmpty) ...[
            pw.SizedBox(height: 3),
            pw.Text(
              categoria,
              style: const pw.TextStyle(fontSize: 8.5, color: _grey),
            ),
          ],
          pw.SizedBox(height: 5),
          pw.Text(_es(m, 'contenido'), style: const pw.TextStyle(fontSize: 9)),
          if (_en(m, 'contenido').isNotEmpty) ...[
            pw.SizedBox(height: 6),
            pw.Text(
              _en(m, 'contenido'),
              style: const pw.TextStyle(fontSize: 8.5, color: _grey),
            ),
          ],
        ]);
      }),
    ];
  }

  List<pw.Widget> buildExpresiones() {
    if (expresiones.isEmpty) return [];
    return [
      seccion('Expresiones culturales'),
      pw.Table(
        border: pw.TableBorder.all(color: _border),
        columnWidths: {
          0: const pw.FlexColumnWidth(1.5),
          1: const pw.FlexColumnWidth(2),
          2: const pw.FlexColumnWidth(2),
        },
        children: [
          pw.TableRow(
            decoration: const pw.BoxDecoration(color: _primaryLight),
            children: [
              _cellHeader('Expresion'),
              _cellHeader('Significado (ES)'),
              _cellHeader('Meaning (EN)'),
            ],
          ),
          ...expresiones.map((e) {
            final m = Map<String, dynamic>.from(e as Map);
            return pw.TableRow(children: [
              _cellBold(_limpiarTexto(m['expresion'])),
              _cell(_limpiarTexto(m['significado_es'])),
              _cell(_limpiarTexto(m['significado_en']), color: _grey),
            ]);
          }),
        ],
      ),
    ];
  }

  List<pw.Widget> buildAlertas() {
    if (alertas.isEmpty) return [];
    return [
      seccion('Alertas recientes'),
      ...alertas.map((a) {
        final m = Map<String, dynamic>.from(a as Map);
        final verificada = _limpiarTexto(m['estado']) == 'verificada';
        final tipo = capitalizar(
          _limpiarTexto(m['tipo']).replaceAll('_', ' '),
        );
        return tarjeta([
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text(
                tipo,
                style: pw.TextStyle(
                  fontSize: 10.5,
                  fontWeight: pw.FontWeight.bold,
                ),
              ),
              chip(
                verificada ? 'Verificada' : 'Sin verificar',
                verificada ? _verdeChipBg : _ambarChipBg,
                verificada ? _verdeChip : _ambarChip,
              ),
            ],
          ),
          pw.SizedBox(height: 5),
          pw.Text(
            _limpiarTexto(m['descripcion']),
            style: const pw.TextStyle(fontSize: 9),
          ),
          if (_limpiarTexto(m['fecha_evento']).isNotEmpty)
            dato(
              'Fecha',
              formatearFecha(parseFecha(m['fecha_evento'])),
            ),
        ]);
      }),
    ];
  }

  // ── Documento ─────────────────────────────

  final doc = pw.Document(
    title: 'TravelLaw - $nombreDestino',
    author: 'TravelLaw Mobile',
    subject: 'Paquete offline de destino turistico',
  );

  doc.addPage(
    pw.MultiPage(
      pageFormat: PdfPageFormat.a4,
      margin: const pw.EdgeInsets.symmetric(horizontal: 36, vertical: 36),
      header: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(bottom: 12),
        padding: const pw.EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: pw.BoxDecoration(
          color: _primary,
          borderRadius: pw.BorderRadius.circular(8),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(
                  'TravelLaw',
                  style: pw.TextStyle(
                    fontSize: 18,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  'Tu asistente para viajar informado y seguro',
                  style: const pw.TextStyle(
                    fontSize: 8.5,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
            pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.end,
              children: [
                pw.Text(
                  nombreDestino,
                  style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.white,
                  ),
                ),
                pw.Text(
                  municipio,
                  style: const pw.TextStyle(
                    fontSize: 9,
                    color: PdfColors.white,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      footer: (ctx) => pw.Container(
        margin: const pw.EdgeInsets.only(top: 8),
        padding: const pw.EdgeInsets.only(top: 6),
        decoration: const pw.BoxDecoration(
          border: pw.Border(top: pw.BorderSide(color: _border)),
        ),
        child: pw.Row(
          mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
          children: [
            pw.Text(
              'Generado: ${formatearFecha(generado)} - Version $version',
              style: const pw.TextStyle(fontSize: 7.5, color: _grey),
            ),
            pw.Text(
              'Pagina ${ctx.pageNumber} de ${ctx.pagesCount}',
              style: const pw.TextStyle(fontSize: 7.5, color: _grey),
            ),
          ],
        ),
      ),
      build: (ctx) => [
        // ── Resumen del destino ──────────────
        pw.Container(
          padding: const pw.EdgeInsets.all(14),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: _primary, width: 1.5),
            borderRadius: pw.BorderRadius.circular(8),
          ),
          child: pw.Row(
            children: [
              pw.Expanded(
                child: pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text(
                      'Paquete de informacion offline',
                      style: pw.TextStyle(
                        fontSize: 12,
                        fontWeight: pw.FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                    pw.Text(
                      '$nombreDestino - $municipio, Cordoba',
                      style: const pw.TextStyle(fontSize: 9.5, color: _grey),
                    ),
                    pw.SizedBox(height: 8),
                    pw.Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        _resumenChip(
                          '${normas.length} normas',
                          _primaryLight,
                          _primary,
                        ),
                        _resumenChip(
                          '${zonas.length} zonas',
                          _primaryLight,
                          _primary,
                        ),
                        _resumenChip(
                          '${contactos.length} emergencias',
                          const PdfColor.fromInt(0xFFFFEBEE),
                          _errorColor,
                        ),
                        _resumenChip(
                          '${guias.length} guias/FAQs',
                          _primaryLight,
                          _primary,
                        ),
                        _resumenChip(
                          '${expresiones.length} expresiones',
                          _primaryLight,
                          _primary,
                        ),
                        _resumenChip(
                          '${alertas.length} alertas',
                          _ambarChipBg,
                          _ambarChip,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              pw.SizedBox(width: 16),
              pw.Container(
                padding: const pw.EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 12,
                ),
                decoration: pw.BoxDecoration(
                  color: _primaryLight,
                  borderRadius: pw.BorderRadius.circular(8),
                ),
                child: pw.Column(
                  children: [
                    pw.Text(
                      'v$version',
                      style: pw.TextStyle(
                        fontSize: 18,
                        fontWeight: pw.FontWeight.bold,
                        color: _primary,
                      ),
                    ),
                    pw.Text(
                      formatearFecha(generado),
                      style: const pw.TextStyle(fontSize: 8, color: _grey),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // ── Secciones con datos ──────────────
        ...buildContactos(),
        ...buildNormas(),
        ...buildZonas(),
        ...buildGuias(),
        ...buildExpresiones(),
        ...buildAlertas(),

        // ── Pie informativo ──────────────────
        pw.SizedBox(height: 16),
        pw.Container(
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            color: _primaryLight,
            borderRadius: pw.BorderRadius.circular(6),
          ),
          child: pw.Text(
            'Este documento fue generado por la app TravelLaw para uso offline. '
            'La informacion puede cambiar: verifica siempre con las autoridades '
            'locales en destino.',
            style: const pw.TextStyle(fontSize: 8, color: _grey),
          ),
        ),
      ],
    ),
  );

  return await doc.save();
}

// ─────────────────────────────────────────────────────────────
// Helpers para las celdas de la tabla
// ─────────────────────────────────────────────────────────────

pw.Widget _cellHeader(String texto) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _cellBold(String texto) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 9, fontWeight: pw.FontWeight.bold),
      ),
    );

pw.Widget _cell(String texto, {PdfColor? color}) => pw.Padding(
      padding: const pw.EdgeInsets.all(6),
      child: pw.Text(
        texto,
        style: pw.TextStyle(fontSize: 9, color: color),
      ),
    );

pw.Widget _resumenChip(String texto, PdfColor bg, PdfColor fg) =>
    pw.Container(
      padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: pw.BoxDecoration(
        color: bg,
        borderRadius: pw.BorderRadius.circular(10),
      ),
      child: pw.Text(texto, style: pw.TextStyle(fontSize: 8, color: fg)),
    );

// ─────────────────────────────────────────────────────────────
// Servicio de descargas
// ─────────────────────────────────────────────────────────────

/// Nombre de archivo seguro (sin caracteres especiales).
String _nombreArchivoPdf(String nombreDestino) {
  final seguro = nombreDestino
      .replaceAll(RegExp(r'[^\w\sáéíóúñÁÉÍÓÚÑ-]', unicode: true), '')
      .trim()
      .replaceAll(RegExp(r'\s+'), '_');
  return 'TravelLaw_$seguro.pdf';
}

class DescargasService {
  // ── Rutas ─────────────────────────────────

  /// Obtiene el directorio base de descargas.
  /// En Android prioriza la carpeta pública `/storage/emulated/0/Download/TravelLaw`
  /// para que el usuario pueda ver el PDF directamente desde el Administrador
  /// de archivos de su celular.
  Future<Directory> _dirBase() async {
    if (Platform.isAndroid) {
      // 1. Intenta la carpeta pública de Descargas de Android (/storage/emulated/0/Download)
      // Esta es la carpeta accesible desde el Administrador de Archivos de cualquier celular.
      try {
        final publicDownload = Directory('/storage/emulated/0/Download');
        if (await publicDownload.exists()) {
          final dir = Directory('${publicDownload.path}/TravelLaw');
          if (!await dir.exists()) await dir.create(recursive: true);
          // Prueba rápida de escritura
          final test = File('${dir.path}/.test_access');
          await test.writeAsString('ok');
          await test.delete();
          return dir;
        }
      } catch (_) {
        // En algunas versiones con Scoped Storage estricto, la escritura directa
        // puede fallar; pasamos al fallback.
      }

      // 2. Directorio de descargas externo del sistema
      try {
        final extDownloads =
            await getExternalStorageDirectories(type: StorageDirectory.downloads);
        if (extDownloads != null && extDownloads.isNotEmpty) {
          final dir = Directory('${extDownloads.first.path}/TravelLaw');
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir;
        }
      } catch (_) {}

      // 3. Directorio de almacenamiento externo general
      try {
        final extDir = await getExternalStorageDirectory();
        if (extDir != null) {
          final dir = Directory('${extDir.path}/TravelLaw');
          if (!await dir.exists()) await dir.create(recursive: true);
          return dir;
        }
      } catch (_) {}
    }

    // 4. Fallback estándar (iOS o si los anteriores no están disponibles)
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/TravelLaw');
    if (!await dir.exists()) await dir.create(recursive: true);
    return dir;
  }

  Future<File> _pdfFile(int idDestino, String nombre) async {
    final dir = await _dirBase();
    return File('${dir.path}/${_nombreArchivoPdf(nombre)}');
  }

  Future<File> _metaFile(int idDestino) async {
    final base = await getApplicationDocumentsDirectory();
    final dir = Directory('${base.path}/TravelLaw/meta');
    if (!await dir.exists()) await dir.create(recursive: true);
    return File('${dir.path}/meta_$idDestino.json');
  }

  // ── API pública ────────────────────────────

  Future<PaqueteLocal?> leer(int idDestino) async {
    try {
      final meta = await _metaFile(idDestino);
      if (!await meta.exists()) return null;

      final mapa = jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
      final nombre = mapa['nombre'] as String? ?? '';
      final rutaGuardada = mapa['ruta_pdf'] as String?;

      File? pdf;
      if (rutaGuardada != null && rutaGuardada.isNotEmpty) {
        final f = File(rutaGuardada);
        if (await f.exists()) pdf = f;
      }

      pdf ??= await _pdfFile(idDestino, nombre);
      if (!await pdf.exists()) return null;

      return PaqueteLocal(
        version: mapa['version'] as String? ?? '?',
        bytes: await pdf.length(),
        rutaPdf: pdf.path,
        generadoEn: parseFecha(mapa['generado_en']),
      );
    } catch (_) {
      return null; // archivo dañado o no accesible → tratar como no descargado
    }
  }

  /// Genera el PDF en un isolate y lo guarda. Devuelve la ruta absoluta del PDF.
  Future<String> guardar(
    int idDestino,
    String nombreDestino,
    Map<String, dynamic> paquete,
  ) async {
    // 1. Serializa el paquete a String para pasarlo al isolate via compute().
    final paqueteJson = jsonEncode(paquete);

    // 2. Genera el PDF en segundo plano (no bloquea la UI).
    final pdfBytes = await compute(_buildPdfIsolate, paqueteJson);

    // 3. Escribe el PDF en el almacenamiento.
    final pdfFile = await _pdfFile(idDestino, nombreDestino);
    await pdfFile.writeAsBytes(pdfBytes);

    // 4. Guarda los metadatos con la ruta absoluta donde se guardó.
    final metaFile = await _metaFile(idDestino);
    await metaFile.writeAsString(jsonEncode({
      'version': paquete['version'] ?? '1',
      'nombre': nombreDestino,
      'ruta_pdf': pdfFile.path,
      'generado_en': DateTime.now().toIso8601String(),
    }));

    return pdfFile.path;
  }

  Future<void> eliminar(int idDestino) async {
    try {
      final meta = await _metaFile(idDestino);
      if (await meta.exists()) {
        final mapa =
            jsonDecode(await meta.readAsString()) as Map<String, dynamic>;
        final nombre = mapa['nombre'] as String? ?? '';
        final rutaGuardada = mapa['ruta_pdf'] as String?;

        if (rutaGuardada != null && rutaGuardada.isNotEmpty) {
          final f = File(rutaGuardada);
          if (await f.exists()) await f.delete();
        }

        final pdf = await _pdfFile(idDestino, nombre);
        if (await pdf.exists()) await pdf.delete();

        await meta.delete();
      }
    } catch (_) {}
  }

  /// Abre el PDF con el visor de archivos del sistema operativo.
  Future<OpenResult> abrirPdf(String ruta) => OpenFile.open(ruta);
}

// ─────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────

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

final paqueteLocalProvider =
    FutureProvider.autoDispose.family<PaqueteLocal?, int>((ref, idDestino) {
  return ref.watch(descargasServiceProvider).leer(idDestino);
});

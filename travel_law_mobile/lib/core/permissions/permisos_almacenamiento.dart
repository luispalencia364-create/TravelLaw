import 'dart:io';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

/// Gestiona el permiso de almacenamiento necesario para leer y modificar el
/// contenido de la carpeta pública de descargas (`Download/TravelLaw`) y sus
/// subcarpetas.
class PermisosAlmacenamiento {
  const PermisosAlmacenamiento._();

  /// Comprueba el permiso y, si hace falta, lo solicita al usuario.
  ///
  /// Devuelve `true` cuando la app puede leer y escribir en el almacenamiento
  /// compartido. En plataformas que no lo requieren (iOS, escritorio) devuelve
  /// `true` directamente.
  static Future<bool> solicitar(BuildContext context) async {
    if (!Platform.isAndroid) return true;

    // Android 11+ (API 30): "Acceso a todos los archivos", que permite leer y
    // modificar el contenido de la carpeta Descargas y sus subcarpetas.
    var estado = await Permission.manageExternalStorage.status;
    if (estado.isGranted) return true;

    if (estado.isRestricted) {
      // Android 10 o anterior: permiso clásico de almacenamiento.
      if (!context.mounted) return false;
      return _solicitarAlmacenamientoClasico(context);
    }

    // Explicación previa: el sistema abrirá una pantalla de ajustes.
    if (!context.mounted) return false;
    final continuar = await _mostrarExplicacion(context);
    if (continuar != true) return false;

    estado = await Permission.manageExternalStorage.request();
    if (estado.isGranted) return true;

    if (!context.mounted) return false;
    return _ofrecerAjustes(
      context,
      'Activa «Permitir acceso a todos los archivos» para que TravelLaw '
      'pueda leer y modificar la carpeta Descargas y sus subcarpetas.',
    );
  }

  static Future<bool> _solicitarAlmacenamientoClasico(
    BuildContext context,
  ) async {
    var estado = await Permission.storage.status;
    if (estado.isGranted) return true;

    estado = await Permission.storage.request();
    if (estado.isGranted) return true;

    if (!context.mounted) return false;
    return _ofrecerAjustes(
      context,
      'Concede el permiso de almacenamiento para que TravelLaw pueda '
      'guardar, leer y eliminar los PDFs de la carpeta Descargas.',
    );
  }

  static Future<bool?> _mostrarExplicacion(BuildContext context) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso de almacenamiento'),
        content: const Text(
          'TravelLaw necesita acceso a la carpeta Descargas para guardar los '
          'paquetes PDF y poder leerlos, actualizarlos o eliminarlos.\n\n'
          'En la siguiente pantalla activa «Permitir acceso a todos los '
          'archivos».',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Ahora no'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Continuar'),
          ),
        ],
      ),
    );
  }

  static Future<bool> _ofrecerAjustes(
    BuildContext context,
    String mensaje,
  ) async {
    final abrir = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Permiso necesario'),
        content: Text(mensaje),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Abrir ajustes'),
          ),
        ],
      ),
    );

    if (abrir != true) return false;

    // Abre los ajustes de la app. El usuario debe activar el permiso y volver
    // a intentar la acción; en el siguiente intento se comprobará de nuevo.
    await openAppSettings();
    return false;
  }
}

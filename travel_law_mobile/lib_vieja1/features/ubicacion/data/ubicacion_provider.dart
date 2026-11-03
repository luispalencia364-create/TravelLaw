import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

enum UbicacionStatus {
  /// Comprobando GPS y permisos.
  verificando,

  /// Permiso concedido; esperando la primera posición.
  obteniendo,

  /// Hay posición y se actualiza en tiempo real.
  activa,

  /// El GPS del teléfono está apagado.
  servicioApagado,

  /// El usuario negó el permiso (se puede volver a pedir).
  denegado,

  /// El permiso quedó bloqueado: solo se activa desde Ajustes.
  denegadoSiempre,

  error,
}

class UbicacionState {
  const UbicacionState({
    this.status = UbicacionStatus.verificando,
    this.posicion,
  });

  final UbicacionStatus status;
  final LatLng? posicion;

  UbicacionState copyWith({UbicacionStatus? status, LatLng? posicion}) {
    return UbicacionState(
      status: status ?? this.status,
      posicion: posicion ?? this.posicion,
    );
  }
}

/// Ubicación en tiempo real del dispositivo (GPS), con manejo de permisos.
/// Se activa llamando a [iniciar] y se libera con [detener].
class UbicacionNotifier extends Notifier<UbicacionState> {
  StreamSubscription<Position>? _subscription;

  @override
  UbicacionState build() {
    ref.onDispose(() => _subscription?.cancel());
    return const UbicacionState();
  }

  Future<void> iniciar() async {
    await _subscription?.cancel();
    _subscription = null;
    state = const UbicacionState(status: UbicacionStatus.verificando);

    try {
      final servicioActivo = await Geolocator.isLocationServiceEnabled();
      if (!servicioActivo) {
        state = const UbicacionState(status: UbicacionStatus.servicioApagado);
        return;
      }

      var permiso = await Geolocator.checkPermission();
      if (permiso == LocationPermission.denied) {
        permiso = await Geolocator.requestPermission();
      }
      if (permiso == LocationPermission.deniedForever) {
        state = const UbicacionState(status: UbicacionStatus.denegadoSiempre);
        return;
      }
      if (permiso == LocationPermission.denied) {
        state = const UbicacionState(status: UbicacionStatus.denegado);
        return;
      }

      state = const UbicacionState(status: UbicacionStatus.obteniendo);

      // Última posición conocida: permite pintar el mapa casi al instante.
      try {
        final ultima = await Geolocator.getLastKnownPosition();
        if (ultima != null) {
          state = UbicacionState(
            status: UbicacionStatus.activa,
            posicion: LatLng(ultima.latitude, ultima.longitude),
          );
        }
      } catch (_) {
        // No disponible en todas las plataformas (p. ej. web): se ignora.
      }

      _subscription =
          Geolocator.getPositionStream(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.high,
              distanceFilter: 10, // metros mínimos entre actualizaciones
            ),
          ).listen(
            (p) {
              state = UbicacionState(
                status: UbicacionStatus.activa,
                posicion: LatLng(p.latitude, p.longitude),
              );
            },
            onError: (_) {
              state = state.copyWith(status: UbicacionStatus.error);
            },
          );
    } catch (_) {
      state = const UbicacionState(status: UbicacionStatus.error);
    }
  }

  /// Deja de escuchar el GPS (ahorra batería al salir de la pantalla).
  Future<void> detener() async {
    await _subscription?.cancel();
    _subscription = null;
  }
}

final ubicacionProvider = NotifierProvider<UbicacionNotifier, UbicacionState>(
  UbicacionNotifier.new,
);

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../ubicacion/data/ubicacion_provider.dart';
import 'destinos_repository.dart';

/// Destino elegido manualmente por el usuario (null = automático).
class DestinoActivoNotifier extends Notifier<int?> {
  @override
  int? build() => null;

  void seleccionar(int? id) => state = id;
}

final destinoActivoProvider = NotifierProvider<DestinoActivoNotifier, int?>(
  DestinoActivoNotifier.new,
);

/// Destino con el que trabajan los módulos: el elegido, o el más cercano al
/// usuario, o el primero de la lista.
final destinoEfectivoProvider = Provider<Destino?>((ref) {
  final destinos = ref
      .watch(destinosProvider)
      .maybeWhen(data: (lista) => lista, orElse: () => const <Destino>[]);
  if (destinos.isEmpty) return null;

  final activo = ref.watch(destinoActivoProvider);
  if (activo != null) {
    for (final d in destinos) {
      if (d.id == activo) return d;
    }
  }

  final pos = ref.watch(ubicacionProvider).posicion;
  if (pos != null) {
    var mejor = destinos.first;
    var mejorDistancia = double.infinity;
    for (final d in destinos) {
      final distancia = Geolocator.distanceBetween(
        pos.latitude,
        pos.longitude,
        d.posicion.latitude,
        d.posicion.longitude,
      );
      if (distancia < mejorDistancia) {
        mejorDistancia = distancia;
        mejor = d;
      }
    }
    return mejor;
  }
  return destinos.first;
});

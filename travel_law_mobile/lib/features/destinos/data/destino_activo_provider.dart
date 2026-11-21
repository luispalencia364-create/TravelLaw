import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

import '../../auth/data/auth_repository.dart';
import '../../auth/data/perfil_provider.dart';
import '../../ubicacion/data/ubicacion_provider.dart';
import 'destinos_repository.dart';

/// Destino elegido manualmente por el usuario (null = automático).
class DestinoActivoNotifier extends Notifier<int?> {
  @override
  int? build() {
    // Restaura el destino que el viajero eligió en una sesión anterior.
    ref.listen(perfilProvider, (anterior, siguiente) {
      if (!siguiente.hasValue) return;
      final id = siguiente.asData?.value?.idDestinoActivo;
      if (id != null) {
        if (state == null) state = id;
      } else {
        state = null;
      }
    });

    return ref.read(perfilProvider).asData?.value?.idDestinoActivo;
  }

  void seleccionar(int? id) {
    state = id;
    if (id != null) _guardarEnServidor(id);
  }

  /// Persiste el destino activo para que las alertas de esa zona puedan
  /// notificar al viajero. Un fallo de red no debe romper la navegación.
  Future<void> _guardarEnServidor(int id) async {
    final client = ref.read(supabaseProvider);
    if (client.auth.currentUser?.id == null) return;
    try {
      await client.rpc(
        'actualizar_mi_contexto',
        params: {'p_id_destino': id},
      );
    } catch (e) {
      debugPrint('No se pudo guardar el destino activo: $e');
    }
  }
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

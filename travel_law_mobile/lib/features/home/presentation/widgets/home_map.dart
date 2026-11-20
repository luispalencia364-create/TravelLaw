import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/config/app_constants.dart';
import '../../../destinos/data/destinos_repository.dart';
import '../../../lugares/data/lugares_repository.dart';
import '../../../ubicacion/data/ubicacion_provider.dart';

/// Centro aproximado del departamento de Córdoba (vista inicial del mapa).
final LatLng _centroCordoba = LatLng(8.95, -75.85);

/// Mapa principal (RI-02): destinos, ubicación del usuario en tiempo real y
/// estado del permiso de ubicación. Requiere conexión (teselas de OpenStreetMap).
class HomeMap extends ConsumerWidget {
  const HomeMap({
    super.key,
    required this.controller,
    required this.destinos,
    required this.seleccionado,
    this.lugarSeleccionado,
    required this.onSelect,
    required this.onMapReady,
    required this.onCentrar,
  });

  final MapController controller;
  final List<Destino> destinos;
  final Destino? seleccionado;
  final LugarPublico? lugarSeleccionado;
  final ValueChanged<Destino> onSelect;
  final VoidCallback onMapReady;
  final VoidCallback onCentrar;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final ubicacion = ref.watch(ubicacionProvider);
    final scheme = Theme.of(context).colorScheme;
    final posicionUsuario = ubicacion.posicion;

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 320,
        child: Stack(
          children: [
            FlutterMap(
              mapController: controller,
              options: MapOptions(
                initialCenter: _centroCordoba,
                initialZoom: 8,
                minZoom: 3,
                maxZoom: 18,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                ),
                onMapReady: onMapReady,
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: kAppPackage,
                ),
                MarkerLayer(
                  markers: [
                    for (final d in destinos)
                      Marker(
                        point: d.posicion,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: GestureDetector(
                          onTap: () => onSelect(d),
                          child: Icon(
                            Icons.location_on,
                            size: 44,
                            color: d.id == seleccionado?.id
                                ? scheme.error
                                : scheme.primary,
                          ),
                        ),
                      ),
                    if (lugarSeleccionado != null)
                      Marker(
                        point: lugarSeleccionado!.posicion,
                        width: 44,
                        height: 44,
                        alignment: Alignment.topCenter,
                        child: Icon(
                          Icons.place,
                          size: 42,
                          color: scheme.tertiary,
                        ),
                      ),
                    if (posicionUsuario != null)
                      Marker(
                        point: posicionUsuario,
                        width: 22,
                        height: 22,
                        child: const _PuntoUsuario(),
                      ),
                  ],
                ),
                RichAttributionWidget(
                  attributions: [
                    TextSourceAttribution('OpenStreetMap contributors'),
                  ],
                ),
              ],
            ),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _EstadoUbicacion(estado: ubicacion),
            ),
            if (posicionUsuario != null)
              Positioned(
                right: 8,
                bottom: 32,
                child: FloatingActionButton.small(
                  heroTag: null,
                  tooltip: 'Centrar en mi ubicación',
                  onPressed: onCentrar,
                  child: const Icon(Icons.my_location),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Punto azul de "estás aquí".
class _PuntoUsuario extends StatelessWidget {
  const _PuntoUsuario();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.blue,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: const [BoxShadow(blurRadius: 6, color: Colors.black38)],
      ),
    );
  }
}

/// Aviso sobre el mapa según el estado del GPS y del permiso.
class _EstadoUbicacion extends ConsumerWidget {
  const _EstadoUbicacion({required this.estado});

  final UbicacionState estado;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(ubicacionProvider.notifier);

    switch (estado.status) {
      case UbicacionStatus.activa:
        return const SizedBox.shrink();
      case UbicacionStatus.verificando:
      case UbicacionStatus.obteniendo:
        return const _Aviso(mensaje: 'Buscando tu ubicación…', cargando: true);
      case UbicacionStatus.servicioApagado:
        return _Aviso(
          mensaje: 'El GPS está desactivado. Actívalo para ver tu ubicación.',
          accion: 'Activar GPS',
          onAccion: Geolocator.openLocationSettings,
        );
      case UbicacionStatus.denegado:
        return _Aviso(
          mensaje:
              'Permite el acceso a tu ubicación para ver destinos y '
              'alertas cerca de ti.',
          accion: 'Permitir',
          onAccion: notifier.iniciar,
        );
      case UbicacionStatus.denegadoSiempre:
        return _Aviso(
          mensaje:
              'El permiso de ubicación está bloqueado. '
              'Actívalo en los ajustes de la app.',
          accion: 'Abrir ajustes',
          onAccion: Geolocator.openAppSettings,
        );
      case UbicacionStatus.error:
        return _Aviso(
          mensaje: 'No se pudo obtener tu ubicación.',
          accion: 'Reintentar',
          onAccion: notifier.iniciar,
        );
    }
  }
}

class _Aviso extends StatelessWidget {
  const _Aviso({
    required this.mensaje,
    this.accion,
    this.onAccion,
    this.cargando = false,
  });

  final String mensaje;
  final String? accion;
  final Future<void> Function()? onAccion;
  final bool cargando;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            if (cargando) ...[
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
              const SizedBox(width: 12),
            ] else ...[
              const Icon(Icons.location_off_outlined, size: 20),
              const SizedBox(width: 8),
            ],
            Expanded(child: Text(mensaje)),
            if (accion != null && onAccion != null) ...[
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: () => onAccion!(),
                child: Text(accion!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

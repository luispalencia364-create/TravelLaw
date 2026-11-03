import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/alertas_repository.dart';

class AlertasPage extends StatelessWidget {
  const AlertasPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Alertas y reportes'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Vigentes'),
              Tab(text: 'Mis alertas'),
            ],
          ),
        ),
        body: ConDestino(
          builder: (context, destino) => TabBarView(
            children: [
              Consumer(
                builder: (context, ref, _) => AsyncListView<AlertaItem>(
                  value: ref.watch(alertasDestinoProvider(destino.id)),
                  emptyIcon: Icons.notifications_off_outlined,
                  emptyMessage: 'Sin alertas en ${destino.nombre}',
                  emptyDetail:
                      'Cuando alguien reporte un riesgo aparecerá aquí.',
                  onRefresh: () async {
                    await ref.refresh(
                      alertasDestinoProvider(destino.id).future,
                    );
                  },
                  itemBuilder: (context, a) => _AlertaCard(alerta: a),
                ),
              ),
              Consumer(
                builder: (context, ref, _) => AsyncListView<AlertaItem>(
                  value: ref.watch(misAlertasProvider),
                  emptyIcon: Icons.edit_notifications_outlined,
                  emptyMessage: 'Aún no has creado alertas',
                  onRefresh: () async {
                    await ref.refresh(misAlertasProvider.future);
                  },
                  itemBuilder: (context, a) => _AlertaCard(alerta: a),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

IconData _iconoTipo(String tipo) {
  switch (tipo) {
    case 'emergencia':
      return Icons.emergency_outlined;
    case 'cierre_vial':
      return Icons.block_outlined;
    case 'clima':
      return Icons.thunderstorm_outlined;
    case 'riesgo':
      return Icons.warning_amber_outlined;
    default:
      return Icons.info_outline;
  }
}

String _nombreTipo(String tipo) {
  switch (tipo) {
    case 'cierre_vial':
      return 'Cierre vial';
    case 'emergencia':
      return 'Emergencia';
    case 'clima':
      return 'Clima';
    case 'riesgo':
      return 'Riesgo';
    default:
      return 'Otro';
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.alerta});

  final AlertaItem alerta;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final verificada = alerta.estado == 'verificada';
    final etiqueta = switch (alerta.estado) {
      'verificada' => 'Verificada',
      'pendiente_moderacion' => 'Sin verificar',
      'rechazada' => 'Rechazada',
      'vencida' => 'Vencida',
      _ => alerta.estado,
    };

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ListTile(
        leading: Icon(_iconoTipo(alerta.tipo), color: scheme.primary),
        title: Text(_nombreTipo(alerta.tipo)),
        subtitle: Text(
          '${alerta.descripcion}\n${fechaRelativa(alerta.fechaEvento)}',
        ),
        isThreeLine: true,
        trailing: Chip(
          label: Text(etiqueta),
          avatar: Icon(
            verificada ? Icons.verified_outlined : Icons.help_outline,
            size: 16,
          ),
          visualDensity: VisualDensity.compact,
        ),
      ),
    );
  }
}

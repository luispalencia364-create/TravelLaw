import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../auth/data/perfil_provider.dart';
import '../../destinos/data/destino_activo_provider.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/alertas_repository.dart';
import 'crear_alerta_dialog.dart';

class AlertasPage extends ConsumerWidget {
  const AlertasPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final perfil = ref.watch(perfilProvider).asData?.value;
    final destino = ref.watch(destinoEfectivoProvider);
    final puedeReportar =
        perfil != null && !perfil.esAdministrador && !perfil.esModerador;

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
        floatingActionButton: puedeReportar && destino != null
            ? FloatingActionButton.extended(
                onPressed: () async {
                  final creada = await showDialog<bool>(
                    context: context,
                    builder: (_) => CrearAlertaDialog(destino: destino),
                  );
                  if (creada == true && context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Alerta enviada. Quedará visible cuando un '
                          'moderador la verifique.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.add_alert_outlined),
                label: const Text('Reportar alerta'),
              )
            : null,
        body: ConDestino(
          builder: (context, destino) => TabBarView(
            children: [
              AsyncListView<AlertaItem>(
                value: ref.watch(alertasDestinoProvider(destino.id)),
                emptyIcon: Icons.notifications_off_outlined,
                emptyMessage: 'Sin alertas en ${destino.nombre}',
                emptyDetail:
                    'Cuando un moderador verifique un reporte aparecerá aquí.',
                onRefresh: () async {
                  ref.invalidate(alertasDestinoProvider(destino.id));
                  await ref.read(alertasDestinoProvider(destino.id).future);
                },
                itemBuilder: (context, a) => _AlertaCard(alerta: a),
              ),
              AsyncListView<AlertaItem>(
                value: ref.watch(misAlertasProvider),
                emptyIcon: Icons.edit_notifications_outlined,
                emptyMessage: 'Aún no has creado alertas',
                onRefresh: () async {
                  ref.invalidate(misAlertasProvider);
                  await ref.read(misAlertasProvider.future);
                },
                itemBuilder: (context, a) => _AlertaCard(alerta: a),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AlertaCard extends StatelessWidget {
  const _AlertaCard({required this.alerta});

  final AlertaItem alerta;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final esVerificada = alerta.estado == 'verificada';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  esVerificada
                      ? Icons.warning_amber_rounded
                      : Icons.hourglass_top_rounded,
                  color: esVerificada
                      ? Colors.amber.shade800
                      : theme.colorScheme.secondary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    capitalizar(alerta.tipo),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                if (alerta.fechaEvento != null)
                  Text(
                    fechaRelativa(alerta.fechaEvento),
                    style: theme.textTheme.bodySmall,
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Text(alerta.descripcion),
            const SizedBox(height: 6),
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                capitalizar(alerta.estado.replaceAll('_', ' ')),
                style: theme.textTheme.labelSmall?.copyWith(
                  color: esVerificada
                      ? Colors.green.shade700
                      : theme.colorScheme.outline,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

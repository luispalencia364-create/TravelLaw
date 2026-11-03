import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/text_utils.dart';
import '../../../core/widgets/empty_state.dart';
import '../../destinos/presentation/destino_selector.dart';
import '../data/precios_repository.dart';

class PreciosPage extends StatelessWidget {
  const PreciosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Precios y cobros'),
          bottom: const TabBar(
            tabs: [
              Tab(text: 'Precios de referencia'),
              Tab(text: 'Mis reportes'),
            ],
          ),
        ),
        body: ConDestino(
          builder: (context, destino) => TabBarView(
            children: [
              Consumer(
                builder: (context, ref, _) => AsyncListView<PrecioReferencia>(
                  value: ref.watch(preciosProvider(destino.id)),
                  emptyIcon: Icons.request_quote_outlined,
                  emptyMessage:
                      'Sin precios de referencia en ${destino.nombre}',
                  onRefresh: () async {
                    await ref.refresh(preciosProvider(destino.id).future);
                  },
                  itemBuilder: (context, p) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.sell_outlined),
                      title: Text(p.servicio),
                      subtitle: Text(
                        [
                          if (p.lugar != null) p.lugar!,
                          'Actualizado ${formatearFecha(p.fechaActualizacion)}',
                          if (p.fuente != null && p.fuente!.isNotEmpty)
                            'Fuente: ${p.fuente}',
                        ].join('\n'),
                      ),
                      isThreeLine: p.lugar != null,
                      trailing: Text(
                        '${formatearPesos(p.minimo)}\n- ${formatearPesos(p.maximo)}',
                        textAlign: TextAlign.right,
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                    ),
                  ),
                ),
              ),
              Consumer(
                builder: (context, ref, _) => AsyncListView<ReporteCobro>(
                  value: ref.watch(misReportesCobroProvider),
                  emptyIcon: Icons.receipt_long_outlined,
                  emptyMessage: 'Aún no has reportado cobros',
                  onRefresh: () async {
                    await ref.refresh(misReportesCobroProvider.future);
                  },
                  itemBuilder: (context, r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: const Icon(Icons.report_gmailerrorred_outlined),
                      title: Text(r.servicio),
                      subtitle: Text(
                        'Pagaste ${formatearPesos(r.precioPagado)}  ·  '
                        '${formatearFecha(r.fecha)}',
                      ),
                      trailing: Chip(
                        label: Text(switch (r.estado) {
                          'revisado' => 'Revisado',
                          'rechazado' => 'Rechazado',
                          _ => 'En revisión',
                        }),
                        visualDensity: VisualDensity.compact,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

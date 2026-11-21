import 'package:flutter/material.dart';

/// Filtro horizontal de "desde hace N días" para los módulos de contenido.
///
/// `0` significa "Todo" (sin límite de fecha).
class FiltroDias extends StatelessWidget {
  const FiltroDias({
    super.key,
    required this.valor,
    required this.onChanged,
    this.opciones = const [7, 30, 90, 365, 0],
  });

  final int valor;
  final ValueChanged<int> onChanged;
  final List<int> opciones;

  String _etiqueta(int dias) {
    return switch (dias) {
      0 => 'Todo',
      7 => '7 días',
      30 => '30 días',
      90 => '90 días',
      365 => '1 año',
      _ => '$dias días',
    };
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
        itemCount: opciones.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final dias = opciones[i];
          return ChoiceChip(
            label: Text(_etiqueta(dias)),
            selected: valor == dias,
            onSelected: (_) => onChanged(dias),
          );
        },
      ),
    );
  }
}

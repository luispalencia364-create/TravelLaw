const String _conTilde = 'áàäâéèëêíìïîóòöôúùüûñ';
const String _sinTilde = 'aaaaeeeeiiiioooouuuun';

/// Minúsculas y sin tildes, para búsquedas ("monteria" encuentra "Montería").
String normalizar(String texto) {
  final buffer = StringBuffer();
  for (final rune in texto.toLowerCase().runes) {
    final caracter = String.fromCharCode(rune);
    final i = _conTilde.indexOf(caracter);
    buffer.write(i >= 0 ? _sinTilde[i] : caracter);
  }
  return buffer.toString();
}

String capitalizar(String texto) {
  if (texto.isEmpty) return texto;
  return texto[0].toUpperCase() + texto.substring(1);
}

/// "850 m" o "12.3 km".
String formatearDistancia(double metros) {
  if (metros < 1000) return '${metros.round()} m';
  return '${(metros / 1000).toStringAsFixed(1)} km';
}

/// Convierte el valor que llega de Supabase (texto ISO) en fecha local.
DateTime? parseFecha(Object? valor) {
  return DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
}

/// "05/11/2026".
String formatearFecha(DateTime? fecha) {
  if (fecha == null) return '—';
  return '${fecha.day.toString().padLeft(2, '0')}/'
      '${fecha.month.toString().padLeft(2, '0')}/${fecha.year}';
}

/// "hace 5 min", "hace 3 h", "hace 2 d" o la fecha si es más antigua.
String fechaRelativa(DateTime? fecha) {
  if (fecha == null) return '—';
  final diff = DateTime.now().difference(fecha);
  if (diff.isNegative) return formatearFecha(fecha);
  if (diff.inMinutes < 1) return 'hace un momento';
  if (diff.inMinutes < 60) return 'hace ${diff.inMinutes} min';
  if (diff.inHours < 24) return 'hace ${diff.inHours} h';
  if (diff.inDays < 7) return 'hace ${diff.inDays} d';
  return formatearFecha(fecha);
}

/// Pesos colombianos con separador de miles: "\$ 15.000".
String formatearPesos(num valor) {
  final entero = valor.round().toString();
  final buffer = StringBuffer();
  for (var i = 0; i < entero.length; i++) {
    final restantes = entero.length - i;
    buffer.write(entero[i]);
    if (restantes > 1 && restantes % 3 == 1) buffer.write('.');
  }
  return '\$ ${buffer.toString()}';
}

/// Elige el texto según el idioma; si falta la versión en inglés, usa español.
String textoIdioma(String idioma, String es, String? en) {
  if (idioma == 'en' && en != null && en.trim().isNotEmpty) return en;
  return es;
}

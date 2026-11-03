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

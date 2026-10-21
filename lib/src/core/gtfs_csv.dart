/// Parses one GTFS CSV [line] into trimmed fields.
///
/// Handles double-quoted fields containing commas; the quote characters
/// themselves are dropped. Lines without any quote (the vast majority of GTFS
/// rows) take a `split` fast path.
List<String> parseGtfsCsvRow(String line) {
  if (!line.contains('"')) {
    final parts = line.split(',');
    for (var i = 0; i < parts.length; i++) {
      parts[i] = parts[i].trim();
    }
    return parts;
  }

  final values = <String>[];
  final buffer = StringBuffer();
  var inQuotes = false;

  for (var i = 0; i < line.length; i++) {
    final c = line.codeUnitAt(i);
    if (c == 0x22) {
      inQuotes = !inQuotes;
    } else if (c == 0x2C && !inQuotes) {
      values.add(buffer.toString().trim());
      buffer.clear();
    } else {
      buffer.writeCharCode(c);
    }
  }
  values.add(buffer.toString().trim());
  return values;
}

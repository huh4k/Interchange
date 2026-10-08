import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/core/gtfs_csv.dart';

/// The pre-optimisation parser, kept verbatim as the oracle.
List<String> _oldParse(String line) {
  final values = <String>[];
  final buffer = StringBuffer();
  bool inQuotes = false;
  for (int i = 0; i < line.length; i++) {
    final char = line[i];
    if (char == '"') {
      inQuotes = !inQuotes;
    } else if (char == ',' && !inQuotes) {
      values.add(buffer.toString().trim().replaceAll('"', ''));
      buffer.clear();
    } else {
      buffer.write(char);
    }
  }
  values.add(buffer.toString().trim().replaceAll('"', ''));
  return values;
}

void main() {
  const lines = [
    '',
    'a',
    'a,b,c',
    ' a , b ,c ',
    ',,',
    '"a","b","c"',
    '"a,b",c,"d, e ,f"',
    'stop_id,stop_name,stop_lat',
    '"11212","Flinders Street Railway Station","-37.8","https://x/stop/1071/?a=b,c","",',
    'a,"unterminated,b',
    'a,"he said ""hi""",b',
    '﻿stop_id,stop_name',
    'é,"ü, ñ",😀',
    'trailing,',
    '"quoted",,"",x',
  ];

  test('parseGtfsCsvRow matches the original parser on a corpus', () {
    for (final line in lines) {
      expect(parseGtfsCsvRow(line), _oldParse(line), reason: 'line: $line');
    }
  });

  test('parseGtfsCsvRow keeps commas inside quoted fields', () {
    expect(parseGtfsCsvRow('"a,b",c'), ['a,b', 'c']);
  });
}

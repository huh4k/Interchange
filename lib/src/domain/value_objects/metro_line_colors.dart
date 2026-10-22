import 'dart:ui';

import 'transit_type.dart';

/// Official colours for Melbourne metro train lines, keyed by line name.
const Map<String, ({String code, Color color})> _metroLines = {
  'alamein': (code: 'ALM', color: Color(0xFF0072CE)),
  'belgrave': (code: 'BEL', color: Color(0xFF0072CE)),
  'craigieburn': (code: 'CGB', color: Color(0xFFFFBE00)),
  'cranbourne': (code: 'CRN', color: Color(0xFF009B77)),
  'frankston': (code: 'FKN', color: Color(0xFF009B77)),
  'glen waverley': (code: 'GLW', color: Color(0xFF0072CE)),
  'hurstbridge': (code: 'HUR', color: Color(0xFFE11B22)),
  'lilydale': (code: 'LIL', color: Color(0xFF0072CE)),
  'mernda': (code: 'MER', color: Color(0xFFE11B22)),
  'pakenham': (code: 'PAK', color: Color(0xFF009B77)),
  'sandringham': (code: 'SAN', color: Color(0xFFF37021)),
  'stony point': (code: 'STY', color: Color(0xFF009B77)),
  'sunbury': (code: 'SUN', color: Color(0xFFFFBE00)),
  'upfield': (code: 'UPF', color: Color(0xFFFFBE00)),
  'werribee': (code: 'WER', color: Color(0xFF009B77)),
  'williamstown': (code: 'WIL', color: Color(0xFF009B77)),
  'flemington': (code: 'FLM', color: Color(0xFFFFBE00)),
};

/// The colour of a metro train line from its [name] or 3-letter [code]
/// (either may be empty), or null when it isn't a known line.
Color? metroLineColor({String name = '', String code = ''}) {
  final c = code.trim().toUpperCase();
  final n = name.trim().toLowerCase();
  for (final e in _metroLines.entries) {
    if (c.isNotEmpty && e.value.code == c) return e.value.color;
    if (n.isNotEmpty && n.contains(e.key)) return e.value.color;
  }
  return null;
}

/// Colour for a line pill: the metro line colour for trains, otherwise the
/// mode's brand colour.
Color lineColorFor(TransitType type, {String name = '', String code = ''}) =>
    (type == TransitType.metro ? metroLineColor(name: name, code: code) : null) ??
    type.ptvBrandColor;

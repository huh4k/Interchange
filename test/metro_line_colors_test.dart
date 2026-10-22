import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/domain/value_objects/metro_line_colors.dart';
import 'package:interchange/src/domain/value_objects/transit_type.dart';

void main() {
  test('metro lines resolve by name or code', () {
    expect(metroLineColor(name: 'Frankston'), const Color(0xFF009B77));
    expect(metroLineColor(code: 'sun'), const Color(0xFFFFBE00));
    expect(metroLineColor(name: 'Mernda Line'), const Color(0xFFE11B22));
    expect(metroLineColor(name: 'Unknown'), isNull);
  });

  test('non-metro modes keep their brand colour', () {
    expect(lineColorFor(TransitType.tram, name: 'Frankston'),
        TransitType.tram.ptvBrandColor);
    expect(lineColorFor(TransitType.metro, name: 'Nowhere'),
        TransitType.metro.ptvBrandColor);
  });
}

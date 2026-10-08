import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/core/heavy_work.dart';
import 'package:transit_app/src/domain/entities/station.dart';

void main() {
  test('runHeavy runs small payloads inline', () async {
    expect(await runHeavy(10, () => 1 + 1), 2);
  });

  test('runHeavy runs large payloads on an isolate', () async {
    final text = 'a,b\n' * 10;
    final lines = await runHeavy(1 << 20, () => text.split('\n').length);
    expect(lines, 11);
  });

  test('Station.isSameStopAs matches ids and normalised names', () {
    Station st(String id, String stopId, String name) => Station(
          id: id,
          stopId: stopId,
          name: name,
          code: '',
          lat: 0,
          lon: 0,
          suburb: '',
          zone: '',
          routes: const [],
        );
    expect(st('1', '10', 'Flinders  Street').isSameStopAs(st('2', '10', 'x')), isTrue);
    expect(st('1', '', 'Flinders Street').isSameStopAs(st('2', '', 'flinders   street')), isTrue);
    expect(st('', '', 'A').isSameStopAs(st('', '', 'B')), isFalse);
  });
}

import 'package:flutter_test/flutter_test.dart';
import 'package:transit_app/src/domain/value_objects/transfer_feasibility.dart';

void main() {
  group('TransferFeasibility Tests', () {
    test('1 min buffer is evaluated as tight connection', () {
      final feasibility = TransferFeasibility.fromBuffer(const Duration(minutes: 1));
      expect(feasibility, equals(TransferFeasibility.tight));
      expect(feasibility.label, equals('Tight Connection'));
      expect(feasibility.isFeasible, isTrue);
    });

    test('2 min buffer is evaluated as possible connection', () {
      final feasibility = TransferFeasibility.fromBuffer(const Duration(minutes: 2));
      expect(feasibility, equals(TransferFeasibility.possible));
      expect(feasibility.label, equals('Possible'));
      expect(feasibility.isFeasible, isTrue);
    });

    test('3 min buffer is evaluated as easy connection', () {
      final feasibility = TransferFeasibility.fromBuffer(const Duration(minutes: 3));
      expect(feasibility, equals(TransferFeasibility.easy));
      expect(feasibility.label, equals('Easy'));
      expect(feasibility.isFeasible, isTrue);
    });

    test('4+ min buffer is evaluated as guaranteed connection', () {
      final fourMins = TransferFeasibility.fromBuffer(const Duration(minutes: 4));
      final tenMins = TransferFeasibility.fromBuffer(const Duration(minutes: 10));

      expect(fourMins, equals(TransferFeasibility.guaranteed));
      expect(tenMins, equals(TransferFeasibility.guaranteed));
      expect(fourMins.label, equals('Guaranteed Connection'));
      expect(fourMins.isFeasible, isTrue);
    });

    test('Buffer under 1 min is evaluated as missed / infeasible', () {
      final thirtySecs = TransferFeasibility.fromBuffer(const Duration(seconds: 30));
      final negative = TransferFeasibility.fromBuffer(const Duration(minutes: -2));

      expect(thirtySecs, equals(TransferFeasibility.missed));
      expect(negative, equals(TransferFeasibility.missed));
      expect(thirtySecs.isFeasible, isFalse);
    });
  });
}

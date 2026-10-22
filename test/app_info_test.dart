import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:interchange/src/core/app_info.dart';
import 'package:interchange/src/presentation/widgets/app_header_widget.dart';

void main() {
  test('appVersion matches pubspec.yaml', () {
    final line = File('pubspec.yaml')
        .readAsLinesSync()
        .firstWhere((l) => l.startsWith('version:'));
    expect(line.split(':')[1].trim().split('+').first, appVersion);
  });

  testWidgets('header shows the version', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: AppHeaderWidget(isLoading: false, onRefresh: () {})),
    ));
    expect(find.text('v$appVersion'), findsOneWidget);
  });
}

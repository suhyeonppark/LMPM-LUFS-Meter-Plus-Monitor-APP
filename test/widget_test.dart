import 'package:flutter_test/flutter_test.dart';

import 'package:lufs_monitor/main.dart';

void main() {
  testWidgets('shows LUFS monitor shell', (WidgetTester tester) async {
    await tester.pumpWidget(const LufsMonitorApp());

    expect(find.text('LMPM'), findsOneWidget);
    expect(find.text('INTEGRATED'), findsOneWidget);
    expect(find.text('MOMENTARY'), findsOneWidget);
    expect(find.text('SHORT-TERM'), findsOneWidget);
  });
}

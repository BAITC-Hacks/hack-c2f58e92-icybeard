import 'package:darumen/screens/home_screen.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('home shows citizen cards and doctor cards after switching role', (tester) async {
    final session = Session(baseUrl: 'http://localhost:8000');
    await tester.pumpWidget(ChangeNotifierProvider.value(value: session, child: const MaterialApp(home: HomeScreen())));
    expect(find.text('Сколько ждать'), findsOneWidget);
    expect(find.text('Рабочий список'), findsNothing);
    await tester.tap(find.text('Врач'));
    await tester.pumpAndSettle();
    expect(find.text('Рабочий список'), findsOneWidget);
    expect(session.isDoctor, isTrue);
  });
}

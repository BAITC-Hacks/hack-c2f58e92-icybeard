import 'package:darumen/widgets/darumen_mark.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('intro covers the app, then reveals it after the animation', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: DarumenIntro(duration: Duration(milliseconds: 200), child: Scaffold(body: Text('app')))));
    await tester.pump();
    expect(find.text('darumen'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
    expect(find.text('darumen'), findsNothing);
    expect(find.text('app'), findsOneWidget);
  });

  testWidgets('reduced motion skips the animation', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: MaterialApp(home: DarumenIntro(child: Scaffold(body: Text('app')))),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('darumen'), findsNothing);
  });

  testWidgets('static mark paints without errors at any size', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Center(child: DarumenMark(size: 96))));
    expect(find.byType(CustomPaint), findsWidgets);
  });
}

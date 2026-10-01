import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/scribe_record_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Карточка записи приёма (ScribeRecordCard) сама по себе: во время записи — таймер мм:сс, волна уровней,
/// «Остановить»; вставка текста и отмена записи неактивны, пока идёт запись; заметка о модели.
Future<void> pumpCard(WidgetTester tester, Widget card) => tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: Scaffold(body: SingleChildScrollView(child: card)),
    ));

void main() {
  final ru = S.of('ru');

  testWidgets('идёт запись: таймер, волна, «Остановить»; вставка и отмена заблокированы', (tester) async {
    var stopped = 0;
    await pumpCard(
      tester,
      ScribeRecordCard(
        recording: true,
        seconds: 65,
        levels: const [0, 0.2, 0.8, 1],
        language: ru.aiScribeLangKk,
        note: ru.aiScribeModelFake,
        onRecord: () {},
        onStop: () => stopped++,
        onPaste: () {},
        onDiscard: () {},
      ),
    );
    expect(find.text('01:05'), findsOneWidget);
    expect(find.text('Қазақша'), findsOneWidget);
    expect(find.text(ru.aiScribeModelFake), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNWidgets(4), reason: 'по столбику на уровень');
    expect(find.text(ru.aiScribeRecordMic), findsNothing);
    await tester.tap(find.text(ru.scribeStopButton));
    expect(stopped, 1);
    ButtonStyleButton button(String label) =>
        tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(label), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton)));
    expect(button(ru.aiScribePasteText).enabled, isFalse);
    expect(button(ru.aiScribeDiscard).enabled, isFalse);
    expect(find.text(ru.aiScribeDiscardHint), findsOneWidget);
  });

  testWidgets('до записи: «Записать с микрофона», без волны; null у колбэка — кнопка неактивна', (tester) async {
    await pumpCard(tester, ScribeRecordCard(recording: false, seconds: 0, levels: const [0, 0], language: ru.aiScribeLangRu, onStop: () {}, onPaste: () {}));
    expect(find.text('00:00'), findsOneWidget);
    expect(find.byType(AnimatedContainer), findsNothing);
    expect(tester.widget<ButtonStyleButton>(find.ancestor(of: find.text(ru.aiScribeRecordMic), matching: find.byWidgetPredicate((w) => w is ButtonStyleButton))).enabled, isFalse);
  });
}

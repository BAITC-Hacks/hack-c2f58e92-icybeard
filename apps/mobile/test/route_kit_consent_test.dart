import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/widgets/route/consent_chip.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Чип согласия пациента на перевод (IncomingReferralsView.vue: CONSENT_TONES; RouteCitizenView.vue: ответ врача):
/// согласился — ok, ждём — warn, отказался и незнакомое — нейтральный; подпись — по голосу.
Widget host(Widget child, {String locale = 'ru', double textScale = 1.0}) => MaterialApp(
      theme: AppTheme.light(),
      locale: Locale(locale),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(textScale), size: const Size(360, 800)),
        child: Scaffold(body: Center(child: SizedBox(width: 296, child: Wrap(children: [child])))),
      ),
    );

void main() {
  test('тон по согласию: accepted — ok, pending — warn, declined и незнакомое — neutral', () {
    expect(consentTone('accepted'), StatusTone.ok);
    expect(consentTone('pending'), StatusTone.warn);
    expect(consentTone('declined'), StatusTone.neutral);
    expect(consentTone('revoked'), StatusTone.neutral);
  });

  testWidgets('персоналу — «ждём согласия пациента», гражданину — «Вы согласились на перевод»', (tester) async {
    await tester.pumpWidget(host(const ConsentChip('pending', voice: RouteVoice.staff)));
    var chip = tester.widget<StatusChip>(find.byType(StatusChip));
    expect(chip.label, 'ждём согласия пациента');
    expect(chip.tone, StatusTone.warn);
    await tester.pumpWidget(host(const ConsentChip('accepted', voice: RouteVoice.citizen)));
    chip = tester.widget<StatusChip>(find.byType(StatusChip));
    expect(chip.label, 'Вы согласились на перевод');
    expect(chip.tone, StatusTone.ok);
  });

  testWidgets('KK и крупный шрифт: подпись по-казахски, без переполнения', (tester) async {
    await tester.pumpWidget(host(const ConsentChip('pending', voice: RouteVoice.staff), locale: 'kk', textScale: 1.3));
    expect(tester.widget<StatusChip>(find.byType(StatusChip)).label, 'пациенттің келісімін күтудеміз');
    expect(tester.takeException(), isNull);
  });
}

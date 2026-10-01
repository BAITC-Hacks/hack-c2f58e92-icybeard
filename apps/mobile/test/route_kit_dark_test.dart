import 'dart:convert';
import 'dart:io';

import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/theme/app_theme.dart';
import 'package:darumen/theme/tokens.dart';
import 'package:darumen/theme/tones.dart';
import 'package:darumen/widgets/route/alternative_tile.dart';
import 'package:darumen/widgets/route/checklist_groups.dart';
import 'package:darumen/widgets/route/consent_chip.dart';
import 'package:darumen/widgets/route/forecast_factors.dart';
import 'package:darumen/widgets/route/priority_badge.dart';
import 'package:darumen/widgets/route/route_journal.dart';
import 'package:darumen/widgets/route/stage_list.dart';
import 'package:darumen/widgets/route/stage_strip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

/// Весь набор маршрута в тёмной теме: цвета берутся из активной темы (AppPalette / AppTones), а не из светлых
/// констант, и ничего не переполняется (KK, шрифт 1.3, 360 dp).
void main() {
  testWidgets('тёмная тема: набор маршрута рисуется токенами тёмной темы без переполнения', (tester) async {
    final json = jsonDecode(File('test/fixtures/api/route-me.json').readAsStringSync()) as Map<String, dynamic>;
    final route = PatientRoute.fromJson(json);
    final doctor = PatientRoute.fromJson(jsonDecode(File('test/fixtures/api/route-doctor.json').readAsStringSync()) as Map<String, dynamic>);
    final s = S.of('kk');
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.dark(),
      locale: const Locale('kk'),
      supportedLocales: const [Locale('ru'), Locale('kk')],
      localizationsDelegates: const [GlobalMaterialLocalizations.delegate, GlobalWidgetsLocalizations.delegate, GlobalCupertinoLocalizations.delegate],
      home: MediaQuery(
        data: const MediaQueryData(textScaler: TextScaler.linear(1.3), size: Size(360, 800)),
        child: Scaffold(
          body: Center(
            child: SizedBox(
              width: 296,
              child: SingleChildScrollView(
                child: Column(children: [
                  const Wrap(children: [PriorityBadge(9), ConsentChip('pending', voice: RouteVoice.staff)]),
                  StageStrip(stages: route.timeline),
                  StageList(stages: route.timeline),
                  ForecastFactorList(items: forecastFactors(doctor.doctor!.shap!.factors, s), lead: s.factorsLead),
                  for (final a in route.alternatives) AlternativeTile(alternative: a, baselineDays: 4.4),
                  RouteJournal(entries: route.journal, voice: RouteVoice.citizen),
                  ChecklistGroups(items: route.checklist, standard: route.standard),
                ]),
              ),
            ),
          ),
        ),
      ),
    ));
    expect(tester.takeException(), isNull);
    const dark = ColorTokens.dark;
    final tones = AppTones.from(dark);
    final dot = find.descendant(of: find.byKey(const ValueKey('journal-dot-redirect')).first, matching: find.byType(Container)).first;
    expect((tester.widget<Container>(dot).decoration! as BoxDecoration).color, dark.accentSubtle);
    expect(tester.widget<ColoredBox>(find.byKey(const ValueKey('checklist-bar-expired'))).color, tones.danger.fg);
    expect(tester.widget<Text>(find.text('≈ 2')).style?.color, tones.ok.fg, reason: '031N: ≈ 2 при своей ≈ 4 — быстрее');
    expect(tester.widget<Text>(find.text('Перевод')).style?.color, dark.accentHover, reason: 'текущий этап (заголовок сервера)');
  });
}

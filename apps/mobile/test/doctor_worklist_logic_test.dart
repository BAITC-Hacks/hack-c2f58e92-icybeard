import 'package:darumen/api/models.dart';
import 'package:darumen/l10n/strings.dart';
import 'package:darumen/widgets/doctor/worklist_logic.dart';
import 'package:darumen/widgets/status_chip.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/harness.dart';

/// Правила рабочего списка как в вебе (WorklistView.vue): главный чип строки, счётчики фильтра, фильтр по флагу,
/// поиск по номеру и сортировка колонками. Сервер считает флаги, приоритет и шаг — клиент только показывает.
WorklistItem row(
  String ref, {
  List<String> flags = const [],
  int priority = 5,
  int days = 30,
  String stageCode = 'waiting',
  String stage = 'ожидает',
  String moName = 'ТОО "Б"',
  String profileCode = '171',
}) =>
    WorklistItem(
      patientRef: ref,
      stage: stage,
      stageCode: stageCode,
      expectedDate: null,
      riskFlags: flags,
      priority: priority,
      nextAction: 'ждать вызова',
      explanation: '',
      moCode: '224E',
      moName: moName,
      profileCode: profileCode,
      regionKato: '75',
      daysWaiting: days,
    );

final ru = S.of('ru');

void main() {
  group('главный чип строки', () {
    test('первый флаг в порядке веба: дата прошла → запрос → перевод → к нам → риск → быстрее → > 30 → остаться', () {
      expect(worklistChip(ru, row('a', flags: ['stuck_over_30', 'refusal_risk', 'date_overdue'])), (label: 'дата прошла', tone: StatusTone.danger));
      expect(worklistChip(ru, row('b', flags: ['transferred_in', 'patient_signal'])), (label: 'запрос пациента', tone: StatusTone.warn));
      expect(worklistChip(ru, row('c', flags: ['refusal_risk', 'transfer_pending'])), (label: 'идёт перевод', tone: StatusTone.accent));
      expect(worklistChip(ru, row('d', flags: ['refusal_risk', 'transferred_in'])), (label: 'переведён к нам', tone: StatusTone.accent));
      expect(worklistChip(ru, row('e', flags: ['faster_alternative', 'refusal_risk'])), (label: 'риск отказа', tone: StatusTone.danger));
      expect(worklistChip(ru, row('f', flags: ['stuck_over_30', 'faster_alternative'])), (label: 'есть быстрее', tone: StatusTone.accent));
      expect(worklistChip(ru, row('g', flags: ['prefers_current', 'stuck_over_30'])), (label: '> 30 дней', tone: StatusTone.neutral));
      expect(worklistChip(ru, row('h', flags: ['prefers_current'])), (label: 'хочет остаться', tone: StatusTone.neutral));
    });

    test('без известных флагов — этап строки с тоном веба; незнакомый этап — подпись API, нейтрально', () {
      expect(worklistChip(ru, row('a', stageCode: 'registered')), (label: 'зарегистрирован', tone: StatusTone.ok));
      expect(worklistChip(ru, row('b', stageCode: 'waiting')), (label: 'ожидает', tone: StatusTone.accent));
      expect(worklistChip(ru, row('c', stageCode: 'called')), (label: 'вызов на госпитализацию', tone: StatusTone.ok));
      expect(worklistChip(ru, row('d', stageCode: 'paused', stage: 'на паузе', flags: ['new_flag'])), (label: 'на паузе', tone: StatusTone.neutral));
    });

    test('тоны флагов для чипов маршрута — те же, что в строке; незнакомый флаг — нейтральный', () {
      expect(worklistFlagTone('refusal_risk'), StatusTone.danger);
      expect(worklistFlagTone('patient_signal'), StatusTone.warn);
      expect(worklistFlagTone('faster_alternative'), StatusTone.accent);
      expect(worklistFlagTone('stuck_over_30'), StatusTone.neutral);
      expect(worklistFlagTone('unknown'), StatusTone.neutral);
    });
  });

  group('счётчики и фильтр', () {
    final items = [
      row('SYN-75-224E-171-01', flags: ['stuck_over_30', 'refusal_risk']),
      row('SYN-75-224E-171-02', flags: ['refusal_risk']),
      row('SYN-75-028B-381-03', flags: ['patient_signal']),
      row('SYN-75-028B-381-04'),
    ];

    test('счётчики — все строки и каждый из восьми флагов, нулевые тоже', () {
      final counts = worklistCounts(items);
      expect(counts[worklistFilterAll], 4);
      expect(counts['refusal_risk'], 2);
      expect(counts['stuck_over_30'], 1);
      expect(counts['patient_signal'], 1);
      expect(counts['date_overdue'], 0);
      expect(counts.keys, [worklistFilterAll, ...RouteCodes.riskFlags]);
    });

    test('фильтр по флагу и поиск по части номера без учёта регистра и пробелов по краям', () {
      expect(visibleWorklist(items, filter: 'refusal_risk').map((i) => i.patientRef), ['SYN-75-224E-171-01', 'SYN-75-224E-171-02']);
      expect(visibleWorklist(items, query: '  028b ').map((i) => i.patientRef), ['SYN-75-028B-381-03', 'SYN-75-028B-381-04']);
      expect(visibleWorklist(items, filter: 'patient_signal', query: '224e'), isEmpty);
      expect(visibleWorklist(items), hasLength(4));
    });

    test('пустой список и список только для чтения не ломают ни счётчики, ни фильтр', () {
      expect(worklistCounts(const [])[worklistFilterAll], 0);
      expect(visibleWorklist(const []), isEmpty);
      final frozen = List<WorklistItem>.unmodifiable(items.reversed);
      expect(visibleWorklist(frozen).first.patientRef, 'SYN-75-028B-381-04', reason: 'равные приоритеты — серверный порядок');
      expect(frozen.first.patientRef, 'SYN-75-028B-381-04', reason: 'вход не меняется');
    });
  });

  group('сортировка', () {
    test('по умолчанию — приоритет по убыванию, равные остаются в порядке сервера', () {
      final items = [row('a', priority: 5), row('b', priority: 9), row('c', priority: 5), row('d', priority: 9)];
      expect(visibleWorklist(items).map((i) => i.patientRef), ['b', 'd', 'a', 'c']);
      expect(WorklistSort.initial, const WorklistSort(WorklistSortKey.priority, descending: true));
    });

    test('повторный выбор колонки меняет направление; новая числовая — по убыванию, текстовая — по возрастанию', () {
      final days = WorklistSort.initial.tap(WorklistSortKey.days);
      expect(days, const WorklistSort(WorklistSortKey.days, descending: true));
      expect(days.tap(WorklistSortKey.days), const WorklistSort(WorklistSortKey.days, descending: false));
      expect(days.tap(WorklistSortKey.patient), const WorklistSort(WorklistSortKey.patient, descending: false));
      expect(WorklistSort.initial.tap(WorklistSortKey.priority).descending, isFalse);
    });

    test('ключи веба: номер, профиль по названию, больница по короткому имени, дни', () {
      final items = [
        row('SYN-2', days: 10, moName: 'ТОО "Ясень"', profileCode: '2'),
        row('SYN-1', days: 40, moName: 'АО "Берёза"', profileCode: '1'),
        row('SYN-3', days: 25, moName: 'Акация', profileCode: '3'),
      ];
      List<String> order(WorklistSort sort) =>
          visibleWorklist(items, sort: sort, profileName: (code) => {'1': 'Хирургия', '2': 'Офтальмология', '3': 'Кардиология'}[code] ?? code).map((i) => i.patientRef).toList();
      expect(order(const WorklistSort(WorklistSortKey.patient, descending: false)), ['SYN-1', 'SYN-2', 'SYN-3']);
      expect(order(const WorklistSort(WorklistSortKey.days, descending: true)), ['SYN-1', 'SYN-3', 'SYN-2']);
      expect(order(const WorklistSort(WorklistSortKey.organization, descending: false)), ['SYN-3', 'SYN-1', 'SYN-2']);
      expect(order(const WorklistSort(WorklistSortKey.profile, descending: false)), ['SYN-3', 'SYN-2', 'SYN-1']);
      expect(order(const WorklistSort(WorklistSortKey.profile, descending: true)), ['SYN-1', 'SYN-2', 'SYN-3']);
    });

    test('настоящий ответ API: 4 строки, фильтр «идёт перевод» и счётчик совпадают', () {
      final page = WorklistResponse.fromJson(fixtureMap('worklist'));
      final counts = worklistCounts(page.items);
      expect(counts[worklistFilterAll], page.items.length);
      expect(visibleWorklist(page.items, filter: 'transfer_pending'), hasLength(counts['transfer_pending']!));
      expect(visibleWorklist(page.items).first.priority, page.items.map((i) => i.priority).reduce((a, b) => a > b ? a : b));
    });
  });
}

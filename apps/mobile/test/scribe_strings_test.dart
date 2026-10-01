import 'dart:io';

import 'package:darumen/l10n/strings.dart';
import 'package:flutter_test/flutter_test.dart';

/// Словарь врача D3 (strings_scribe.dart): скрайб, ассистент направления, журнал решений. Каждая строка, у которой
/// есть веб-ключ, сверяется с самим веб-словарём (apps/web/src/i18n/{ru,kk}.ts) — она должна встречаться в нём
/// дословно в одинарных кавычках. Свои формулировки (Q-11, лист подтверждения отмены) проверяются отдельно: их в
/// вебе нет, и в них нет слова «черновик».
final ru = S.of('ru');
final kk = S.of('kk');
final webRu = File('../web/src/i18n/ru.ts').readAsStringSync();
final webKk = File('../web/src/i18n/kk.ts').readAsStringSync();

void expectWeb(String Function(S s) text) {
  expect(webRu, contains("'${text(ru)}'"), reason: '«${text(ru)}» должна быть дословно в ru.ts');
  expect(webKk, contains("'${text(kk)}'"), reason: '«${text(kk)}» должна быть дословно в kk.ts');
}

const scribeStates = ['approved', 'recording', 'processing', 'transcribed', 'ready'];
const consentStates = ['none', 'pending', 'granted', 'declined', 'withdrawn', 'cancelled', 'expired', 'recording', 'discarded', 'completed'];

void main() {
  group('скрайб', () {
    test('шапка, шаги, состояние записи и согласия — дословно из doctor.scribe.*', () {
      for (final f in <String Function(S)>[
        (s) => s.aiScribeTitle,
        (s) => s.aiScribePatient('{ref}'),
        (s) => s.aiScribeAudioOnApprove,
        (s) => s.aiScribeLangRu,
        (s) => s.aiScribeLangKk,
        (s) => s.aiScribeStepPatient,
        (s) => s.aiScribeStepConsent,
        (s) => s.aiScribeStepRecord,
        (s) => s.aiScribeAskConsent,
        (s) => s.aiScribeAskAgain,
        (s) => s.aiScribeCancelRequest,
        (s) => s.aiScribeConsentSent,
        (s) => s.aiScribeWhat1,
        (s) => s.aiScribeWhat3,
        (s) => s.aiScribeServiceDown,
        (s) => s.aiScribeNeedConsent,
        (s) => s.aiScribeStart,
        (s) => s.aiScribeSessionLost,
        (s) => s.aiScribeResume,
        (s) => s.aiScribeDiscard,
        (s) => s.aiScribeDiscardHint,
      ]) {
        expectWeb(f);
      }
      for (final key in scribeStates) {
        expectWeb((s) => s.aiScribeState(key));
      }
      for (final status in consentStates) {
        expectWeb((s) => s.aiScribeConsentStatus(status));
        expectWeb((s) => s.aiScribeConsentHint(status));
      }
    });

    test('запись, стенограмма, памятка и итог — дословно из doctor.scribe.* и shell.*', () {
      for (final f in <String Function(S)>[
        (s) => s.aiScribeRecordMic,
        (s) => s.aiScribePasteText,
        (s) => s.aiScribeOrType,
        (s) => s.aiScribeUseText,
        (s) => s.aiScribePasteSample,
        (s) => s.aiScribeSampleTranscript,
        (s) => s.aiScribeModelDownloading(-1, -2, -3).replaceAll('-1', '{pct}').replaceAll('-2', '{done}').replaceAll('-3', '{total}'),
        (s) => s.aiScribeModelLoading,
        (s) => s.aiScribeModelError,
        (s) => s.aiScribeModelFake,
        (s) => s.aiScribeTranscribing,
        (s) => s.aiScribeNoTranscript,
        (s) => s.aiScribeEditHint,
        (s) => s.aiScribeFixedBy('ai'),
        (s) => s.aiScribeFixedBy('dictionary'),
        (s) => s.aiScribeFixedBy('doctor'),
        (s) => s.aiScribeWasText,
        (s) => s.aiScribeRevert,
        (s) => s.aiScribeSave,
        (s) => s.aiScribeCorrectTerms,
        (s) => s.aiScribeCorrected(-1).replaceAll('-1', '{n}'),
        (s) => s.aiScribeNothingToCorrect,
        (s) => s.aiScribeAiUnavailable,
        (s) => s.aiScribeRecordTitle,
        (s) => s.aiScribeNoRecord,
        (s) => s.aiScribeRecordHint,
        (s) => s.aiScribeTranscriptChanged,
        (s) => s.aiScribeReplaceRecord,
        (s) => s.aiScribeLeafletHint,
        (s) => s.aiScribeRebuildLeaflet,
        (s) => s.aiScribeLeafletIntro,
        (s) => s.aiScribeLeafletNoPrescriptions,
        (s) => s.aiScribeLeafletSafety,
        (s) => s.aiScribeApprove,
        (s) => s.aiScribeApproveHint,
        (s) => s.aiScribeApprovedToast,
        (s) => s.aiScribeLeafletSent,
        (s) => s.aiScribeAudioDeleted,
        (s) => s.aiScribeCopyLink,
        (s) => s.aiScribeLinkCopied,
        (s) => s.aiScribeQrHint,
        (s) => s.aiScribeQrAlt,
        (s) => s.aiScribeNewVisit,
        (s) => s.aiScribeOpenPatient,
      ]) {
        expectWeb(f);
      }
    });

    test('свои формулировки Q-11 описывают реальный порядок: без «черновика» и «Утвердить все»', () {
      for (final s in [ru, kk]) {
        for (final text in [s.aiScribeWhat2, s.aiScribeResumeHint, s.aiScribeDiscardDone, s.aiScribeApprove, s.aiScribeDiscardQuestion, s.aiScribeDiscardKeep]) {
          expect(text.toLowerCase(), isNot(contains('черновик')));
          expect(text.toLowerCase(), isNot(contains('жоба')));
          expect(text, isNot(contains('Утвердить все')));
        }
      }
      expect(webRu, isNot(contains("'${ru.aiScribeWhat2}'")));
      expect(ru.aiScribeWhat2, contains('Фразы стенограммы'));
      expect(ru.aiScribeDiscardDone, 'Запись отменена, аудио и текст удалены');
      expect(kk.aiScribeResumeHint, contains('Стенограмма сақталған'));
    });

    test('незнакомые коды не ломают словарь: код как есть или пустая подсказка', () {
      expect(ru.aiScribeState('draft'), 'draft');
      expect(ru.aiScribeConsentStatus('unknown'), 'unknown');
      expect(ru.aiScribeConsentHint('unknown'), '');
      expect(kk.aiScribeFixedBy(null), '');
      expect(kk.aiScribeFixedBy('robot'), '');
    });
  });

  group('ассистент направления', () {
    test('все подписи — дословно из doctor.referral.*, route.doctorView.* и shell.asOf', () {
      for (final f in <String Function(S)>[
        (s) => s.assistTitle,
        (s) => s.assistLead,
        (s) => s.assistAsOf('{date}'),
        (s) => s.assistParams,
        (s) => s.assistRegion,
        (s) => s.assistPurpose,
        (s) => s.assistTerritory,
        (s) => s.assistIcd,
        (s) => s.assistMore,
        (s) => s.assistRegistrationDate,
        (s) => s.assistRegistrationDateHint,
        (s) => s.assistReferringOrg,
        (s) => s.assistNotSpecified,
        (s) => s.assistIncludeNeighbors,
        (s) => s.assistWhere,
        (s) => s.assistPickOrg,
        (s) => s.assistChangeOrg,
        (s) => s.assistChosenByDoctor,
        (s) => s.assistInQueue(-1).replaceAll('-1', '{n}'),
        (s) => s.assistFasterBy(-1).replaceAll('-1', '{n}'),
        (s) => s.assistSlowerBy(-1).replaceAll('-1', '{n}'),
        (s) => s.assistRefusal('{pct}'),
        (s) => s.assistHalfShort,
        (s) => s.assistFillForm,
        (s) => s.assistForecastFor('{name}'),
        (s) => s.assistHalf,
        (s) => s.assistNinety,
        (s) => s.assistWithin30,
        (s) => s.assistRefusalRow,
        (s) => s.assistQueueInfo(-1, '{age}', '{throughput}').replaceAll('-1', '{len}'),
        (s) => s.assistUnseenOrgHint,
        (s) => s.assistReferringUnset,
        (s) => s.assistReferringUnsetHint,
        (s) => s.assistDecision,
        (s) => s.assistSumWhere,
        (s) => s.assistSumInsteadOf('{name}'),
        (s) => s.assistSumWhat,
        (s) => s.assistReason,
        (s) => s.assistReasonExample,
        (s) => s.assistSaveNote,
        (s) => s.assistSaveChoice,
        (s) => s.assistRecorded,
        (s) => s.assistDecisionRecorded,
        (s) => s.assistToJournal,
        (s) => s.assistToWorklist,
      ]) {
        expectWeb(f);
      }
    });
  });

  group('журнал решений', () {
    test('подзаголовок, предметы, итоги и пустое состояние — дословно из doctor.decisions.* и decision.*', () {
      for (final f in <String Function(S)>[
        (s) => s.decisionsLead,
        (s) => s.decisionsAll,
        (s) => s.decisionsAnomaly('{id}'),
        (s) => s.decisionsOutcomeLabel,
        (s) => s.decisionsEmpty,
        (s) => s.decisionsEmptyText,
      ]) {
        expectWeb(f);
      }
      for (final subject in ['referral', 'anomaly', 'route', 'scribe']) {
        expectWeb((s) => s.decisionsSubject(subject));
      }
      for (final outcome in ['matched', 'differ', 'none']) {
        expectWeb((s) => s.decisionsOutcome(outcome));
      }
      expect(ru.decisionsSubject('other'), 'other');
      expect(kk.decisionsOutcome('weird'), 'weird');
    });
  });
}

import 'package:darumen/api/models.dart';
import 'package:darumen/config/env.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ScribeSession (§5.10, POST /scribe/sessions response)', () {
    test('parses sessionId, consentId and patientRef', () {
      final s = ScribeSession.fromJson({'sessionId': '9f2c', 'consentId': 'c-1', 'patientRef': 'SYN-75-028B-381-01'});
      expect(s.sessionId, '9f2c');
      expect(s.consentId, 'c-1');
      expect(s.patientRef, 'SYN-75-028B-381-01');
    });
  });

  group('TranscriptSegment original/source (§3.10.5)', () {
    test('an untouched segment has no original and no source', () {
      final seg = TranscriptSegment.fromJson({'t0': 0.0, 't1': 4.0, 'text': 'жалобы на боль'});
      expect(seg.original, isNull);
      expect(seg.source, isNull);
    });

    test('a doctor-edited segment carries original and source: doctor', () {
      final seg = TranscriptSegment.fromJson({'t0': 0.0, 't1': 4.0, 'text': 'исправлено', 'original': 'исходно', 'source': 'doctor'});
      expect(seg.original, 'исходно');
      expect(seg.source, 'doctor');
    });

    test('source can be ai or dictionary', () {
      expect(TranscriptSegment.fromJson({'t0': 0.0, 't1': 1.0, 'text': 'x', 'source': 'ai'}).source, 'ai');
      expect(TranscriptSegment.fromJson({'t0': 0.0, 't1': 1.0, 'text': 'x', 'source': 'dictionary'}).source, 'dictionary');
    });
  });

  group('ApproveResult (§2.2): the server no longer sends leafletUrl', () {
    test('parses the real new shape: leafletToken, audioDeleted, consentId', () {
      final r = ApproveResult.fromJson({'leafletToken': 'tok-1', 'audioDeleted': true, 'consentId': 'c-1'});
      expect(r.leafletToken, 'tok-1');
      expect(r.audioDeleted, isTrue);
      expect(r.consentId, 'c-1');
    });

    test('audioDeleted defaults to true and consentId is nullable when absent', () {
      final r = ApproveResult.fromJson({'leafletToken': 'tok-2'});
      expect(r.audioDeleted, isTrue);
      expect(r.consentId, isNull);
    });

    test('leafletUrl (MOBILE-REFACTOR-SHIM) is the public web page built from the token, not a server field', () {
      // старый сервер присылал относительный /scribe/leaflets/{token} — для QR он не годился и больше не читается
      final r = ApproveResult.fromJson({'leafletToken': 'tok-3', 'leafletUrl': '/scribe/leaflets/tok-3'});
      expect(r.leafletToken, 'tok-3');
      expect(r.leafletUrl, '${Env.webBase}/leaflet/tok-3');
    });
  });

  group('tolerant parsing of the scribe shapes', () {
    test('a segment without timings or text parses to zeros and an empty string', () {
      final seg = TranscriptSegment.fromJson(const {});
      expect(seg.t0, 0);
      expect(seg.t1, 0);
      expect(seg.text, '');
    });

    test('integer timings from the recognizer are read as doubles', () {
      final seg = TranscriptSegment.fromJson({'t0': 1, 't1': 5, 'text': 'x'});
      expect(seg.t0, 1.0);
      expect(seg.t1, 5.0);
    });

    test('a draft section without spans has an empty span list; a draft without model has model null', () {
      final draft = ScribeDraft.fromJson({
        'sections': [
          {'name': 'Запись приёма', 'text': 'текст'},
        ],
        'leaflet': '',
      });
      expect(draft.sections.single.spans, isEmpty);
      expect(draft.model, isNull);
    });

    test('a consent with missing optional fields keeps nulls and empty strings, never throws', () {
      final c = ScribeConsent.fromJson({'requestId': 'r-3', 'patientRef': 'SYN-75-028B-381-01', 'status': 'expired'});
      expect(c.status, RouteCodes.scribeExpired);
      expect(c.requestedRole, '');
      expect(c.day, '');
      expect(c.answeredAt, isNull);
      expect(c.approvedAt, isNull);
    });

    test('a resumed session without language defaults to ru', () {
      expect(ScribeSessionState.fromJson({'sessionId': 's'}).language, 'ru');
      expect(ScribeSessionState.fromJson({'sessionId': 's'}).approved, isFalse);
    });

    test('health with transcriberProgress null or totalMb null leaves the missing sizes null', () {
      final h = ScribeHealth.fromJson({'status': 'ok', 'transcriber': 'w', 'drafter': 'q', 'transcriberProgress': {'downloadedMb': 40, 'totalMb': null}});
      expect(h.downloadedMb, 40);
      expect(h.totalMb, isNull);
      expect(ScribeHealth.fromJson({'transcriberProgress': null}).downloadedMb, isNull);
    });

    test('parsed lists are unmodifiable — models are immutable', () {
      final state = ScribeSessionState.fromJson({
        'sessionId': 's',
        'transcript': [
          {'t0': 0.0, 't1': 1.0, 'text': 'x'},
        ],
      });
      expect(() => state.transcript.add(const TranscriptSegment(t0: 0, t1: 1, text: 'y')), throwsUnsupportedError);
    });
  });

  group('ScribeConsent (§3.10.1, GET /scribe-consents)', () {
    test('parses a pending consent request', () {
      final c = ScribeConsent.fromJson({
        'requestId': 'r-1',
        'patientRef': 'SYN-75-028B-381-01',
        'moCode': '028B',
        'moName': 'Институт',
        'requestedRole': 'doctor',
        'requestedAt': '2026-10-01T09:00:00+00:00',
        'day': '2026-10-01',
        'comment': null,
        'status': 'pending',
        'answeredAt': null,
        'sessionId': null,
        'leafletToken': null,
        'approvedAt': null,
      });
      expect(c.requestId, 'r-1');
      expect(c.status, RouteCodes.scribePending);
      expect(c.sessionId, isNull);
      expect(c.leafletToken, isNull);
    });

    test('parses a completed consent with a leaflet token', () {
      final c = ScribeConsent.fromJson({
        'requestId': 'r-2',
        'patientRef': 'SYN-75-028B-381-01',
        'requestedRole': 'doctor',
        'requestedAt': '2026-10-01T09:00:00+00:00',
        'day': '2026-10-01',
        'status': 'completed',
        'leafletToken': 'tok-9',
        'approvedAt': '2026-10-01T09:40:00+00:00',
      });
      expect(c.status, RouteCodes.scribeCompleted);
      expect(c.leafletToken, 'tok-9');
      expect(c.moCode, isNull, reason: 'moCode/moName необязательны — терпимый разбор');
    });
  });

  group('ScribeSessionState (§3.10.4, GET /scribe/sessions/{id})', () {
    test('parses a resumed session with a transcript and no draft yet', () {
      final state = ScribeSessionState.fromJson({
        'sessionId': '9f2c',
        'language': 'ru',
        'approved': false,
        'transcript': [
          {'t0': 0.0, 't1': 4.0, 'text': 'жалобы на боль'},
        ],
        'draft': null,
      });
      expect(state.approved, isFalse);
      expect(state.transcript, hasLength(1));
      expect(state.draft, isNull);
    });

    test('parses a draft with sections including model', () {
      final state = ScribeSessionState.fromJson({
        'sessionId': '9f2c',
        'language': 'kk',
        'approved': false,
        'transcript': [],
        'draft': {
          'sections': [
            {
              'name': 'Жалобы',
              'text': 'боль в груди',
              'spans': [
                {'t0': 0.0, 't1': 4.0},
              ],
            },
          ],
          'leaflet': 'памятка пациенту',
          'model': 'qwen-2.5',
        },
      });
      expect(state.draft!.model, 'qwen-2.5');
      expect(state.draft!.sections.single.spans.single.t0, 0.0);
    });

    test('transcript defaults to an empty list when absent', () {
      final state = ScribeSessionState.fromJson({'sessionId': '9f2c', 'language': 'ru', 'approved': true});
      expect(state.transcript, isEmpty);
    });
  });

  group('ScribeCorrection (§3.10.5, POST …/correct)', () {
    test('parses a successful AI correction', () {
      final c = ScribeCorrection.fromJson({
        'transcript': [
          {'t0': 0.0, 't1': 4.0, 'text': 'исправлено', 'source': 'ai'},
        ],
        'changed': 1,
        'aiError': null,
      });
      expect(c.changed, 1);
      expect(c.aiError, isNull);
      expect(c.transcript.single.source, 'ai');
    });

    test('a 200 with aiError means dictionary-only correction, not a failure', () {
      final c = ScribeCorrection.fromJson({'transcript': [], 'changed': 0, 'aiError': 'Языковая модель сейчас недоступна'});
      expect(c.aiError, 'Языковая модель сейчас недоступна');
      expect(c.changed, 0);
    });
  });

  group('ScribeHealth (§3.10.5, GET /scribe/health)', () {
    test('parses a loading transcriber with download progress', () {
      final h = ScribeHealth.fromJson({
        'status': 'degraded',
        'transcriber': 'whisper',
        'drafter': 'qwen',
        'transcriberState': 'loading',
        'transcriberError': null,
        'transcriberProgress': {'downloadedMb': 120, 'totalMb': 500},
      });
      expect(h.transcriberState, 'loading');
      expect(h.downloadedMb, 120);
      expect(h.totalMb, 500);
    });

    test('transcriberProgress absent leaves downloadedMb/totalMb null', () {
      final h = ScribeHealth.fromJson({'status': 'ok', 'transcriber': 'whisper', 'drafter': 'qwen', 'transcriberState': 'ready'});
      expect(h.downloadedMb, isNull);
      expect(h.totalMb, isNull);
    });
  });

  group('ScribeAudioUpload (§5.13, new uploadScribeAudio response)', () {
    test('parses transcript segments together with the raw joined text', () {
      final upload = ScribeAudioUpload.fromJson({
        'transcript': [
          {'t0': 0.0, 't1': 4.0, 'text': 'жалобы на боль'},
        ],
        'text': 'жалобы на боль',
        'transcriber': 'whisper',
      });
      expect(upload.transcript.single.text, 'жалобы на боль');
      expect(upload.text, 'жалобы на боль');
      expect(upload.transcriber, 'whisper');
    });

    test('defaults to an empty transcript and empty text when absent', () {
      final upload = ScribeAudioUpload.fromJson(const {});
      expect(upload.transcript, isEmpty);
      expect(upload.text, '');
      expect(upload.transcriber, isNull);
    });
  });
}

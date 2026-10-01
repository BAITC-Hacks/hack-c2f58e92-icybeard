import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';

import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/api_error.dart';
import '../widgets/app_card.dart';
import '../widgets/scribe/scribe_flow.dart';
import '../widgets/scribe/scribe_phrases.dart';
import '../widgets/scribe/scribe_result_card.dart';
import '../widgets/scribe/scribe_sheets.dart';
import '../widgets/scribe/scribe_steps.dart';
import '../widgets/scribe/scribe_text.dart';
import '../widgets/scribe/scribe_texts_card.dart';
import '../widgets/scribe_record_card.dart';
import '../widgets/section.dart';
import '../widgets/state_view.dart';
import '../widgets/status_chip.dart';

/// AI-скрайб приёма — всегда для одного пациента (`/doctor/patients/:ref/scribe`, решение API 6). Одна колонка (веб
/// ScribeView, отчёт врача §6.3):
/// - до записи — язык приёма и три шага: пациент, согласие пациента (запрос, отмена, «Запросить снова»; пока ждём
///   ответа и экран виден, согласие перечитывается каждые 5 с), запись («Начать» по согласию, «Продолжить» и
///   «Отменить запись» для начатой);
/// - во время записи — карточка записи (микрофон или вставка текста, заметка о модели, отмена с подтверждением),
///   фразы стенограммы с правкой в листе и «Исправить термины (ИИ)», запись приёма и памятка; «Утвердить и выдать
///   памятку» — в нижней зоне;
/// - после утверждения — ссылка на памятку, QR и «Новый приём».
/// Сервис скрайба проверяется при открытии и каждые 12 с, пока модель распознавания грузится; 429 — «повторите позже».
/// Ошибки — одним вызовом `showApiError`; согласие и сессию перечитывает ScribeFlow. Словаря терминов и загрузки
/// аудиофайла на телефоне нет (только веб, §6.4).
class ScribeScreen extends StatefulWidget {
  const ScribeScreen({super.key, required String? patientRef}) : patientRef = patientRef ?? '';

  final String patientRef;

  @override
  State<ScribeScreen> createState() => _ScribeScreenState();
}

class _ScribeScreenState extends State<ScribeScreen> with WidgetsBindingObserver {
  static const _bars = 24;
  static const _consentPoll = Duration(seconds: 5);
  static const _healthPoll = Duration(seconds: 12);

  late final ScribeFlow _flow;
  final AudioRecorder _recorder = AudioRecorder();
  Timer? _consentTimer;
  Timer? _healthTimer;
  Timer? _clock;
  StreamSubscription<Amplitude>? _amplitude;
  bool _foreground = true;

  /// Страница видна внутри своей вкладки (у скрытой вкладки shell'а тикеры выключены) и она верхняя в навигаторе.
  bool _ticking = true;
  ModalRoute<Object?>? _route;
  bool _recording = false;
  int _seconds = 0;
  List<double> _levels = List.filled(_bars, 0);

  /// Подсказка под карточкой записи: нет доступа к микрофону или речь не распознана.
  String? _notice;

  @override
  void initState() {
    super.initState();
    final session = context.read<Session>();
    _flow = ScribeFlow(api: session.api, patientRef: widget.patientRef, language: session.locale)..addListener(_onFlow);
    WidgetsBinding.instance.addObserver(this);
    _consentTimer = Timer.periodic(_consentPoll, (_) => _poll(_flow.waitsForPatient, _flow.loadConsents));
    _healthTimer = Timer.periodic(_healthPoll, (_) => _poll(_flow.pollHealth, _flow.loadHealth));
    unawaited(_flow.loadConsents());
    unawaited(_flow.loadHealth());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _consentTimer?.cancel();
    _healthTimer?.cancel();
    _clock?.cancel();
    unawaited(_amplitude?.cancel());
    unawaited(_recorder.dispose());
    _flow
      ..removeListener(_onFlow)
      ..dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _route = ModalRoute.of(context);
    final ticking = TickerMode.valuesOf(context).enabled;
    final shown = ticking && !_ticking;
    _ticking = ticking;
    // вернулись на вкладку со скрайбом — согласие перечитывается сразу, не дожидаясь следующего тика
    if (shown && _flow.waitsForPatient) unawaited(_flow.loadConsents());
  }

  void _onFlow() {
    if (mounted) setState(() {});
  }

  /// Опрос идёт, только пока экран виден: приложение на переднем плане, вкладка показана и этот экран — верхний.
  bool get _visible => mounted && _foreground && _ticking && (_route?.isCurrent ?? true);

  void _poll(bool needed, Future<void> Function() load) {
    if (needed && _visible) unawaited(load());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final back = !_foreground && state == AppLifecycleState.resumed;
    if (state == AppLifecycleState.resumed) {
      _foreground = true;
    } else if (state != AppLifecycleState.inactive) {
      _foreground = false;
    }
    if (back && _flow.waitsForPatient) unawaited(_flow.loadConsents());
  }

  // ---------- действия ----------

  void _snack(String text) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(text)));

  /// Действие flow; ошибка — одним вызовом showApiError (согласие flow уже перечитал).
  Future<void> _act(Future<void> Function() action, {String? done}) async {
    try {
      await action();
      if (done != null && mounted) _snack(done);
    } on Object catch (e) {
      if (mounted) await showApiError(context, e);
    }
  }

  Future<void> _ask() async {
    final s = S.at(context);
    try {
      if (await _flow.askConsent() && mounted) _snack(s.aiScribeConsentSent);
    } on Object catch (e) {
      if (mounted) await showApiError(context, e);
    }
  }

  Future<void> _discard() async {
    final s = S.at(context);
    if (!await confirmScribeDiscard(context) || !mounted) return;
    await _act(_flow.discard, done: s.aiScribeDiscardDone);
  }

  Future<void> _record() async {
    final s = S.at(context);
    if (_recording || _flow.sessionBusy) return;
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) setState(() => _notice = s.scribeMicDenied);
        return;
      }
      final dir = await getTemporaryDirectory();
      await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '${dir.path}/consult.m4a');
    } on Exception {
      // плагин записи недоступен или микрофон занят — говорим прямо и оставляем вставку текста
      if (mounted) setState(() => _notice = s.scribeMicDenied);
      return;
    }
    if (!mounted) return;
    setState(() {
      _notice = null;
      _recording = true;
      _seconds = 0;
      _levels = List.filled(_bars, 0);
    });
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    try {
      _amplitude = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amp) {
        // dBFS от −160 до 0: всё тише −60 считаем тишиной
        final level = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        if (mounted) setState(() => _levels = [..._levels.skip(1), level]);
      });
    } on Exception {
      // платформа без уровня сигнала — волна остаётся плоской, запись идёт
    }
  }

  Future<void> _stop() async {
    _clock?.cancel();
    await _amplitude?.cancel();
    _amplitude = null;
    String? path;
    try {
      path = await _recorder.stop();
    } on Exception {
      path = null;
    }
    if (!mounted) return;
    setState(() => _recording = false);
    if (path == null) return;
    final file = File(path);
    try {
      final upload = await _flow.uploadAudio(await file.readAsBytes(), 'consult.m4a');
      // тишина или шум дают пустую стенограмму — говорим об этом прямо, а не оставляем пустой список
      if (mounted) setState(() => _notice = upload.transcript.isEmpty ? S.at(context).scribeNothingRecognized : null);
    } on Object catch (e) {
      if (mounted) await showApiError(context, e);
    } finally {
      await _deleteQuietly(file);
    }
  }

  /// Временный файл записи удаляется сразу после отправки; на сервере аудио живёт до утверждения или отмены.
  static Future<void> _deleteQuietly(File file) async {
    try {
      await file.delete();
    } on FileSystemException {
      // файла уже нет — удалять нечего; временную папку система чистит сама
    }
  }

  Future<void> _paste() async {
    final text = await showScribePasteSheet(context);
    if (text != null && mounted) await _act(() => _flow.useText(text));
  }

  Future<void> _edit(int index) async {
    final segment = _flow.segments[index];
    final stamp = '${scribeStamp(segment.t0, segment.t1)} · ${scribeSegmentLanguage(segment.text).toUpperCase()}';
    final text = await showScribePhraseSheet(context, stamp: stamp, text: segment.text);
    if (text != null && text != segment.text && mounted && !_flow.sessionBusy) await _act(() => _flow.saveSegment(index, text));
  }

  Future<void> _revert(int index) async {
    final original = _flow.segments[index].original;
    if (original != null && !_flow.sessionBusy) await _act(() => _flow.saveSegment(index, original));
  }

  Future<void> _correct() async {
    final s = S.at(context);
    if (_flow.sessionBusy) return;
    try {
      final result = await _flow.correctTerms();
      final summary = result.changed > 0 ? s.aiScribeCorrected(result.changed) : s.aiScribeNothingToCorrect;
      // языковая модель недоступна — исправил только словарь, говорим об этом второй строкой (мягкий сбой)
      if (mounted) _snack(result.aiError == null ? summary : '$summary\n${s.aiScribeAiUnavailable}');
    } on Object catch (e) {
      if (mounted) await showApiError(context, e);
    }
  }

  Future<void> _copy(String link) async {
    final copied = S.at(context).aiScribeLinkCopied;
    await Clipboard.setData(ClipboardData(text: link));
    if (mounted) _snack(copied);
  }

  // ---------- экран ----------

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final flow = _flow;
    final forbidden = !flow.consentsLoaded && isForbidden(flow.consentsError);
    final result = flow.result;
    return PageScaffold(
      title: s.aiScribeTitle,
      onRefresh: flow.hasSession || forbidden ? null : () => Future.wait([flow.loadConsents(), flow.loadHealth()]),
      bottom: forbidden ? null : _bottom(s),
      children: [
        _Header(
          patientRef: widget.patientRef,
          state: scribeStateKey(approved: flow.approved, recording: _recording, busy: flow.processing, hasTranscript: flow.segments.isNotEmpty, hasSession: flow.hasSession),
        ),
        if (forbidden)
          ForbiddenState(error: flow.consentsError)
        else if (result != null)
          ScribeResultCard(
            link: scribeLeafletLink(result.leafletToken),
            onCopy: () => _copy(scribeLeafletLink(result.leafletToken)),
            onOpenPatient: () => context.go('/doctor/patients/${Uri.encodeComponent(widget.patientRef)}'),
          )
        else if (flow.hasSession)
          ..._work(s, flow)
        else ...[
          _LanguagePicker(language: flow.language, onChanged: flow.setLanguage),
          ScribePatientStep(patientRef: widget.patientRef),
          ScribeConsentStep(flow: flow, onAsk: _ask, onCancel: () => _act(flow.cancelConsent)),
          ScribeRecordStep(flow: flow, onStart: () => _act(flow.start), onResume: () => _act(flow.resume), onDiscard: _discard),
        ],
      ],
    );
  }

  List<Widget> _work(S s, ScribeFlow flow) {
    final locked = _recording || flow.sessionBusy;
    return [
      ScribeRecordCard(
        recording: _recording,
        seconds: _seconds,
        levels: _levels,
        language: flow.language == 'kk' ? s.aiScribeLangKk : s.aiScribeLangRu,
        note: scribeModelNote(s, flow.health),
        onRecord: flow.sessionBusy || scribeModelNotReady(flow.health) ? null : _record,
        onStop: _stop,
        onPaste: flow.sessionBusy ? null : _paste,
        onDiscard: flow.sessionBusy || flow.consentBusy ? null : _discard,
      ),
      if (_notice != null) Text(_notice!, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: AppTones.of(context).danger.fg)),
      ScribePhrasesCard(
        segments: flow.segments,
        locked: locked,
        processing: flow.processing,
        correcting: flow.correcting,
        savingIndex: flow.savingIndex,
        onEdit: _edit,
        onRevert: _revert,
        onCorrect: _correct,
      ),
      ScribeTextsCard(flow: flow, locked: locked),
    ];
  }

  Widget? _bottom(S s) {
    if (_flow.approved) {
      return FilledButton.icon(onPressed: _flow.newVisit, icon: const Icon(Icons.add, size: 20), label: Text(s.aiScribeNewVisit));
    }
    if (!_flow.hasSession) return null;
    return FilledButton.icon(
      onPressed: _flow.canApprove && !_recording ? () => _act(() => _flow.approve(s.aiScribeRecordTitle), done: s.aiScribeApprovedToast) : null,
      icon: _flow.approving ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check, size: 20),
      label: Text(s.aiScribeApprove),
    );
  }
}

/// Подзаголовок «Пациент {ref} · аудио удаляется при утверждении» и чип состояния записи справа (с начала записи).
class _Header extends StatelessWidget {
  const _Header({required this.patientRef, required this.state});

  final String patientRef;
  final String? state;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final key = state;
    return Wrap(
      spacing: AppSpacing.sm,
      runSpacing: AppSpacing.xs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Text('${s.aiScribePatient(patientRef)} · ${s.aiScribeAudioOnApprove}', style: Theme.of(context).textTheme.bodySmall?.merge(AppType.numeric)),
        if (key != null)
          StatusChip(
            s.aiScribeState(key),
            tone: switch (key) {
              'approved' => StatusTone.ok,
              'recording' => StatusTone.danger,
              'processing' => StatusTone.warn,
              'transcribed' => StatusTone.accent,
              _ => StatusTone.neutral,
            },
          ),
      ],
    );
  }
}

/// Язык приёма «Русский» / «Қазақша» (решение Q-9) — до начала записи; дальше он показан чипом в карточке записи.
class _LanguagePicker extends StatelessWidget {
  const _LanguagePicker({required this.language, required this.onChanged});

  final String language;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        FieldLabel(s.scribeLanguageLabel),
        SegmentedButton<String>(
          segments: [
            ButtonSegment(value: 'ru', label: Text(s.aiScribeLangRu)),
            ButtonSegment(value: 'kk', label: Text(s.aiScribeLangKk)),
          ],
          selected: {language},
          showSelectedIcon: false,
          onSelectionChanged: (value) => onChanged(value.first),
        ),
      ],
    );
  }
}

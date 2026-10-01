import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';

import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../theme/typography.dart';
import '../widgets/app_card.dart';
import '../widgets/circle_button.dart';
import '../widgets/error_box.dart';
import '../widgets/origin_tag.dart';
import '../widgets/scribe_record_card.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

enum ScribeStep { consent, record, draft, approved }

/// AI-скрайб по доске m-scribe-new: карточка записи (красная точка записи, таймер 40/800, волна, строка согласия), карточка
/// «Черновик» с чипом AI и разделами, primary-кнопка внизу по шагу: согласие → «Начать»; запись → «Остановить» /
/// «Составить черновик» (микрофон или вставка текста); черновик → «Утвердить все»; итог — ссылка, QR, «Исходные
/// данные удалены сервером». Открывается из маршрута пациента (реф в подписи) или без него.
class ScribeScreen extends StatefulWidget {
  const ScribeScreen({super.key, this.patientRef});

  final String? patientRef;

  @override
  State<ScribeScreen> createState() => _ScribeScreenState();
}

class _ScribeScreenState extends State<ScribeScreen> {
  static const _bars = 24;

  ScribeStep step = ScribeStep.consent;
  bool consent = false;

  /// ru | kk | auto; API принимает только ru|kk, «авто» — язык приложения.
  String language = 'auto';
  String? sessionId;
  final transcript = TextEditingController();
  List<DraftSection> sections = [];
  final Map<String, TextEditingController> sectionControllers = {};
  final leaflet = TextEditingController();
  ApproveResult? result;
  Object? error;
  VoidCallback? retry;
  bool busy = false;
  // запись с микрофона: файл во временной папке, после распознавания удаляется; аудио на сервере — до утверждения
  final AudioRecorder _recorder = AudioRecorder();
  bool recording = false;
  bool transcribing = false;
  String? notice;
  int _seconds = 0;
  Timer? _timer;
  StreamSubscription<Amplitude>? _amplitude;
  final _levels = List<double>.filled(_bars, 0);

  @override
  void dispose() {
    _timer?.cancel();
    _amplitude?.cancel();
    _recorder.dispose();
    transcript.dispose();
    leaflet.dispose();
    for (final c in sectionControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  void _resetAll() {
    setState(() {
      step = ScribeStep.consent;
      consent = false;
      sessionId = null;
      transcript.clear();
      sections = [];
      for (final c in sectionControllers.values) {
        c.dispose();
      }
      sectionControllers.clear();
      leaflet.clear();
      result = null;
      error = null;
      retry = null;
      notice = null;
      _seconds = 0;
      _levels.fillRange(0, _bars, 0);
    });
  }

  String get _sessionLanguage => language == 'auto' ? context.read<Session>().locale : language;

  Future<void> _start() async {
    final session = context.read<Session>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      // MOBILE-REFACTOR-SHIM: запись начинается только по согласию пациента (consentId), а у этого экрана его нет —
      // сервер откажет; экран со шагом согласия придёт на смену этому
      final created = await session.api.createScribeSession(consentId: '', language: _sessionLanguage);
      if (!mounted) {
        return;
      }
      setState(() {
        sessionId = created.sessionId;
        step = ScribeStep.record;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          retry = _start;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  /// Запись: разрешение → старт → таймер и волна прямо в карточке; «Остановить» внизу отправляет аудио.
  Future<void> _record() async {
    final s = S.at(context);
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => notice = s.scribeMicDenied);
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '${dir.path}/consult.m4a');
    if (!mounted) {
      return;
    }
    setState(() {
      notice = null;
      recording = true;
      _seconds = 0;
      _levels.fillRange(0, _bars, 0);
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    try {
      _amplitude = _recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amp) {
        // dBFS от −160 до 0: всё тише −60 считаем тишиной
        final level = ((amp.current + 60) / 60).clamp(0.0, 1.0);
        setState(() {
          _levels.removeAt(0);
          _levels.add(level);
        });
      });
    } catch (_) {
      // платформа без амплитуды — волна остаётся плоской
    }
  }

  Future<void> _stopRecording() async {
    _timer?.cancel();
    await _amplitude?.cancel();
    _amplitude = null;
    final path = await _recorder.stop();
    if (!mounted) {
      return;
    }
    setState(() {
      recording = false;
      transcribing = path != null;
    });
    if (path == null || sessionId == null) {
      return;
    }
    try {
      final file = File(path);
      // MOBILE-REFACTOR-SHIM: загрузка аудио теперь возвращает фразы стенограммы; старому экрану нужен только текст
      final text = (await context.read<Session>().api.uploadScribeAudio(sessionId!, await file.readAsBytes(), 'consult.m4a')).text;
      await file.delete();
      if (mounted) {
        // тишина или шум дают пустую стенограмму — говорим об этом прямо, а не оставляем пустое поле без объяснения
        setState(() {
          transcript.text = [transcript.text.trim(), text.trim()].where((t) => t.isNotEmpty).join('\n');
          notice = text.trim().isEmpty ? S.at(context).scribeNothingRecognized : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => error = e);
      }
    } finally {
      if (mounted) {
        setState(() => transcribing = false);
      }
    }
  }

  Future<void> _pasteText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim();
    if (text == null || text.isEmpty || !mounted) {
      return;
    }
    setState(() => transcript.text = [transcript.text.trim(), text].where((t) => t.isNotEmpty).join('\n'));
  }

  Future<void> _makeDraft() async {
    final api = context.read<Session>().api;
    final id = sessionId;
    if (id == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.setTranscript(id, transcript.text);
      final draft = await api.makeDraft(id);
      if (!mounted) {
        return;
      }
      for (final c in sectionControllers.values) {
        c.dispose();
      }
      sectionControllers.clear();
      for (final s in draft.sections) {
        sectionControllers[s.name] = TextEditingController(text: s.text);
      }
      setState(() {
        sections = draft.sections;
        leaflet.text = draft.leaflet;
        step = ScribeStep.draft;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          retry = _makeDraft;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _approve() async {
    final api = context.read<Session>().api;
    final id = sessionId;
    if (id == null) {
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final edited = [for (final s in sections) DraftSection(name: s.name, text: sectionControllers[s.name]?.text ?? s.text)];
      final approved = await api.approveScribe(id, edited, leaflet.text);
      if (!mounted) {
        return;
      }
      setState(() {
        result = approved;
        step = ScribeStep.approved;
      });
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e;
          retry = _approve;
        });
      }
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> _discard() async {
    final api = context.read<Session>().api;
    if (recording) {
      await _stopRecording();
    }
    final id = sessionId;
    if (id != null) {
      try {
        await api.discardScribe(id);
      } catch (e) {
        if (mounted) {
          setState(() => error = e);
        }
        return;
      }
    }
    if (mounted) {
      _resetAll();
    }
  }

  Future<void> _copy(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(S.at(context).copied)));
    }
  }

  Widget _bottom(S s) => switch (step) {
        ScribeStep.consent => FilledButton(onPressed: consent && !busy ? _start : null, child: Text(s.scribeStartButton)),
        ScribeStep.record => recording
            ? FilledButton.icon(onPressed: _stopRecording, icon: const Icon(Icons.stop, size: 20), label: Text(s.scribeStopButton))
            : FilledButton.icon(onPressed: busy || transcribing ? null : _makeDraft, icon: const Icon(Icons.description_outlined, size: 20), label: Text(s.scribeMakeDraftButton)),
        ScribeStep.draft => FilledButton(onPressed: busy ? null : _approve, child: Text(s.scribeApproveButton)),
        ScribeStep.approved => OutlinedButton(onPressed: _resetAll, child: Text(s.scribeNewSessionButton)),
      };

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return PageScaffold(
      title: s.scribeTitle,
      actions: [
        if (step == ScribeStep.record || step == ScribeStep.draft)
          CircleIconButton(icon: Icons.close, label: s.scribeDiscardButton, onTap: busy ? null : _discard),
      ],
      bottom: _bottom(s),
      children: [
        if (widget.patientRef != null) Text(widget.patientRef!, style: theme.textTheme.bodySmall?.merge(AppType.numeric)),
        if (error != null) ErrorBox(error: error, onRetry: busy ? null : retry),
        if (step == ScribeStep.consent) _consentStep(s, theme),
        if (step == ScribeStep.record) ..._recordStep(s, theme),
        if (step == ScribeStep.draft) ..._draftStep(s, theme),
        if (step == ScribeStep.approved && result != null) ..._approvedStep(s, theme),
      ],
    );
  }

  Widget _consentStep(S s, ThemeData theme) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            CardLabel(s.scribeRecordShort, trailing: StatusChip(_sessionLanguage.toUpperCase(), tone: StatusTone.neutral)),
            const SizedBox(height: AppSpacing.md),
            InkWell(
              borderRadius: BorderRadius.circular(AppRadius.sm),
              onTap: () => setState(() => consent = !consent),
              child: Row(
                children: [
                  Checkbox(value: consent, onChanged: (v) => setState(() => consent = v ?? false)),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(child: Text(s.scribeConsentLabel, style: theme.textTheme.rowStrong)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _InfoLine(icon: Icons.mic_none, text: s.scribeWhatHappens1),
            const SizedBox(height: AppSpacing.sm),
            _InfoLine(icon: Icons.description_outlined, text: s.scribeWhatHappens2),
            const SizedBox(height: AppSpacing.lg),
            FieldLabel(s.scribeLanguageLabel),
            SegmentedButton<String>(
              segments: [
                const ButtonSegment(value: 'ru', label: Text('РУС')),
                const ButtonSegment(value: 'kk', label: Text('ҚАЗ')),
                ButtonSegment(value: 'auto', label: Text(s.scribeLanguageAuto)),
              ],
              selected: {language},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => language = v.first),
            ),
          ],
        ),
      );

  List<Widget> _recordStep(S s, ThemeData theme) => [
        ScribeRecordCard(
          recording: recording,
          seconds: _seconds,
          levels: _levels,
          language: _sessionLanguage.toUpperCase(),
          caption: recording ? s.scribeRecordingCaption : s.scribeReadyCaption,
        ),
        if (!recording)
          Row(
            children: [
              Expanded(child: OutlinedButton.icon(onPressed: busy || transcribing ? null : _record, icon: const Icon(Icons.mic, size: 20), label: Text(s.scribeRecordMic))),
              const SizedBox(width: AppSpacing.sm),
              Expanded(child: OutlinedButton.icon(onPressed: busy ? null : _pasteText, icon: const Icon(Icons.content_paste, size: 20), label: Text(s.scribePasteText))),
            ],
          ),
        if (transcribing)
          Row(
            children: [
              const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              const SizedBox(width: AppSpacing.sm),
              Flexible(child: Text(s.scribeTranscribing, style: theme.textTheme.bodySmall)),
            ],
          ),
        if (notice != null) Text(notice!, style: theme.textTheme.bodySmall?.copyWith(color: AppTones.of(context).danger.fg)),
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardLabel(s.scribeTranscriptTitle),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: transcript, minLines: 3, maxLines: 10, decoration: InputDecoration(hintText: s.scribeTranscriptFieldLabel)),
            ],
          ),
        ),
      ];

  List<Widget> _draftStep(S s, ThemeData theme) => [
        Text(s.scribeDraftReviewCaption, style: theme.textTheme.bodySmall),
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CardLabel(s.scribeDraftShort, trailing: const OriginTag(Origin.ai)),
              for (final section in sections) ...[
                const SizedBox(height: AppSpacing.md),
                FieldLabel(s.scribeSectionLabel(section.name)),
                TextField(controller: sectionControllers[section.name], minLines: 2, maxLines: 8),
              ],
              const SizedBox(height: AppSpacing.md),
              FieldLabel(s.scribeLeafletLabel),
              TextField(controller: leaflet, minLines: 3, maxLines: 8),
            ],
          ),
        ),
      ];

  List<Widget> _approvedStep(S s, ThemeData theme) => [
        AppCard(
          padding: AppCard.plain,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(s.scribeApprovedTitle, style: theme.textTheme.titleMedium),
              const SizedBox(height: AppSpacing.md),
              FieldLabel(s.scribeLeafletUrlLabel),
              Row(
                children: [
                  Expanded(child: SelectableText(result!.leafletUrl, style: theme.textTheme.bodySmall)),
                  IconButton(icon: const Icon(Icons.copy_outlined), tooltip: s.copy, onPressed: () => _copy(result!.leafletUrl)),
                ],
              ),
              const SizedBox(height: AppSpacing.md),
              Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  // QR читается только на белом — единственное место с цветом вне палитры темы
                  decoration: BoxDecoration(color: ColorTokens.white, borderRadius: BorderRadius.circular(AppRadius.md)),
                  child: QrImageView(data: result!.leafletUrl, size: 200),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(s.scribeQrHint, style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: AppSpacing.md),
              _InfoLine(icon: Icons.delete_outline, text: s.scribeAudioDeletedNote),
            ],
          ),
        ),
      ];
}

class _InfoLine extends StatelessWidget {
  const _InfoLine({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: AppPalette.of(context).muted),
          const SizedBox(width: AppSpacing.md),
          Expanded(child: Text(text, style: Theme.of(context).textTheme.bodySmall)),
        ],
      );
}

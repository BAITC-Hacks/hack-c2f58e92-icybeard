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
import '../widgets/error_box.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

enum _Step { consent, record, draft, approved }

/// AI-скрайб: тонкая полоса прогресса с четырьмя подписями; согласие (чекбокс, две строки о происходящем, язык);
/// запись нижним листом с волной, таймером и «Стоп», стенограмма под листом и «Вставить текст» как запасной путь;
/// черновик по разделам карточками [AI], «Утвердить все»; итог — ссылка, QR, «Исходные данные удалены сервером».
class ScribeScreen extends StatefulWidget {
  const ScribeScreen({super.key});

  @override
  State<ScribeScreen> createState() => _ScribeScreenState();
}

class _ScribeScreenState extends State<ScribeScreen> {
  _Step step = _Step.consent;
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
  bool transcribing = false;
  String? notice;

  @override
  void dispose() {
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
      step = _Step.consent;
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
      final created = await session.api.createScribeSession(_sessionLanguage);
      if (!mounted) {
        return;
      }
      setState(() {
        sessionId = created.sessionId;
        step = _Step.record;
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

  /// Запись: разрешение → старт → нижний лист с волной и таймером; «Стоп» закрывает лист и отправляет аудио.
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
    setState(() => notice = null);
    await showModalBottomSheet<void>(
      context: context,
      isDismissible: false,
      enableDrag: false,
      builder: (_) => _RecordingSheet(recorder: _recorder, language: _sessionLanguage.toUpperCase()),
    );
    await _stopRecording();
  }

  Future<void> _stopRecording() async {
    final path = await _recorder.stop();
    if (!mounted) {
      return;
    }
    setState(() => transcribing = path != null);
    if (path == null || sessionId == null) {
      return;
    }
    try {
      final file = File(path);
      final text = await context.read<Session>().api.uploadScribeAudio(sessionId!, await file.readAsBytes(), 'consult.m4a');
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
        step = _Step.draft;
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
        step = _Step.approved;
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

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    return PageScaffold(
      title: s.scribeTitle,
      actions: [
        if (step == _Step.record || step == _Step.draft)
          IconButton(icon: const Icon(Icons.close), tooltip: s.scribeDiscardButton, onPressed: busy ? null : _discard),
      ],
      children: [
        _StepBar(step: step, labels: [s.scribeConsentShort, s.scribeRecordShort, s.scribeDraftShort, s.scribeApprovedShort]),
        const SizedBox(height: AppSpacing.lg),
        if (error != null) ...[ErrorBox(error: error, onRetry: busy ? null : retry), const SizedBox(height: AppSpacing.md)],
        if (step == _Step.consent) _consentStep(s, theme),
        if (step == _Step.record) ..._recordStep(s, theme),
        if (step == _Step.draft) ..._draftStep(s, theme),
        if (step == _Step.approved && result != null) ..._approvedStep(s, theme),
      ],
    );
  }

  Widget _consentStep(S s, ThemeData theme) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              CheckboxListTile(
                value: consent,
                onChanged: (v) => setState(() => consent = v ?? false),
                title: Text(s.scribeConsentLabel, style: theme.textTheme.titleSmall),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: EdgeInsets.zero,
              ),
              const Divider(),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(icon: Icons.mic_none, text: s.scribeWhatHappens1),
              const SizedBox(height: AppSpacing.sm),
              _InfoLine(icon: Icons.description_outlined, text: s.scribeWhatHappens2),
              const SizedBox(height: AppSpacing.lg),
              Text(s.scribeLanguageLabel, style: theme.textTheme.labelSmall),
              const SizedBox(height: AppSpacing.xs),
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
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(onPressed: consent && !busy ? _start : null, icon: const Icon(Icons.play_arrow), label: Text(s.scribeStartButton)),
            ],
          ),
        ),
      );

  List<Widget> _recordStep(S s, ThemeData theme) => [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(child: Text(s.scribeTranscriptTitle, style: theme.textTheme.titleSmall)),
                    StatusChip(_sessionLanguage.toUpperCase(), tone: StatusTone.neutral),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                FilledButton.icon(onPressed: busy || transcribing ? null : _record, icon: const Icon(Icons.mic), label: Text(s.scribeRecordMic)),
                if (transcribing) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                      const SizedBox(width: AppSpacing.sm),
                      Flexible(child: Text(s.scribeTranscribing, style: theme.textTheme.bodySmall)),
                    ],
                  ),
                ],
                if (notice != null) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(notice!, style: theme.textTheme.bodySmall?.copyWith(color: AppTones.of(context).warn.fg)),
                ],
                const SizedBox(height: AppSpacing.md),
                TextField(
                  controller: transcript,
                  minLines: 4,
                  maxLines: 10,
                  decoration: InputDecoration(labelText: s.scribeTranscriptFieldLabel, alignLabelWithHint: true),
                ),
                const SizedBox(height: AppSpacing.sm),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(onPressed: busy ? null : _pasteText, icon: const Icon(Icons.content_paste), label: Text(s.scribePasteText)),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(onPressed: busy || transcribing ? null : _makeDraft, icon: const Icon(Icons.description_outlined), label: Text(s.scribeMakeDraftButton)),
      ];

  List<Widget> _draftStep(S s, ThemeData theme) => [
        Text(s.scribeDraftReviewCaption, style: theme.textTheme.bodySmall),
        for (final section in sections)
          Padding(
            padding: const EdgeInsets.only(top: AppSpacing.md),
            child: _DraftCard(title: s.scribeSectionLabel(section.name), controller: sectionControllers[section.name], minLines: 2),
          ),
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.md),
          child: _DraftCard(title: s.scribeLeafletLabel, controller: leaflet, minLines: 3),
        ),
        const SizedBox(height: AppSpacing.md),
        FilledButton.icon(onPressed: busy ? null : _approve, icon: const Icon(Icons.check_circle_outline), label: Text(s.scribeApproveButton)),
      ];

  List<Widget> _approvedStep(S s, ThemeData theme) => [
        Text(s.scribeApprovedTitle, style: theme.textTheme.titleMedium),
        SectionTitle(s.scribeLeafletUrlLabel),
        Card(
          child: ListTile(
            title: SelectableText(result!.leafletUrl, style: theme.textTheme.bodySmall),
            trailing: IconButton(icon: const Icon(Icons.copy_outlined), tooltip: s.copy, onPressed: () => _copy(result!.leafletUrl)),
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Center(
          child: Container(
            padding: const EdgeInsets.all(AppSpacing.sm),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(AppRadius.md), border: Border.all(color: AppPalette.of(context).hairline)),
            child: QrImageView(data: result!.leafletUrl, size: 200),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(child: Text(s.scribeQrHint, style: theme.textTheme.bodySmall, textAlign: TextAlign.center)),
        const SizedBox(height: AppSpacing.md),
        Row(
          children: [
            Icon(Icons.delete_outline, size: 18, color: AppPalette.of(context).muted),
            const SizedBox(width: AppSpacing.sm),
            Expanded(child: Text(s.scribeAudioDeletedNote, style: theme.textTheme.bodySmall)),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(onPressed: _resetAll, icon: const Icon(Icons.refresh), label: Text(s.scribeNewSessionButton)),
      ];
}

/// Тонкая полоса прогресса с четырьмя подписями: пройденные и текущий сегменты — акцентные.
class _StepBar extends StatelessWidget {
  const _StepBar({required this.step, required this.labels});

  final _Step step;
  final List<String> labels;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, label) in labels.indexed) ...[
          if (i > 0) const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Column(
              children: [
                Container(
                  height: 3,
                  decoration: BoxDecoration(color: i <= step.index ? colors.accent : colors.hairline, borderRadius: BorderRadius.circular(AppRadius.pill)),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  label,
                  style: theme.textTheme.labelSmall?.copyWith(color: i == step.index ? colors.ink : colors.muted, fontWeight: i == step.index ? FontWeight.w600 : FontWeight.w500),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
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

/// Раздел черновика: заголовок, метка «AI‑черновик», редактируемый текст.
class _DraftCard extends StatelessWidget {
  const _DraftCard({required this.title, required this.controller, required this.minLines});

  final String title;
  final TextEditingController? controller;
  final int minLines;

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: Text(title, style: Theme.of(context).textTheme.titleSmall)),
                  const OriginTag(Origin.ai),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextField(controller: controller, minLines: minLines, maxLines: 8),
            ],
          ),
        ),
      );
}

/// Нижний лист записи: волна по амплитуде микрофона, таймер, чип языка и круглая кнопка «Стоп».
class _RecordingSheet extends StatefulWidget {
  const _RecordingSheet({required this.recorder, required this.language});

  final AudioRecorder recorder;
  final String language;

  @override
  State<_RecordingSheet> createState() => _RecordingSheetState();
}

class _RecordingSheetState extends State<_RecordingSheet> {
  static const _bars = 24;
  final _levels = List<double>.filled(_bars, 0.08);
  late final Timer _timer;
  StreamSubscription<Amplitude>? _amplitude;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => setState(() => _seconds++));
    try {
      _amplitude = widget.recorder.onAmplitudeChanged(const Duration(milliseconds: 120)).listen((amp) {
        // dBFS от −160 до 0: всё тише −60 считаем тишиной
        final level = ((amp.current + 60) / 60).clamp(0.08, 1.0);
        setState(() {
          _levels.removeAt(0);
          _levels.add(level);
        });
      });
    } catch (_) {
      // платформа без амплитуды — волна остаётся плоской
    }
  }

  @override
  void dispose() {
    _timer.cancel();
    _amplitude?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = S.at(context);
    final theme = Theme.of(context);
    final colors = AppPalette.of(context);
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(s.scribeRecordingTitle, style: theme.textTheme.titleMedium, textAlign: TextAlign.center),
            const SizedBox(height: AppSpacing.xl),
            SizedBox(
              height: 64,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  for (final level in _levels)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      child: AnimatedContainer(
                        duration: AppDurations.fast,
                        width: 4,
                        height: 8 + 56 * level,
                        decoration: BoxDecoration(color: colors.accent, borderRadius: BorderRadius.circular(AppRadius.pill)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Row(
              children: [
                Text('$mm:$ss', style: theme.textTheme.headlineSmall?.merge(AppType.numeric)),
                const Spacer(),
                StatusChip(widget.language, tone: StatusTone.neutral),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            Center(
              child: Semantics(
                button: true,
                label: s.scribeStop,
                child: Material(
                  color: colors.danger,
                  shape: const CircleBorder(),
                  child: InkWell(
                    customBorder: const CircleBorder(),
                    onTap: () => Navigator.of(context).pop(),
                    child: SizedBox(width: 72, height: 72, child: Icon(Icons.stop, size: 36, color: theme.colorScheme.onError)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(s.scribeStop, style: theme.textTheme.labelMedium, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

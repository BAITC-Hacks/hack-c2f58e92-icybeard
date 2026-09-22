import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:record/record.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../theme/tokens.dart';
import '../theme/tones.dart';
import '../widgets/error_box.dart';
import '../widgets/origin_tag.dart';
import '../widgets/section.dart';
import '../widgets/status_chip.dart';

enum _Step { consent, transcript, draft, approved }

/// AI-скрайб: типизированная стенограмма, черновик по разделам (каждый помечен «AI‑черновик»), утверждение
/// врачом и памятка пациенту через тот же REST API, что и веб.
class ScribeScreen extends StatefulWidget {
  const ScribeScreen({super.key});

  @override
  State<ScribeScreen> createState() => _ScribeScreenState();
}

class _ScribeScreenState extends State<ScribeScreen> {
  _Step step = _Step.consent;
  bool consent = false;
  String? sessionId;
  final transcript = TextEditingController();
  List<DraftSection> sections = [];
  final Map<String, TextEditingController> sectionControllers = {};
  final leaflet = TextEditingController();
  ApproveResult? result;
  Object? error;
  bool busy = false;
  // запись с микрофона: файл во временной папке, после распознавания удаляется; аудио на сервере — до утверждения
  final AudioRecorder _recorder = AudioRecorder();
  bool recording = false;
  bool transcribing = false;

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
    });
  }

  Future<void> _start() async {
    final session = context.read<Session>();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final created = await session.api.createScribeSession(session.locale);
      setState(() {
        sessionId = created.sessionId;
        step = _Step.transcript;
      });
    } catch (e) {
      setState(() => error = e);
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _record() async {
    final s = S.at(context);
    if (!await _recorder.hasPermission()) {
      if (mounted) {
        setState(() => error = s.scribeMicDenied);
      }
      return;
    }
    final dir = await getTemporaryDirectory();
    await _recorder.start(const RecordConfig(encoder: AudioEncoder.aacLc), path: '${dir.path}/consult.m4a');
    if (mounted) {
      setState(() => recording = true);
    }
  }

  Future<void> _stopRecording() async {
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
      final text = await context.read<Session>().api.uploadScribeAudio(sessionId!, await file.readAsBytes(), 'consult.m4a');
      await file.delete();
      if (mounted) {
        setState(() => transcript.text = text);
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
      setState(() => error = e);
    } finally {
      setState(() => busy = false);
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
      setState(() {
        result = approved;
        step = _Step.approved;
      });
    } on ApiException catch (e) {
      setState(() => error = e);
    } finally {
      setState(() => busy = false);
    }
  }

  Future<void> _discard() async {
    final api = context.read<Session>().api;
    final id = sessionId;
    if (id != null) {
      try {
        await api.discardScribe(id);
      } catch (e) {
        setState(() => error = e);
        return;
      }
    }
    _resetAll();
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
        if (step == _Step.transcript || step == _Step.draft)
          IconButton(icon: const Icon(Icons.close), tooltip: s.scribeDiscardButton, onPressed: busy ? null : _discard),
      ],
      children: [
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (final (index, item) in _Step.values.indexed)
              StatusChip(
                '${index + 1} · ${_stepLabel(s, item)}',
                tone: item == step ? StatusTone.accent : item.index < step.index ? StatusTone.ok : StatusTone.neutral,
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.lg),
        if (error != null) ...[ErrorBox(error: error), const SizedBox(height: AppSpacing.md)],
        if (step == _Step.consent) ...[
          Card(
            child: SwitchListTile(
              value: consent,
              onChanged: (v) => setState(() => consent = v),
              title: Text(s.scribeConsentLabel),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(onPressed: consent && !busy ? _start : null, icon: const Icon(Icons.play_arrow), label: Text(s.scribeStartButton)),
        ],
        if (step == _Step.transcript) ...[
          Row(
            children: [
              if (!recording)
                FilledButton.tonalIcon(onPressed: busy || transcribing ? null : _record, icon: const Icon(Icons.mic_none), label: Text(s.scribeRecordMic))
              else
                FilledButton.icon(onPressed: _stopRecording, icon: const Icon(Icons.stop_circle_outlined), label: Text(s.scribeStopRecording)),
              if (transcribing) ...[const SizedBox(width: AppSpacing.md), const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)), const SizedBox(width: AppSpacing.sm), Text(s.scribeTranscribing, style: theme.textTheme.bodySmall)],
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(s.scribeNoAudioCaption, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.sm),
          TextField(
            controller: transcript,
            minLines: 6,
            maxLines: 12,
            decoration: InputDecoration(labelText: s.scribeTranscriptFieldLabel, alignLabelWithHint: true),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(onPressed: busy ? null : _makeDraft, icon: const Icon(Icons.description_outlined), label: Text(s.scribeMakeDraftButton)),
        ],
        if (step == _Step.draft) ...[
          Text(s.scribeDraftReviewCaption, style: theme.textTheme.bodySmall),
          for (final section in sections)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.md),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(child: Text(s.scribeSectionLabel(section.name), style: theme.textTheme.titleMedium)),
                          const OriginTag(Origin.ai),
                        ],
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      TextField(controller: sectionControllers[section.name], minLines: 2, maxLines: 8),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: AppSpacing.md),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.lg),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(child: Text(s.scribeLeafletLabel, style: theme.textTheme.titleMedium)),
                      const OriginTag(Origin.ai),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  TextField(controller: leaflet, minLines: 3, maxLines: 8),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(onPressed: busy ? null : _approve, icon: const Icon(Icons.check_circle_outline), label: Text(s.scribeApproveButton)),
        ],
        if (step == _Step.approved && result != null) ...[
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
          Text(s.scribeAudioDeletedNote, style: theme.textTheme.bodySmall),
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(onPressed: _resetAll, icon: const Icon(Icons.refresh), label: Text(s.scribeNewSessionButton)),
        ],
      ],
    );
  }

  static String _stepLabel(S s, _Step step) => switch (step) {
        _Step.consent => s.scribeConsentShort,
        _Step.transcript => s.scribeTranscriptFieldLabel,
        _Step.draft => s.scribeDraftShort,
        _Step.approved => s.scribeApprovedShort,
      };
}

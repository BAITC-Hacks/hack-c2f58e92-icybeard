import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/client.dart';
import '../api/models.dart';
import '../l10n/strings.dart';
import '../state/session.dart';
import '../widgets/common.dart';

enum _Step { consent, transcript, draft, approved }

/// AI-скрайб: типизированная стенограмма (без записи с микрофона — см. docs/finish-plan.md 5.12),
/// черновик по разделам, утверждение и памятка пациенту через тот же REST API, что и веб.
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

  @override
  void dispose() {
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

  Future<void> _makeDraft() async {
    final api = context.read<Session>().api;
    final id = sessionId;
    if (id == null) return;
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
    if (id == null) return;
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

  @override
  Widget build(BuildContext context) {
    final s = S.of(context.watch<Session>().locale);
    return Scaffold(
      appBar: AppBar(
        title: Text(s.scribeTitle),
        actions: [
          if (step == _Step.transcript || step == _Step.draft)
            IconButton(icon: const Icon(Icons.close), tooltip: s.scribeDiscardButton, onPressed: busy ? null : _discard),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ErrorBox(error: error),
          if (step == _Step.consent) ...[
            SwitchListTile(
              value: consent,
              onChanged: (v) => setState(() => consent = v),
              title: Text(s.scribeConsentLabel),
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: consent && !busy ? _start : null,
              icon: const Icon(Icons.play_arrow),
              label: Text(s.scribeStartButton),
            ),
          ],
          if (step == _Step.transcript) ...[
            Text(s.scribeNoAudioCaption, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 8),
            TextField(
              controller: transcript,
              minLines: 6,
              maxLines: 12,
              decoration: InputDecoration(labelText: s.scribeTranscriptFieldLabel, alignLabelWithHint: true),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: busy ? null : _makeDraft,
              icon: const Icon(Icons.description),
              label: Text(s.scribeMakeDraftButton),
            ),
          ],
          if (step == _Step.draft) ...[
            Text(s.scribeDraftReviewCaption, style: Theme.of(context).textTheme.bodySmall),
            for (final section in sections)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(s.scribeSectionLabel(section.name), style: Theme.of(context).textTheme.titleMedium),
                        const SizedBox(height: 4),
                        TextField(controller: sectionControllers[section.name], minLines: 2, maxLines: 8),
                      ],
                    ),
                  ),
                ),
              ),
            const SizedBox(height: 12),
            TextField(controller: leaflet, minLines: 3, maxLines: 8, decoration: InputDecoration(labelText: s.scribeLeafletLabel)),
            const SizedBox(height: 12),
            FilledButton.icon(onPressed: busy ? null : _approve, icon: const Icon(Icons.check_circle), label: Text(s.scribeApproveButton)),
          ],
          if (step == _Step.approved && result != null) ...[
            Text(s.scribeApprovedTitle, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            SectionTitle(s.scribeLeafletTokenLabel),
            SelectableText(result!.leafletToken),
            SectionTitle(s.scribeLeafletUrlLabel),
            SelectableText(result!.leafletUrl),
            const SizedBox(height: 12),
            Text(s.scribeAudioDeletedNote, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(s.scribeNoQrNote, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 16),
            OutlinedButton.icon(onPressed: _resetAll, icon: const Icon(Icons.refresh), label: Text(s.scribeNewSessionButton)),
          ],
        ],
      ),
    );
  }
}

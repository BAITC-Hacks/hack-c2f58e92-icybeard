import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/session.dart';

class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = S.of(session.locale);
    final cards = <(String, String, String, IconData)>[
      ('/wait', s.waitTitle, s.waitSubtitle, Icons.hourglass_bottom),
      ('/medicines', s.medicinesTitle, s.medicinesSubtitle, Icons.medication),
      ('/vaccination', s.vaccinationTitle, s.vaccinationSubtitle, Icons.vaccines),
      if (session.isDoctor) ('/worklist', s.worklistTitle, s.worklistSubtitle, Icons.list_alt),
      if (session.isDoctor) ('/referral', s.referralTitle, s.referralSubtitle, Icons.assignment),
      if (session.isDoctor) ('/decisions', s.decisionsTitle, s.decisionsSubtitle, Icons.history_edu),
      if (session.isDoctor) ('/scribe', s.scribeTitle, s.scribeSubtitle, Icons.edit_note),
    ];
    return Scaffold(
      appBar: AppBar(
        title: const Text('Darumen Care'),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => context.push('/settings'))],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SegmentedButton<String>(
            segments: [
              ButtonSegment(value: 'citizen', label: Text(s.roleCitizen), icon: const Icon(Icons.person)),
              ButtonSegment(value: 'doctor', label: Text(s.roleDoctor), icon: const Icon(Icons.medical_services)),
            ],
            selected: {session.role},
            onSelectionChanged: (v) => session.update(role: v.first),
          ),
          const SizedBox(height: 8),
          Text(s.demoStatus(Session.demoActors[session.role] ?? '', session.region), style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 8),
          for (final c in cards)
            Card(
              child: ListTile(
                leading: Icon(c.$4),
                title: Text(c.$2),
                subtitle: Text(c.$3),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(c.$1),
              ),
            ),
          const SizedBox(height: 16),
          Text(s.footerNote, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
  }
}

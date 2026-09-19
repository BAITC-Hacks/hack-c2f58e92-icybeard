import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/strings.dart';
import '../state/session.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final TextEditingController baseUrl = TextEditingController(text: context.read<Session>().baseUrl);
  late final TextEditingController region = TextEditingController(text: context.read<Session>().region);
  late final TextEditingController keycloakUrl = TextEditingController(text: context.read<Session>().keycloakUrl);
  final TextEditingController username = TextEditingController(text: 'doctor1');
  final TextEditingController password = TextEditingController();
  bool loggingIn = false;
  String? loginError;

  Future<void> _login() async {
    final session = context.read<Session>();
    setState(() {
      loggingIn = true;
      loginError = null;
    });
    try {
      await session.update(keycloakUrl: keycloakUrl.text.trim());
      await session.login(username.text.trim(), password.text);
    } catch (e) {
      setState(() => loginError = '$e');
    } finally {
      if (mounted) setState(() => loggingIn = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<Session>();
    final s = S.of(session.locale);
    return Scaffold(
      appBar: AppBar(title: Text(s.settingsTitle)),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(controller: baseUrl, decoration: InputDecoration(labelText: s.apiAddressLabel, helperText: s.apiAddressHelper)),
          const SizedBox(height: 8),
          TextField(controller: region, decoration: InputDecoration(labelText: s.regionLabelHint)),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: const [ButtonSegment(value: 'ru', label: Text('RU')), ButtonSegment(value: 'kk', label: Text('KK'))],
            selected: {session.locale},
            onSelectionChanged: (v) => session.update(locale: v.first),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () async {
              await session.update(baseUrl: baseUrl.text.trim(), region: region.text.trim());
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text(s.saveButton),
          ),
          const Divider(height: 32),
          Text(s.keycloakLoginTitle, style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          if (session.isKeycloak) ...[
            Text(s.loggedInAs(session.actor ?? '', session.role, session.region)),
            const SizedBox(height: 8),
            OutlinedButton(onPressed: () => session.logout(), child: Text(s.logoutButton)),
          ] else ...[
            TextField(controller: keycloakUrl, decoration: InputDecoration(labelText: s.keycloakAddressLabel, helperText: s.keycloakAddressHelper)),
            const SizedBox(height: 8),
            TextField(controller: username, decoration: InputDecoration(labelText: s.usernameLabel, helperText: s.usernameHelper)),
            const SizedBox(height: 8),
            TextField(controller: password, obscureText: true, decoration: InputDecoration(labelText: s.passwordLabel)),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: loggingIn ? null : _login,
              child: Text(loggingIn ? s.loggingInButton : s.loginButton),
            ),
            if (loginError != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(loginError!, style: const TextStyle(color: Colors.red, fontSize: 12))),
            const SizedBox(height: 8),
            Text(s.demoModeHint, style: const TextStyle(fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

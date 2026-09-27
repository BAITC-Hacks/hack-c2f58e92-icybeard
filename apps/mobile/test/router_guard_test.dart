import 'package:darumen/router/guards.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_rbac_test.dart' show FakeBackend, signedIn;
import 'session_test.dart' show session;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Session anonymous;
  late Map<String, Session> byRole;

  setUpAll(() async {
    anonymous = await session(roles: []);
    byRole = {
      'citizen': await signedIn(FakeBackend(roles: ['citizen'], claims: {'iin': '000000000001'})),
      'doctor': await signedIn(FakeBackend(roles: ['doctor'], claims: {'region_kato': '75'})),
      'org_admin': await signedIn(FakeBackend(roles: ['org_admin'], claims: {'mo_code': '028B', 'region_kato': '75'})),
      'regulator': await signedIn(FakeBackend(roles: ['regulator'])),
      'steward': await signedIn(FakeBackend(roles: ['steward'])),
      'auditor': await signedIn(FakeBackend(roles: ['auditor'])),
      'admin': await signedIn(FakeBackend(roles: ['admin'])),
    };
  });

  test('without a session only login, the second factor and password reset are reachable; the target is kept in ?from', () {
    expect(guard(anonymous, '/'), '/login');
    expect(guard(anonymous, '/login'), isNull);
    expect(guard(anonymous, '/login/otp'), isNull);
    expect(guard(anonymous, '/login/forgot'), isNull);
    expect(guard(anonymous, '/home'), '/login?from=%2Fhome');
    expect(guard(anonymous, '/home/wait'), '/login?from=%2Fhome%2Fwait', reason: 'гостевого режима нет — даже публичные справочники за входом');
    expect(guard(anonymous, '/updates'), '/login?from=%2Fupdates');
    expect(guard(anonymous, '/doctor/patients'), '/login?from=%2Fdoctor%2Fpatients');
    expect(guard(anonymous, '/web'), '/login?from=%2Fweb');
  });

  test('each of the 7 roles lands on its home: doctor shell, citizen shell or the web-only screen', () {
    final homes = {for (final e in byRole.entries) e.key: guard(e.value, '/')};
    expect(homes, {
      'citizen': '/home',
      'doctor': '/doctor/patients',
      'org_admin': '/doctor/patients',
      'regulator': '/web',
      'steward': '/web',
      'auditor': '/web',
      'admin': '/doctor/patients',
    });
    for (final s in byRole.values) {
      expect(guard(s, '/login'), s.home, reason: 'вошедший на /login уходит домой');
      expect(guard(s, '/login/forgot'), s.home);
    }
  });

  test('citizen: never enters the doctor shell or the web-only screen; medicines are allowed', () {
    final citizen = byRole['citizen']!;
    expect(guard(citizen, '/home/route'), isNull);
    expect(guard(citizen, '/home/medicines'), isNull);
    expect(guard(citizen, '/profile/security'), isNull);
    expect(guard(citizen, '/doctor/scribe'), '/home');
    expect(guard(citizen, '/doctor/decisions'), '/home');
    expect(guard(citizen, '/web'), '/home');
  });

  test('doctor: whole doctor shell including assistant, scribe, journal and security', () {
    final doctor = byRole['doctor']!;
    for (final path in [
      '/doctor/patients',
      '/doctor/patients/SYN-75-028B-381-01',
      '/doctor/patients/SYN-75-028B-381-01/referral',
      '/doctor/patients/SYN-75-028B-381-01/scribe',
      '/doctor/decisions',
      '/doctor/referral',
      '/doctor/scribe',
      '/doctor/profile/security',
    ]) {
      expect(guard(doctor, path), isNull, reason: path);
    }
    expect(guard(doctor, '/home'), '/doctor/patients');
    expect(guard(doctor, '/updates'), '/doctor/patients');
    expect(guard(doctor, '/web'), '/doctor/patients');
  });

  test('org_admin: worklist, patient route and journal, but no assistant (referral.assist) and no scribe (scribe.use)', () {
    final chief = byRole['org_admin']!;
    expect(guard(chief, '/doctor/patients'), isNull);
    expect(guard(chief, '/doctor/patients/SYN-1'), isNull);
    expect(guard(chief, '/doctor/decisions'), isNull);
    expect(guard(chief, '/doctor/patients/SYN-1/referral'), '/doctor/patients');
    expect(guard(chief, '/doctor/patients/SYN-1/scribe'), '/doctor/patients');
    expect(guard(chief, '/doctor/referral'), '/doctor/patients');
    expect(guard(chief, '/doctor/scribe'), '/doctor/patients');
  });

  test('regulator, steward, auditor: only the web-only screen', () {
    for (final role in ['regulator', 'steward', 'auditor']) {
      final s = byRole[role]!;
      expect(guard(s, '/web'), isNull, reason: role);
      expect(guard(s, '/home'), '/web', reason: role);
      expect(guard(s, '/profile'), '/web', reason: role);
      expect(guard(s, '/doctor/patients'), '/web', reason: role);
      expect(guard(s, '/doctor/decisions'), '/web', reason: role);
    }
  });

  test('admin has every permission and lives in the doctor shell', () {
    final admin = byRole['admin']!;
    expect(guard(admin, '/doctor/scribe'), isNull);
    expect(guard(admin, '/doctor/patients/SYN-1/referral'), isNull);
    expect(guard(admin, '/home'), '/doctor/patients');
  });

  test('requiredPermissions maps screens to rbac.md codes', () {
    expect(requiredPermissions('/doctor/patients/X/referral'), [Perm.referralAssist]);
    expect(requiredPermissions('/doctor/scribe'), [Perm.scribeUse]);
    expect(requiredPermissions('/doctor/decisions'), [Perm.decisionsOwn, Perm.decisionsAll]);
    expect(requiredPermissions('/home/medicines'), [Perm.medicinesCheck]);
    expect(requiredPermissions('/doctor/patients'), isNull);
  });

  test('afterLogin returns only to safe internal paths of the right shell', () {
    final citizen = byRole['citizen']!;
    final doctor = byRole['doctor']!;
    expect(afterLogin(citizen, '/home/route'), '/home/route');
    expect(afterLogin(citizen, '/doctor/patients'), '/home');
    expect(afterLogin(doctor, '/doctor/patients/SYN-1'), '/doctor/patients/SYN-1');
    expect(afterLogin(doctor, '/updates'), '/doctor/patients');
    expect(afterLogin(byRole['regulator']!, '/doctor/patients'), '/web');
    expect(afterLogin(citizen, '//evil.example'), '/home');
    expect(afterLogin(citizen, 'https://evil.example'), '/home');
    expect(afterLogin(citizen, '/login'), '/home');
    expect(afterLogin(citizen, '/login/otp'), '/home');
    expect(afterLogin(citizen, null), '/home');
  });
}

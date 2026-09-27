import 'package:darumen/router/guards.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show session;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Session anonymous;
  late Session citizen;
  late Session doctor;

  setUpAll(() async {
    anonymous = await session(roles: []);
    citizen = await session(roles: ['citizen'], iin: '000000000001');
    await citizen.login('citizen1', 'darumen');
    doctor = await session(roles: ['doctor'], region: '75');
    await doctor.login('doctor1', 'darumen');
  });

  test('without a session only the login screen is reachable, the target is kept in ?from', () {
    expect(guard(anonymous, '/'), '/login');
    expect(guard(anonymous, '/login'), isNull);
    expect(guard(anonymous, '/home'), '/login?from=%2Fhome');
    expect(guard(anonymous, '/home/wait'), '/login?from=%2Fhome%2Fwait', reason: 'гостевого режима нет — даже публичные справочники за входом');
    expect(guard(anonymous, '/home/route'), '/login?from=%2Fhome%2Froute');
    expect(guard(anonymous, '/updates'), '/login?from=%2Fupdates');
    expect(guard(anonymous, '/doctor/patients'), '/login?from=%2Fdoctor%2Fpatients');
  });

  test('citizen: never enters the doctor shell, login bounces home', () {
    expect(guard(citizen, '/'), '/home');
    expect(guard(citizen, '/login'), '/home');
    expect(guard(citizen, '/home/route'), isNull);
    expect(guard(citizen, '/profile'), isNull);
    expect(guard(citizen, '/doctor/scribe'), '/home');
    expect(guard(citizen, '/doctor/decisions'), '/home');
  });

  test('doctor: lives in the doctor shell only, decisions is a tab, assistant and scribe stay reachable', () {
    expect(guard(doctor, '/'), '/doctor/patients');
    expect(guard(doctor, '/login'), '/doctor/patients');
    expect(guard(doctor, '/doctor/patients'), isNull);
    expect(guard(doctor, '/doctor/patients/SYN-75-028B-381-01'), isNull);
    expect(guard(doctor, '/doctor/patients/SYN-75-028B-381-01/referral'), isNull);
    expect(guard(doctor, '/doctor/patients/SYN-75-028B-381-01/scribe'), isNull);
    expect(guard(doctor, '/doctor/decisions'), isNull);
    expect(guard(doctor, '/doctor/referral'), isNull);
    expect(guard(doctor, '/doctor/scribe'), isNull);
    expect(guard(doctor, '/home'), '/doctor/patients');
    expect(guard(doctor, '/updates'), '/doctor/patients');
  });

  test('afterLogin returns only to safe internal paths of the right shell', () {
    expect(afterLogin(citizen, '/home/route'), '/home/route');
    expect(afterLogin(citizen, '/doctor/patients'), '/home');
    expect(afterLogin(doctor, '/doctor/patients/SYN-1'), '/doctor/patients/SYN-1');
    expect(afterLogin(doctor, '/updates'), '/doctor/patients');
    expect(afterLogin(citizen, '//evil.example'), '/home');
    expect(afterLogin(citizen, 'https://evil.example'), '/home');
    expect(afterLogin(citizen, '/login'), '/home');
    expect(afterLogin(citizen, null), '/home');
  });
}

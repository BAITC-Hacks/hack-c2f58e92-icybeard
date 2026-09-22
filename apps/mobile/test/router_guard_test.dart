import 'package:darumen/router/guards.dart';
import 'package:darumen/state/session.dart';
import 'package:flutter_test/flutter_test.dart';

import 'session_test.dart' show session;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Session guest;
  late Session citizen;
  late Session doctor;

  setUpAll(() async {
    guest = await session(roles: []);
    citizen = await session(roles: ['citizen'], iin: '000000000001');
    await citizen.login('citizen1', 'darumen');
    doctor = await session(roles: ['doctor'], region: '75');
    await doctor.login('doctor1', 'darumen');
  });

  test('guest: public shell open, doctor shell and root redirect', () {
    expect(guard(guest, '/'), '/home');
    expect(guard(guest, '/login'), isNull);
    expect(guard(guest, '/home'), isNull);
    expect(guard(guest, '/home/wait'), isNull);
    expect(guard(guest, '/home/route'), isNull, reason: 'экран сам показывает приглашение войти');
    expect(guard(guest, '/updates'), isNull);
    expect(guard(guest, '/doctor/patients'), '/login?from=%2Fdoctor%2Fpatients');
  });

  test('citizen: never enters the doctor shell, login bounces home', () {
    expect(guard(citizen, '/'), '/home');
    expect(guard(citizen, '/login'), '/home');
    expect(guard(citizen, '/home/route'), isNull);
    expect(guard(citizen, '/profile'), isNull);
    expect(guard(citizen, '/doctor/scribe'), '/home');
  });

  test('doctor: lives in the doctor shell only', () {
    expect(guard(doctor, '/'), '/doctor/patients');
    expect(guard(doctor, '/login'), '/doctor/patients');
    expect(guard(doctor, '/doctor/patients'), isNull);
    expect(guard(doctor, '/doctor/patients/SYN-75-028B-381-01'), isNull);
    expect(guard(doctor, '/doctor/referral/decisions'), isNull);
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

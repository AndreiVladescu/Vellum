// Loan due-date notifications (roadmap v1.4.2): which reminders exist for which
// loans and dates, and that the service swaps them as loans and the preference
// change. The OS is a fake.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations_en.dart';
import 'package:vellum/loans/loan_reminders.dart';
import 'package:vellum/settings/app_settings.dart';

Book _book(String title) => Book(
      id: 'b-$title',
      title: title,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

LoanEntry _entry(
  String id, {
  String title = 'Dune',
  String borrower = 'Alice',
  DateTime? dueAt,
  DateTime? returnedAt,
}) =>
    (
      loan: Loan(
        id: id,
        copyId: 'c-$id',
        borrower: borrower,
        loanedAt: DateTime(2026, 6, 1),
        returnedAt: returnedAt,
        updatedAt: DateTime(2026, 6, 1),
        needsPush: false,
        remind: true,
        dueAt: dueAt,
      ),
      book: _book(title),
    );

class FakeNotifier implements ReminderNotifier {
  @override
  bool supported = true;
  final List<List<PlannedReminder>> calls = [];

  @override
  Future<bool> requestPermission() async => true;

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async =>
      calls.add(reminders);
}

void main() {
  final l10n = L10nEn();
  // Friday 10 July 2026, 14:30 local.
  final now = DateTime(2026, 7, 10, 14, 30);

  List<PlannedReminder> plan(List<LoanEntry> loans, {DateTime? at}) =>
      LoanReminderPlanner.plan(loans, l10n, now: at ?? now);

  group('planner', () {
    test('a loan due in a few days gets the day-before and due-day mornings',
        () {
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      expect(r.map((e) => e.kind),
          [LoanReminderKind.dayBefore, LoanReminderKind.dueDay]);
      expect(r[0].at, DateTime(2026, 7, 13, loanReminderHour));
      expect(r[1].at, DateTime(2026, 7, 14, loanReminderHour));
      expect(r[0].title, 'Dune');
      expect(r[0].body, 'Due tomorrow — lent to Alice');
      expect(r[1].body, 'Due today — lent to Alice');
      expect(r[0].payload, 'loan:l1');
    });

    test('due tomorrow: the day-before morning has passed, only the due day',
        () {
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 11))]);
      expect(r.map((e) => e.kind), [LoanReminderKind.dueDay]);
    });

    test('due today after the morning has passed: nothing, then overdue next day',
        () {
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 10))]);
      expect(r.map((e) => e.kind), [LoanReminderKind.overdue]);
      expect(r.single.at, DateTime(2026, 7, 11, loanReminderHour));
    });

    test('due today before the morning: the due-day reminder is still ahead',
        () {
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 10))],
          at: DateTime(2026, 7, 10, 7));
      expect(r.map((e) => e.kind), [LoanReminderKind.dueDay]);
    });

    test('an overdue loan gets one reminder at the next morning', () {
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 1))]);
      expect(r.single.kind, LoanReminderKind.overdue);
      expect(r.single.at, DateTime(2026, 7, 11, loanReminderHour));
      expect(r.single.body, 'Overdue — lent to Alice');
    });

    test('returned loans and loans without a date get nothing', () {
      final r = plan([
        _entry('a', dueAt: DateTime(2026, 7, 14), returnedAt: DateTime(2026, 7, 9)),
        _entry('b'),
      ]);
      expect(r, isEmpty);
    });

    test('due-date instants are compared as local days, not instants', () {
      // Stored as midnight UTC the same calendar day: still the 14th locally
      // for the day it was typed in.
      final r = plan([_entry('l1', dueAt: DateTime(2026, 7, 14, 23, 59))]);
      expect(r.last.at, DateTime(2026, 7, 14, loanReminderHour));
    });

    test('ids are stable per loan and kind, and differ between them', () {
      final a = LoanReminderPlanner.reminderId('loan-1', LoanReminderKind.dueDay);
      expect(a, LoanReminderPlanner.reminderId('loan-1', LoanReminderKind.dueDay));
      expect(a, isNot(LoanReminderPlanner.reminderId('loan-1', LoanReminderKind.dayBefore)));
      expect(a, isNot(LoanReminderPlanner.reminderId('loan-2', LoanReminderKind.dueDay)));
      expect(a, inInclusiveRange(0, 0x7fffffff));
    });

    test('the result is sorted by time and capped', () {
      final many = [
        for (var i = 0; i < 80; i++)
          _entry('l$i', dueAt: DateTime(2026, 8, 1).add(Duration(days: i))),
      ];
      final r = plan(many);
      expect(r.length, LoanReminderPlanner.maxReminders);
      for (var i = 1; i < r.length; i++) {
        expect(r[i].at.isBefore(r[i - 1].at), isFalse);
      }
    });
  });

  group('service', () {
    late FakeNotifier notifier;
    late StreamController<List<LoanEntry>> loans;
    late AppSettingsStore settings;
    late LoanReminderService service;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      notifier = FakeNotifier();
      loans = StreamController<List<LoanEntry>>();
      service = LoanReminderService(
        loans: loans.stream,
        settings: settings,
        notifier: notifier,
        l10n: l10n,
        clock: () => now,
      )..start();
    });

    tearDown(() async {
      service.dispose();
      await loans.close();
    });

    Future<void> settle() => Future<void>.delayed(Duration.zero);

    test('schedules nothing while the preference is off', () async {
      loans.add([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      await settle();
      // Nothing applied yet is the same as an empty schedule: no OS call.
      expect(notifier.calls.every((c) => c.isEmpty), isTrue);
    });

    test('turning it on schedules, a new loan reschedules, a return clears',
        () async {
      loans.add([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      await settle();
      await settings.setLoanReminders(true);
      await settle();
      expect(notifier.calls.last, hasLength(2));

      loans.add([
        _entry('l1', dueAt: DateTime(2026, 7, 14)),
        _entry('l2', dueAt: DateTime(2026, 7, 20)),
      ]);
      await settle();
      expect(notifier.calls.last, hasLength(4));

      loans.add([
        _entry('l1', dueAt: DateTime(2026, 7, 14), returnedAt: now),
        _entry('l2', dueAt: DateTime(2026, 7, 20)),
      ]);
      await settle();
      expect(notifier.calls.last.map((r) => r.loanId).toSet(), {'l2'});

      await settings.setLoanReminders(false);
      await settle();
      expect(notifier.calls.last, isEmpty);
    });

    test('an unchanged plan is not pushed to the OS again', () async {
      await settings.setLoanReminders(true);
      loans.add([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      await settle();
      final count = notifier.calls.length;
      loans.add([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      await settle();
      expect(notifier.calls.length, count);
    });

    test('an unsupported platform does nothing at all', () async {
      service.dispose();
      final quiet = FakeNotifier()..supported = false;
      final other = LoanReminderService(
        loans: loans.stream,
        settings: settings,
        notifier: quiet,
        l10n: l10n,
        clock: () => now,
      )..start();
      await settings.setLoanReminders(true);
      loans.add([_entry('l1', dueAt: DateTime(2026, 7, 14))]);
      await settle();
      expect(quiet.calls, isEmpty);
      other.dispose();
    });
  });
}

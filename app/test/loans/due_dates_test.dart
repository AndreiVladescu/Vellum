// Loan due dates (plan 5 #27). Dates are compared as *local calendar days*, not
// instants, because a due date is an agreement about a day — "back by Friday" —
// and a book due today must not read as overdue at 00:01 because the stored
// moment happened to be midnight UTC.
import 'package:drift/drift.dart' show Value;
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/loans/due_dates.dart';

Loan _loan({
  String id = 'l1',
  String borrower = 'Alice',
  DateTime? loanedAt,
  DateTime? dueAt,
  DateTime? returnedAt,
  DateTime? reminderSentAt,
}) =>
    Loan(
      id: id,
      copyId: 'c1',
      borrower: borrower,
      loanedAt: loanedAt ?? DateTime(2026, 6, 1),
      returnedAt: returnedAt,
      updatedAt: DateTime(2026, 6, 1),
      needsPush: false,
      dueAt: dueAt,
      reminderSentAt: reminderSentAt,
    );

void main() {
  final now = DateTime(2026, 7, 10, 14, 30);

  group('urgency', () {
    test('a loan with no due date is not overdue, ever', () {
      // "Borrow it as long as you like" is a real arrangement, and nagging about
      // it would be inventing an agreement nobody made.
      expect(LoanDue.urgencyOf(_loan(), now: now), LoanUrgency.noDate);
      expect(LoanDue.daysOverdue(_loan(), now: now), 0);
    });

    test('due today is due today, not overdue', () {
      // The bug this prevents: comparing instants makes a book due "today"
      // overdue from one minute past midnight.
      final loan = _loan(dueAt: DateTime(2026, 7, 10, 0, 0));
      expect(LoanDue.urgencyOf(loan, now: now), LoanUrgency.dueToday);
      expect(LoanDue.daysOverdue(loan, now: now), 0);
    });

    test('late in the evening of the due day is still not overdue', () {
      final loan = _loan(dueAt: DateTime(2026, 7, 10));
      final lateEvening = DateTime(2026, 7, 10, 23, 59);
      expect(LoanDue.urgencyOf(loan, now: lateEvening), LoanUrgency.dueToday);
    });

    test('the next morning is one day overdue', () {
      final loan = _loan(dueAt: DateTime(2026, 7, 10));
      final nextMorning = DateTime(2026, 7, 11, 8, 0);
      expect(LoanDue.urgencyOf(loan, now: nextMorning), LoanUrgency.overdue);
      expect(LoanDue.daysOverdue(loan, now: nextMorning), 1);
      expect(LoanDue.describe(loan, now: nextMorning), '1 day overdue');
    });

    test('soon and later are distinguished', () {
      expect(
        LoanDue.urgencyOf(_loan(dueAt: DateTime(2026, 7, 12)), now: now),
        LoanUrgency.dueSoon,
      );
      expect(
        LoanDue.urgencyOf(_loan(dueAt: DateTime(2026, 8, 12)), now: now),
        LoanUrgency.dueLater,
      );
    });

    test('a returned loan is never overdue, however late it was', () {
      final loan = _loan(
        dueAt: DateTime(2026, 1, 1),
        returnedAt: DateTime(2026, 7, 9),
      );
      expect(LoanDue.urgencyOf(loan, now: now), LoanUrgency.returned);
      expect(LoanDue.daysOverdue(loan, now: now), 0);
    });

    test('only overdue and due-today demand attention', () {
      expect(LoanUrgency.overdue.needsAttention, true);
      expect(LoanUrgency.dueToday.needsAttention, true);
      expect(LoanUrgency.dueSoon.needsAttention, false);
      expect(LoanUrgency.noDate.needsAttention, false);
      expect(LoanUrgency.returned.needsAttention, false);
    });
  });

  group('ordering', () {
    test('most urgent first, undated last', () {
      final sorted = LoanDue.sortByUrgency([
        _loan(id: 'none', borrower: 'Zoe'),
        _loan(id: 'later', dueAt: DateTime(2026, 8, 1)),
        _loan(id: 'overdue', dueAt: DateTime(2026, 6, 1)),
        _loan(id: 'today', dueAt: DateTime(2026, 7, 10)),
      ], now: now);
      expect(
        sorted.map((l) => l.id),
        ['overdue', 'today', 'later', 'none'],
      );
    });

    test('two loans due the same day fall back to the borrower name', () {
      final sorted = LoanDue.sortByUrgency([
        _loan(id: 'b', borrower: 'Bob', dueAt: DateTime(2026, 7, 12)),
        _loan(id: 'a', borrower: 'Ana', dueAt: DateTime(2026, 7, 12)),
      ], now: now);
      expect(sorted.map((l) => l.id), ['a', 'b']);
    });

    test('an empty list stays empty', () {
      expect(LoanDue.sortByUrgency(const [], now: now), isEmpty);
    });
  });

  group('reminders', () {
    test('overdue and due-today loans need one', () {
      final loans = [
        _loan(id: 'overdue', dueAt: DateTime(2026, 7, 1)),
        _loan(id: 'today', dueAt: DateTime(2026, 7, 10)),
        _loan(id: 'soon', dueAt: DateTime(2026, 7, 12)),
        _loan(id: 'none'),
      ];
      expect(
        LoanDue.needingReminder(loans, now: now).map((l) => l.id),
        ['overdue', 'today'],
      );
    });

    test('a returned loan never needs one', () {
      final loans = [
        _loan(
          id: 'done',
          dueAt: DateTime(2026, 1, 1),
          returnedAt: DateTime(2026, 2, 1),
        ),
      ];
      expect(LoanDue.needingReminder(loans, now: now), isEmpty);
    });

    test('a reminder given today is not repeated today', () {
      final loans = [
        _loan(
          id: 'nagged',
          dueAt: DateTime(2026, 7, 1),
          reminderSentAt: DateTime(2026, 7, 10, 9),
        ),
      ];
      expect(LoanDue.needingReminder(loans, now: now), isEmpty);
    });

    test('a reminder given last week comes back for a still-overdue book', () {
      // Being reminded once must not mean being reminded once ever — the book is
      // still gone.
      final loans = [
        _loan(
          id: 'still-out',
          dueAt: DateTime(2026, 7, 1),
          reminderSentAt: DateTime(2026, 7, 3),
        ),
      ];
      expect(
        LoanDue.needingReminder(loans, now: now).map((l) => l.id),
        ['still-out'],
      );
    });
  });

  group('wording', () {
    test('describes each state in words a person would use', () {
      expect(LoanDue.describe(_loan(), now: now), 'No due date');
      expect(
        LoanDue.describe(_loan(dueAt: DateTime(2026, 7, 10)), now: now),
        'Due today',
      );
      expect(
        LoanDue.describe(_loan(dueAt: DateTime(2026, 7, 11)), now: now),
        'Due tomorrow',
      );
      expect(
        LoanDue.describe(_loan(dueAt: DateTime(2026, 7, 13)), now: now),
        'Due in 3 days',
      );
      expect(
        LoanDue.describe(_loan(dueAt: DateTime(2026, 7, 8)), now: now),
        '2 days overdue',
      );
    });

    test('the nudge names the book and the dates', () {
      final message = LoanDue.reminderMessage(
        _loan(loanedAt: DateTime(2026, 6, 1), dueAt: DateTime(2026, 7, 1)),
        'Dune',
      );
      expect(message, contains('Dune'));
      expect(message, contains('2026-06-01'));
      expect(message, contains('2026-07-01'));
    });

    test('an undated loan gets a softer nudge with no invented deadline', () {
      final message = LoanDue.reminderMessage(_loan(), 'Dune');
      expect(message, contains('Dune'));
      expect(message, isNot(contains('due')));
    });
  });

  test('a Value-typed companion round-trips the new columns', () {
    // Guards the drift wiring: a nullable column added to a synced table is easy
    // to declare and forget to plumb.
    const companion = LoansCompanion(
      dueAt: Value(null),
      borrowerContact: Value('ana@example.com'),
      notes: Value('lent at book club'),
    );
    expect(companion.borrowerContact.value, 'ana@example.com');
    expect(companion.notes.value, 'lent at book club');
  });
}

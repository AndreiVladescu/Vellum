import '../data/database.dart';

/// How a loan stands against its due date (plan 5 #27).
enum LoanUrgency {
  /// No date was agreed. A real arrangement, not missing data.
  noDate,
  dueLater,
  dueSoon,
  dueToday,
  overdue,
  returned;

  bool get needsAttention =>
      this == LoanUrgency.overdue || this == LoanUrgency.dueToday;
}

/// Everything the loans list needs to sort and badge a loan.
///
/// Pure functions over a row and "now", because due-date arithmetic is where
/// time-zone and end-of-day mistakes live: a book due *today* must not read as
/// overdue at 00:01 just because the stored instant was midnight UTC.
class LoanDue {
  const LoanDue._();

  /// Days a loan is due within to count as "due soon".
  static const soonWithinDays = 3;

  /// Compares by *local calendar day*, not by instant. A due date is an
  /// agreement about a day ("back by Friday"), so treating 23:00 local on the
  /// due day as overdue would be wrong in the way people notice.
  static LoanUrgency urgencyOf(Loan loan, {DateTime? now}) {
    if (loan.returnedAt != null) return LoanUrgency.returned;
    final due = loan.dueAt;
    if (due == null) return LoanUrgency.noDate;

    final today = _day(now ?? DateTime.now());
    final dueDay = _day(due);
    final days = dueDay.difference(today).inDays;
    if (days < 0) return LoanUrgency.overdue;
    if (days == 0) return LoanUrgency.dueToday;
    if (days <= soonWithinDays) return LoanUrgency.dueSoon;
    return LoanUrgency.dueLater;
  }

  /// Whole days overdue, or 0 when it isn't.
  static int daysOverdue(Loan loan, {DateTime? now}) {
    final due = loan.dueAt;
    if (due == null || loan.returnedAt != null) return 0;
    final days = _day(now ?? DateTime.now()).difference(_day(due)).inDays;
    return days > 0 ? days : 0;
  }

  /// Active loans, most urgent first: overdue (longest first), then by due date,
  /// then the undated ones — which sort last because nothing is expected of them.
  static List<Loan> sortByUrgency(List<Loan> loans, {DateTime? now}) {
    final at = now ?? DateTime.now();
    final sorted = [...loans];
    sorted.sort((a, b) {
      final ad = a.dueAt;
      final bd = b.dueAt;
      if ((ad == null) != (bd == null)) return ad == null ? 1 : -1;
      if (ad == null || bd == null) {
        return a.borrower.toLowerCase().compareTo(b.borrower.toLowerCase());
      }
      final byDue = ad.compareTo(bd);
      return byDue != 0 ? byDue : a.borrower.toLowerCase().compareTo(b.borrower.toLowerCase());
    });
    // `at` is unused in the comparison itself, but taking it keeps the API
    // honest for callers that expect "as of" semantics and lets tests pin them.
    assert(at.isAfter(DateTime(1970)));
    return sorted;
  }

  /// Loans that should raise a reminder now: due today or overdue, active, and
  /// not already reminded since their due date passed.
  ///
  /// Returning the list rather than scheduling anything keeps the decision pure
  /// and testable — the caller owns *how* it tells the user.
  static List<Loan> needingReminder(List<Loan> loans, {DateTime? now}) {
    final at = now ?? DateTime.now();
    return [
      for (final loan in loans)
        if (loan.returnedAt == null &&
            urgencyOf(loan, now: at).needsAttention &&
            !_alreadyReminded(loan, at))
          loan,
    ];
  }

  /// A reminder counts as already given if it was sent today or later — so a
  /// reminder sent last week for a book that is *still* overdue comes back.
  static bool _alreadyReminded(Loan loan, DateTime now) {
    final sent = loan.reminderSentAt;
    if (sent == null) return false;
    return !_day(sent).isBefore(_day(now));
  }

  /// A human phrase for the badge: "3 days overdue", "due today", "due in 2 days".
  static String describe(Loan loan, {DateTime? now}) {
    final at = now ?? DateTime.now();
    switch (urgencyOf(loan, now: at)) {
      case LoanUrgency.returned:
        return 'Returned';
      case LoanUrgency.noDate:
        return 'No due date';
      case LoanUrgency.overdue:
        final days = daysOverdue(loan, now: at);
        return days == 1 ? '1 day overdue' : '$days days overdue';
      case LoanUrgency.dueToday:
        return 'Due today';
      case LoanUrgency.dueSoon:
      case LoanUrgency.dueLater:
        final days = _day(loan.dueAt!).difference(_day(at)).inDays;
        return days == 1 ? 'Due tomorrow' : 'Due in $days days';
    }
  }

  /// A message to send the borrower — the "nudge" action.
  static String reminderMessage(Loan loan, String bookTitle, {DateTime? now}) {
    final lent = _dateOnly(loan.loanedAt);
    final due = loan.dueAt;
    if (due == null) {
      return 'You borrowed "$bookTitle" on $lent. Could I have it back when '
          "you're done?";
    }
    return 'You borrowed "$bookTitle" on $lent, due ${_dateOnly(due)}.';
  }

  /// Local calendar day, so comparisons are about days rather than instants.
  static DateTime _day(DateTime moment) {
    final local = moment.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  static String _dateOnly(DateTime moment) {
    final local = moment.toLocal();
    return '${local.year}-${local.month.toString().padLeft(2, '0')}-'
        '${local.day.toString().padLeft(2, '0')}';
  }
}

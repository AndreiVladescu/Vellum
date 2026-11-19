import '../data/database.dart';
import '../data/reading_status.dart';

/// "Continue listening" (docs/AUDIOBOOKS.md section 4): the pure rules, shared
/// by the shelf's strip and the Android home widget so the two cannot disagree
/// about what you are in the middle of.

/// How near the end counts as done. Without it a book left a few seconds from
/// the end, where the last chapter's silence is, would sit in the strip for
/// ever.
const finishedWithinSeconds = 30;

/// Whether [book] belongs in *Continue listening*: it has been played, is not
/// within [finishedWithinSeconds] of the end, and is not finished or abandoned.
///
/// [audioMs] is the total length of its audio in milliseconds, null when it has
/// no audio (then it cannot be listened to, whatever it remembers), and zero
/// when the parts' durations are not known, in which case the end cannot be
/// judged and the book counts as on the go.
bool isListeningOnTheGo(Book book, int? audioMs) {
  if (audioMs == null) return false;
  if (book.lastListenedAt == null) return false;
  final at = book.listenPosition;
  if (at == null || at < 1) return false;
  final status = ReadingStatus.parse(book.status);
  if (status == ReadingStatus.finished || status == ReadingStatus.abandoned) {
    return false;
  }
  if (audioMs > 0 && at >= audioMs / 1000 - finishedWithinSeconds) {
    return false;
  }
  return true;
}

/// How far through the audio [book] is, 0 to 1, or null when the length is not
/// known.
double? listenFraction(Book book, int? audioMs) {
  final at = book.listenPosition;
  if (at == null || audioMs == null || audioMs <= 0) return null;
  return (at * 1000 / audioMs).clamp(0.0, 1.0);
}

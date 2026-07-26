import 'dart:io';

import 'package:share_plus/share_plus.dart';

/// Hands a file we just generated to the rest of the system (plan 5 #28).
///
/// Two different jobs behind one call, because the platforms disagree about
/// what "open this" means:
///
/// - **Desktop** has a file manager and a default application, so the file is
///   opened with it — a printable sheet lands in the browser, one Ctrl+P from
///   paper.
/// - **Android/iOS** have no such notion, so the file goes to the share sheet,
///   which is where printing, saving and sending all live on a phone anyway.
///
/// Returns false when nothing could be launched (a headless desktop, a missing
/// `xdg-open`), so the caller can say so instead of appearing to do nothing.
Future<bool> openExternally(File file, {String? mimeType}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
    return true;
  }
  final (command, args) = switch (Platform.operatingSystem) {
    'linux' => ('xdg-open', [file.path]),
    'macos' => ('open', [file.path]),
    // The empty string is `start`'s title argument; without it a quoted path
    // is taken *as* the title and nothing opens.
    'windows' => ('cmd', ['/c', 'start', '', file.path]),
    _ => ('', <String>[]),
  };
  if (command.isEmpty) return false;
  try {
    final result = await Process.run(command, args);
    return result.exitCode == 0;
  } on ProcessException {
    return false;
  }
}

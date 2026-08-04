import 'dart:io';

import 'package:open_filex/open_filex.dart';
import 'package:share_plus/share_plus.dart';

/// Hands a file to the rest of the system (plan 5 #28).
///
/// "Open" means the same thing everywhere: give it to whatever application
/// handles this kind of file. Android used to be sent to the share sheet
/// instead, on the theory that a phone has no default-application notion —
/// which is wrong. `ACTION_VIEW` on a `content://` URI is exactly that notion,
/// and it is why a phone offers a reader when you tap a PDF in Files. The share
/// sheet answers a different question ("send this to someone"), so *Open in
/// another app* landing there was an answer to a question nobody asked.
///
/// Returns false when nothing could be launched — a headless desktop with no
/// `xdg-open`, or a phone with nothing installed that opens EPUBs — so the
/// caller can say so instead of appearing to do nothing.
Future<bool> openExternally(File file, {String? mimeType}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    final result = await OpenFilex.open(file.path, type: mimeType);
    return result.type == ResultType.done;
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

/// For a file the app just *generated* — a shelf label sheet, a template
/// spreadsheet — where the next step is usually printing it or sending it
/// somewhere.
///
/// Opens it on desktop (straight into a viewer, one Ctrl+P from paper) and
/// shares it on a phone, where printing, saving to Drive and sending all live
/// behind the share sheet. This is what [openExternally] used to do for every
/// caller; a *book* is the case that wanted the other thing.
Future<bool> openOrShare(File file, {String? mimeType}) async {
  if (Platform.isAndroid || Platform.isIOS) {
    await SharePlus.instance.share(
      ShareParams(files: [XFile(file.path, mimeType: mimeType)]),
    );
    return true;
  }
  return openExternally(file, mimeType: mimeType);
}

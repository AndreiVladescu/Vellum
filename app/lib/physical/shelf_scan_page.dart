import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../add_book/barcode_camera.dart';
import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import 'locate.dart';
import 'physical_libraries_page.dart';

/// Scanning a printed shelf label (plan 5 #28): point the phone at the QR code
/// on a shelf edge and Vellum opens that shelf's room.
///
/// **Why a scanner and not an OS deep link.** The labels carry
/// `vellum://shelf/<id>`, which a registered URL scheme could open from the
/// system camera — at the cost of manifest work on four platforms and a hole
/// that any web page could poke. Vellum already has a camera page for ISBNs
/// (#16), and you were going to open the app anyway: the point of scanning a
/// shelf is to look at the room.
///
/// It degrades like the ISBN scanner does: no camera (desktop) leaves the paste
/// field driving exactly the same code path.
class ShelfScanPage extends StatefulWidget {
  const ShelfScanPage({
    super.key,
    required this.repository,
    required this.settings,
    this.codes,
    this.cameraAvailable,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Code source. Null means the device camera; a stream can be supplied
  /// instead, which is how this is tested without one.
  final Stream<String>? codes;

  /// Whether to show the camera at all. Defaults to true on Android/iOS.
  final bool? cameraAvailable;

  @override
  State<ShelfScanPage> createState() => _ShelfScanPageState();
}

class _ShelfScanPageState extends State<ShelfScanPage> {
  final _manual = TextEditingController();
  StreamSubscription<String>? _subscription;
  String? _message;

  /// Set as soon as a code is accepted, so the twenty further frames the camera
  /// decodes while the route is pushing don't open twenty rooms.
  bool _handled = false;

  bool get _useCamera =>
      widget.cameraAvailable ??
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

  @override
  void initState() {
    super.initState();
    _subscription = widget.codes?.listen(_onCode);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    _manual.dispose();
    super.dispose();
  }

  Future<void> _onCode(String raw) async {
    if (_handled) return;
    final shelfId = parseShelfLink(raw);
    if (shelfId == null) {
      // Not a shelf label. Said once, not per frame — a camera pointed at a
      // book's barcode would otherwise strobe the message.
      if (mounted && _message == null) {
        setState(() => _message = "That isn't a Vellum shelf label.");
      }
      return;
    }
    _handled = true;
    final environment =
        await widget.repository.layout.environmentOfShelf(shelfId);
    if (!mounted) return;
    if (environment == null) {
      setState(() {
        _handled = false;
        _message = 'That shelf no longer exists — the label outlived it.';
      });
      return;
    }
    Navigator.of(context).pop();
    openEnvironment(
      context,
      widget.repository,
      widget.settings,
      environment.id,
      environment.name,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Scan a shelf label')),
      body: Column(
        children: [
          if (_useCamera)
            Expanded(
              child: BarcodeCamera(
                formats: shelfLabelFormats,
                onCode: _onCode,
                onError: (message) => Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(message, textAlign: TextAlign.center),
                  ),
                ),
              ),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _manual,
                  decoration: InputDecoration(
                    labelText: 'Shelf link',
                    hintText: 'vellum://shelf/…',
                    helperText: _useCamera
                        ? 'Or type the link, if the code won’t scan'
                        : 'Type or paste the link printed under a label',
                  ),
                  onSubmitted: _onCode,
                ),
                if (_message != null) ...[
                  const SizedBox(height: 8),
                  Text(_message!, style: TextStyle(color: theme.colorScheme.error)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

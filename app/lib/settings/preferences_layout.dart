import 'package:flutter/material.dart';

import '../l10n/gen/app_localizations.dart';
import '../widgets/adaptive.dart';

/// One setting (or one tight group of settings) on the Preferences page.
///
/// The page used to be a single long list. It is now described as data — a
/// list of sections, each a list of these — so the same entries can be shown
/// as a sections list, as one section's page, or as a search result, without
/// the page knowing which.
class PrefsEntry {
  const PrefsEntry({
    required this.id,
    required this.title,
    this.subtitle,
    this.keywords = const [],
    this.heading,
    required this.builder,
  });

  /// Stable name, for deep links (`PreferencesPage.initialEntry`) and tests.
  final String id;

  /// What a search result is called.
  final String title;
  final String? subtitle;

  /// Extra words that find this entry although they are not in [title].
  final List<String> keywords;

  /// A small heading drawn above the entry inside its section, if any.
  final String? heading;

  final WidgetBuilder builder;

  bool matches(List<String> terms) {
    final hay = [title, subtitle ?? '', ...keywords].join(' ').toLowerCase();
    return terms.every(hay.contains);
  }
}

class PrefsSection {
  const PrefsSection({
    required this.id,
    required this.title,
    required this.icon,
    required this.entries,
  });

  final String id;
  final String title;
  final IconData icon;
  final List<PrefsEntry> entries;
}

/// Builds the sections from the current state. Called again whenever
/// [PrefsLayout.listenable] fires, so a setting that appears or disappears
/// (face-out hides the spine art control) is picked up.
typedef PrefsSectionsBuilder = List<PrefsSection> Function(BuildContext);

/// The sections of Preferences, with a search box.
///
/// Narrow: a list of sections, each opening its own page. Wide (the 840 px
/// "expanded" size): the list on the left, the chosen section on the right.
/// Either way the search box is on top; typing replaces the sections list with
/// matches, each labelled with its section, and tapping one opens that section
/// scrolled to the setting and briefly tinted.
class PrefsLayout extends StatefulWidget {
  const PrefsLayout({
    super.key,
    required this.listenable,
    required this.sections,
    this.initialSection,
    this.initialEntry,
  });

  final Listenable listenable;
  final PrefsSectionsBuilder sections;

  /// Open this section straight away (a deep link).
  final String? initialSection;

  /// …and scroll to / highlight this entry in it.
  final String? initialEntry;

  @override
  State<PrefsLayout> createState() => _PrefsLayoutState();
}

class _PrefsLayoutState extends State<PrefsLayout> {
  final _query = TextEditingController();
  String? _selected;
  String? _focusEntry;
  int _focusToken = 0;

  @override
  void initState() {
    super.initState();
    _selected = widget.initialSection;
    _focusEntry = widget.initialEntry;
    if (_focusEntry != null) _focusToken++;
    _query.addListener(() => setState(() {}));
    if (widget.initialSection != null) {
      // On a phone a deep link means the section's page, with the list behind
      // it to go back to. Wide layouts show it in the right-hand pane.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_isWide(context)) {
          _openPage(widget.initialSection!, _focusEntry);
        }
      });
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  static bool _isWide(BuildContext context) =>
      MediaQuery.sizeOf(context).width >= WindowSize.expandedFrom;

  void _openPage(String sectionId, String? entryId) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => _SectionPage(
        listenable: widget.listenable,
        sections: widget.sections,
        sectionId: sectionId,
        focusEntry: entryId,
      ),
    ));
  }

  void _open(String sectionId, {String? entryId}) {
    if (_isWide(context)) {
      setState(() {
        _selected = sectionId;
        _focusEntry = entryId;
        if (entryId != null) _focusToken++;
        _query.clear();
      });
    } else {
      _openPage(sectionId, entryId);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.listenable,
      builder: (context, _) {
        final sections = widget.sections(context);
        final wide = _isWide(context);
        final selected = sections.firstWhere(
          (s) => s.id == _selected,
          orElse: () => sections.first,
        );
        final searching = _query.text.trim().isNotEmpty;

        final searchBox = _SearchBox(controller: _query);
        final list = searching
            ? _Results(
                sections: sections,
                query: _query.text,
                onOpen: (s, e) => _open(s.id, entryId: e.id),
              )
            : _SectionList(
                sections: sections,
                selectedId: wide ? selected.id : null,
                onOpen: (s) => _open(s.id),
              );

        if (!wide) {
          return Column(
            children: [
              Padding(
                padding: readableInsets(
                    context, const EdgeInsets.fromLTRB(16, 8, 16, 0)),
                child: searchBox,
              ),
              Expanded(child: list),
            ],
          );
        }
        return Row(
          children: [
            SizedBox(
              width: 320,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: searchBox,
                  ),
                  Expanded(child: list),
                ],
              ),
            ),
            const VerticalDivider(width: 1),
            Expanded(
              child: _SectionView(
                // A new key per section so the scroll position starts at the
                // top rather than carrying over from the last one.
                key: ValueKey(selected.id),
                section: selected,
                focusEntry: _focusEntry,
                focusToken: _focusToken,
                padding: readableInsets(
                    context, const EdgeInsets.symmetric(vertical: 8),
                    maxWidth: 640),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _SearchBox extends StatelessWidget {
  const _SearchBox({required this.controller});

  final TextEditingController controller;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return TextField(
      controller: controller,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        prefixIcon: const Icon(Icons.search),
        hintText: l10n.prefsSearchHint,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(28)),
        ),
        isDense: true,
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: l10n.prefsSearchClear,
                icon: const Icon(Icons.close),
                onPressed: controller.clear,
              ),
      ),
    );
  }
}

class _SectionList extends StatelessWidget {
  const _SectionList({
    required this.sections,
    required this.selectedId,
    required this.onOpen,
  });

  final List<PrefsSection> sections;

  /// Highlighted row on a wide layout; null on a phone.
  final String? selectedId;
  final ValueChanged<PrefsSection> onOpen;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: selectedId == null
          ? readableInsets(context, const EdgeInsets.symmetric(vertical: 8))
          : const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final section in sections)
          ListTile(
            key: ValueKey('prefs-section-${section.id}'),
            leading: Icon(section.icon),
            title: Text(section.title),
            subtitle: Text(
              section.entries.map((e) => e.title).join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: selectedId == null ? const Icon(Icons.chevron_right) : null,
            selected: section.id == selectedId,
            onTap: () => onOpen(section),
          ),
      ],
    );
  }
}

class _Results extends StatelessWidget {
  const _Results({
    required this.sections,
    required this.query,
    required this.onOpen,
  });

  final List<PrefsSection> sections;
  final String query;
  final void Function(PrefsSection, PrefsEntry) onOpen;

  @override
  Widget build(BuildContext context) {
    final terms = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    final hits = [
      for (final s in sections)
        for (final e in s.entries)
          if (e.matches(terms)) (s, e),
    ];
    if (hits.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(L10n.of(context).prefsSearchNone(query.trim())),
        ),
      );
    }
    return ListView(
      padding: EdgeInsets.symmetric(vertical: 8) +
          (MediaQuery.sizeOf(context).width >= WindowSize.expandedFrom
              ? EdgeInsets.zero
              : readableInsets(context, EdgeInsets.zero)),
      children: [
        for (final (section, entry) in hits)
          ListTile(
            key: ValueKey('prefs-result-${entry.id}'),
            leading: Icon(section.icon),
            title: Text(entry.title),
            // The section name is what tells two similar matches apart.
            subtitle: Text(section.title),
            onTap: () => onOpen(section, entry),
          ),
      ],
    );
  }
}

/// One section on its own page (phones).
class _SectionPage extends StatelessWidget {
  const _SectionPage({
    required this.listenable,
    required this.sections,
    required this.sectionId,
    required this.focusEntry,
  });

  final Listenable listenable;
  final PrefsSectionsBuilder sections;
  final String sectionId;
  final String? focusEntry;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: listenable,
      builder: (context, _) {
        final all = sections(context);
        final section = all.firstWhere((s) => s.id == sectionId);
        return Scaffold(
          appBar: AppBar(title: Text(section.title)),
          body: _SectionView(
            section: section,
            focusEntry: focusEntry,
            focusToken: 1,
            padding:
                readableInsets(context, const EdgeInsets.symmetric(vertical: 8)),
          ),
        );
      },
    );
  }
}

/// A section's entries, in a scroll view.
///
/// A `SingleChildScrollView` rather than a lazy `ListView` on purpose: a
/// section is a dozen rows at most, and "scroll to the setting a search
/// result named" needs that row to exist even when it is below the fold.
class _SectionView extends StatelessWidget {
  const _SectionView({
    super.key,
    required this.section,
    required this.focusEntry,
    required this.focusToken,
    required this.padding,
  });

  final PrefsSection section;
  final String? focusEntry;
  final int focusToken;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SingleChildScrollView(
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < section.entries.length; i++) ...[
            if (section.entries[i].heading != null) ...[
              if (i > 0) const Divider(height: 24),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Text(
                  section.entries[i].heading!,
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: theme.colorScheme.primary),
                ),
              ),
            ],
            _Flash(
              // The token in the key restarts the flash when the same entry
              // is asked for twice.
              key: ValueKey(
                  '${section.entries[i].id}-${section.entries[i].id == focusEntry ? focusToken : 0}'),
              active: section.entries[i].id == focusEntry,
              child: Builder(builder: section.entries[i].builder),
            ),
          ],
        ],
      ),
    );
  }
}

/// Scrolls its child into view and tints it, fading out, when [active].
///
/// A `TweenAnimationBuilder` rather than a timer: it needs no clean-up and a
/// test settles it with an ordinary `pumpAndSettle`.
class _Flash extends StatefulWidget {
  const _Flash({super.key, required this.active, required this.child});

  final bool active;
  final Widget child;

  @override
  State<_Flash> createState() => _FlashState();
}

class _FlashState extends State<_Flash> {
  @override
  void initState() {
    super.initState();
    if (widget.active) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.2,
          duration: const Duration(milliseconds: 250),
        );
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.active) return widget.child;
    final tint = Theme.of(context).colorScheme.primaryContainer;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 1, end: 0),
      duration: const Duration(milliseconds: 2200),
      curve: const Interval(0.4, 1),
      builder: (context, t, child) => DecoratedBox(
        decoration: BoxDecoration(
          color: tint.withValues(alpha: t),
          borderRadius: BorderRadius.circular(12),
        ),
        // Its own Material, so a tile's ink paints above the tint rather than
        // being hidden under it (and Flutter's ListTile assert stays quiet).
        child: Material(type: MaterialType.transparency, child: child),
      ),
      child: widget.child,
    );
  }
}

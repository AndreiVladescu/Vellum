import 'package:material_ui/material_ui.dart';

import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';
import 'shelf_grouping.dart';

/// Height of a group header. Fixed, because a pinned sliver header needs to
/// know its extent up front.
const groupHeaderExtent = 44.0;

/// The sliver a group's header lives in.
///
/// Not pinned: a pinned `SliverPersistentHeader` inside a `SliverMainAxisGroup`
/// asserts ("layoutExtent exceeds paintExtent") whenever a later group's header
/// is only partly on screen — which is every scroll position. Sticky headers
/// were asked for only "if simple"; this is not, so headers scroll away.
Widget groupHeaderSliver({
  required ShelfGroup group,
  required bool collapsed,
  required VoidCallback onToggle,
}) =>
    SliverToBoxAdapter(
      child: SizedBox(
        height: groupHeaderExtent,
        child: GroupHeader(
          group: group,
          collapsed: collapsed,
          onToggle: onToggle,
        ),
      ),
    );

/// "Name  ·  12" with a chevron; tapping folds the group away.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.group,
    required this.collapsed,
    required this.onToggle,
  });

  final ShelfGroup group;
  final bool collapsed;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final name = group.name ?? group.by.missingLabelOf(l10n);
    final count = group.entries.length;
    return Semantics(
      header: true,
      button: true,
      label: l10n.groupHeaderLabel(name, count),
      excludeSemantics: true,
      onTap: onToggle,
      child: Material(
        // Opaque enough that rows scrolling under the pinned header do not
        // show through its text.
        color: theme.colorScheme.surface.withValues(alpha: 0.94),
        child: InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(
                  collapsed ? Icons.chevron_right : Icons.expand_more,
                  size: 20,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  '$count', // i18n-ignore
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

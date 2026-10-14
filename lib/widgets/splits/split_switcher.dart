import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/split.dart' as gym;
import '../../providers/split_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'split_dialogs.dart';
import 'preset_browser_dialog.dart';

class SplitSwitcher extends StatefulWidget {
  const SplitSwitcher({super.key});

  @override
  State<SplitSwitcher> createState() => _SplitSwitcherState();
}

class _SplitSwitcherState extends State<SplitSwitcher> {
  final MenuController _menuController = MenuController();

  void _closeMenu() => _menuController.close();

  Future<void> _selectSplit(String splitId) async {
    _closeMenu();
    try {
      await context.read<SplitProvider>().setActiveSplit(splitId);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Could not switch splits',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: onColor(errorColor(context)),
            ),
          ),
          backgroundColor: errorColor(context),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SplitProvider>();
    final active = provider.activeSplit;
    final accent = accentColor(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (active == null) return const SizedBox.shrink();

    final availableWidth =
        MediaQuery.sizeOf(context).width - (AppSpacing.lg * 2);
    final menuWidth = math.min(292.0, availableWidth);

    final menu = MenuAnchor(
      controller: _menuController,
      alignmentOffset: const Offset(0, AppSpacing.xs),
      style: const MenuStyle(
        padding: WidgetStatePropertyAll(EdgeInsets.zero),
        backgroundColor: WidgetStatePropertyAll(Colors.transparent),
        elevation: WidgetStatePropertyAll(0),
        shadowColor: WidgetStatePropertyAll(Colors.transparent),
      ),
      onOpen: () => setState(() {}),
      onClose: () => setState(() {}),
      menuChildren: [
        _SplitMenu(
          width: menuWidth,
          provider: provider,
          onCreate: () {
            _closeMenu();
            SplitDialogs.showCreate(context);
          },
          onManage: () {
            _closeMenu();
            SplitDialogs.showManage(context);
          },
          onBrowse: () {
            _closeMenu();
            PresetBrowserDialog.show(context);
          },
          onSelect: _selectSplit,
        ),
      ],
      builder:
          (context, controller, _) => Semantics(
            label: 'Active split ${active.name}',
            hint: 'Opens the split switcher',
            button: true,
            expanded: controller.isOpen,
            child: Tooltip(
              message: 'Switch training split',
              child: InkWell(
                key: const ValueKey('split-switcher-button'),
                onTap:
                    () =>
                        controller.isOpen
                            ? controller.close()
                            : controller.open(),
                borderRadius: AppRadius.control,
                splashColor: accent.withAlpha(36),
                highlightColor: accent.withAlpha(18),
                // Keep the tap area roomy around a more compact visible button.
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: Center(
                    widthFactor: 1,
                    heightFactor: 1,
                    child: Container(
                      key: const ValueKey('split-switcher-content'),
                      constraints: const BoxConstraints(minHeight: 36),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: raisedSurfaceColor(context),
                        border: Border.all(color: borderColor(context)),
                        borderRadius: AppRadius.control,
                      ),
                      // No alignment: it would stretch the box across all the
                      // width the header gives it instead of fitting the name.
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Flexible(
                            child: AnimatedSwitcher(
                              duration:
                                  disableAnimations
                                      ? Duration.zero
                                      : const Duration(milliseconds: 150),
                              transitionBuilder:
                                  (child, animation) => FadeTransition(
                                    opacity: animation,
                                    child: ScaleTransition(
                                      scale: Tween<double>(
                                        begin: 0.98,
                                        end: 1,
                                      ).animate(animation),
                                      child: child,
                                    ),
                                  ),
                              child: _SplitName(
                                active.name,
                                key: ValueKey(active.id),
                                style: Theme.of(
                                  context,
                                ).textTheme.titleSmall?.copyWith(
                                  color: textPrimaryColor(context),
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: AppSpacing.xs),
                          AnimatedRotation(
                            turns: controller.isOpen ? 0.5 : 0,
                            duration:
                                disableAnimations
                                    ? Duration.zero
                                    : const Duration(milliseconds: 150),
                            child: Icon(
                              LucideIcons.chevronDown,
                              size: 16,
                              color: accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
    );

    // The menu lives in an overlay, not a route, so the Navigator never sees
    // it. Without this, Android Back pops the shell and closes the app.
    return PopScope(
      canPop: !_menuController.isOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _closeMenu();
      },
      child: menu,
    );
  }
}

/// Splits a trailing copy counter such as " (2)" off a split name, so the
/// counter can stay visible while the base name is shortened.
@visibleForTesting
(String base, String suffix) splitNameParts(String name) {
  final match = RegExp(r'\s*\(\d+\)$').firstMatch(name);
  if (match == null || match.start == 0) return (name, '');
  return (name.substring(0, match.start), name.substring(match.start));
}

/// A one-line split name that cuts off the base name, never the "(n)" that
/// tells two copies of the same program apart.
class _SplitName extends StatelessWidget {
  final String name;
  final TextStyle? style;

  const _SplitName(this.name, {this.style, super.key});

  @override
  Widget build(BuildContext context) {
    final (base, suffix) = splitNameParts(name);
    if (suffix.isEmpty) {
      return Text(
        name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    return Semantics(
      label: name,
      excludeSemantics: true,
      child: _SuffixFirstRow(
        children: [
          Text(
            base,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
          Text(
            suffix,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.clip,
            style: style,
          ),
        ],
      ),
    );
  }
}

/// Lays out a base and a suffix on one line, sizing the suffix first so only
/// the base gives way. Unlike a `LayoutBuilder` it reports intrinsic sizes,
/// which the menu's `IntrinsicWidth` needs.
class _SuffixFirstRow extends MultiChildRenderObjectWidget {
  const _SuffixFirstRow({required super.children});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSuffixFirstRow();
}

class _SuffixFirstParentData extends ContainerBoxParentData<RenderBox> {}

class _RenderSuffixFirstRow extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SuffixFirstParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SuffixFirstParentData> {
  RenderBox get _base => firstChild!;
  RenderBox get _suffix => lastChild!;

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SuffixFirstParentData) {
      child.parentData = _SuffixFirstParentData();
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) =>
      _suffix.getMaxIntrinsicWidth(height);

  @override
  double computeMaxIntrinsicWidth(double height) =>
      _base.getMaxIntrinsicWidth(height) + _suffix.getMaxIntrinsicWidth(height);

  @override
  double computeMinIntrinsicHeight(double width) => math.max(
    _base.getMinIntrinsicHeight(width),
    _suffix.getMinIntrinsicHeight(width),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => math.max(
    _base.getMaxIntrinsicHeight(width),
    _suffix.getMaxIntrinsicHeight(width),
  );

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToHighestActualBaseline(baseline);

  BoxConstraints _baseConstraints(BoxConstraints constraints, Size suffix) =>
      constraints.loosen().copyWith(
        maxWidth: math.max(0.0, constraints.maxWidth - suffix.width),
      );

  @override
  Size computeDryLayout(covariant BoxConstraints constraints) {
    final suffix = _suffix.getDryLayout(constraints.loosen());
    final base = _base.getDryLayout(_baseConstraints(constraints, suffix));
    return constraints.constrain(
      Size(base.width + suffix.width, math.max(base.height, suffix.height)),
    );
  }

  @override
  void performLayout() {
    _suffix.layout(constraints.loosen(), parentUsesSize: true);
    _base.layout(
      _baseConstraints(constraints, _suffix.size),
      parentUsesSize: true,
    );
    final height = math.max(_base.size.height, _suffix.size.height);
    size = constraints.constrain(
      Size(_base.size.width + _suffix.size.width, height),
    );
    (_base.parentData! as _SuffixFirstParentData).offset = Offset(
      0,
      (height - _base.size.height) / 2,
    );
    (_suffix.parentData! as _SuffixFirstParentData).offset = Offset(
      _base.size.width,
      (height - _suffix.size.height) / 2,
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _SplitMenu extends StatelessWidget {
  final double width;
  final SplitProvider provider;
  final VoidCallback onCreate;
  final VoidCallback onManage;
  final VoidCallback onBrowse;
  final ValueChanged<String> onSelect;

  const _SplitMenu({
    required this.width,
    required this.provider,
    required this.onCreate,
    required this.onManage,
    required this.onBrowse,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    return Material(
      color: surfaceColor(context),
      elevation: 8,
      shadowColor: backgroundColor(context).withAlpha(128),
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.card,
        side: BorderSide(color: border),
      ),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
        key: const ValueKey('split-menu'),
        width: width,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A quiet overline: the header labels the list below it, it is
              // not itself something to tap.
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Your splits',
                        style: Theme.of(context).textTheme.labelMedium
                            ?.copyWith(color: textSecondary),
                      ),
                    ),
                    Text(
                      '${provider.splits.length} of ${SplitProvider.maxSplits}',
                      style: Theme.of(
                        context,
                      ).textTheme.labelMedium?.copyWith(color: textSecondary),
                    ),
                  ],
                ),
              ),
              for (final split in provider.splits)
                _SplitMenuRow(
                  split: split,
                  selected: split.id == provider.activeSplitId,
                  onTap: () => onSelect(split.id),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Divider(height: 1, thickness: 1, color: border),
              ),
              _SplitMenuAction(
                key: const ValueKey('new-split-action'),
                icon: LucideIcons.plus,
                label: 'New split',
                caption: provider.canCreate ? null : 'Limit reached',
                enabled: provider.canCreate,
                onTap: onCreate,
              ),
              _SplitMenuAction(
                key: const ValueKey('browse-programs-action'),
                icon: LucideIcons.libraryBig,
                label: 'Browse',
                semanticLabel: 'Browse programs',
                onTap: onBrowse,
              ),
              _SplitMenuAction(
                key: const ValueKey('manage-splits-action'),
                icon: LucideIcons.settings2,
                label: 'Manage splits',
                onTap: onManage,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitMenuRow extends StatelessWidget {
  final gym.Split split;
  final bool selected;
  final VoidCallback onTap;

  const _SplitMenuRow({
    required this.split,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Semantics(
      label: '${split.name} split',
      button: true,
      selected: selected,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.control,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
          decoration: BoxDecoration(
            color: selected ? accentMutedColor(context) : Colors.transparent,
            borderRadius: AppRadius.control,
          ),
          // Radio-style leading mark: the splits read as "pick one of these",
          // unlike the icon-led actions under the rule.
          child: Row(
            children: [
              Icon(
                selected ? LucideIcons.circleCheck : LucideIcons.circle,
                size: 18,
                color: selected ? accent : textSecondaryColor(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: _SplitName(
                  split.name,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: textPrimaryColor(context),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A command row under the split list: accent icon plus a one-line label, so
/// it reads as "do something" rather than as another split to pick.
class _SplitMenuAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final String? semanticLabel;
  final String? caption;
  final bool enabled;
  final VoidCallback onTap;

  const _SplitMenuAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.semanticLabel,
    this.caption,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final secondary = textSecondaryColor(context);
    final foreground =
        enabled ? textPrimaryColor(context) : secondary.withAlpha(120);
    final iconColor =
        enabled ? accentColor(context) : secondary.withAlpha(120);
    return Semantics(
      button: true,
      enabled: enabled,
      label: caption == null
          ? (semanticLabel ?? label)
          : '${semanticLabel ?? label}, $caption',
      excludeSemantics: true,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 44),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ),
                if (caption != null) ...[
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    caption!,
                    maxLines: 1,
                    style: Theme.of(
                      context,
                    ).textTheme.bodySmall?.copyWith(color: secondary),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

import 'dart:math' as math;

import 'package:flutter/material.dart';
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

    return MenuAnchor(
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
                    heightFactor: 1,
                    child: Container(
                      key: const ValueKey('split-switcher-content'),
                      constraints: const BoxConstraints(
                        minHeight: 36,
                        maxWidth: 180,
                      ),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                        vertical: AppSpacing.xs,
                      ),
                      decoration: BoxDecoration(
                        color: raisedSurfaceColor(context),
                        border: Border.all(color: borderColor(context)),
                        borderRadius: AppRadius.control,
                      ),
                      alignment: Alignment.center,
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
                              child: Text(
                                active.name,
                                key: ValueKey(active.id),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
  }
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
                child: Text(
                  split.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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

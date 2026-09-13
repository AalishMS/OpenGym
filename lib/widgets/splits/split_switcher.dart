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
                child: Container(
                  key: const ValueKey('split-switcher-content'),
                  constraints: const BoxConstraints(
                    minHeight: 48,
                    maxWidth: 180,
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
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
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.sm,
                  AppSpacing.xs,
                  AppSpacing.sm,
                  AppSpacing.sm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Training split',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: accentColor(context),
                        ),
                      ),
                    ),
                    Text(
                      '${provider.splits.length} of ${SplitProvider.maxSplits}',
                      style: Theme.of(
                        context,
                      ).textTheme.bodySmall?.copyWith(color: textSecondary),
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
                label: 'New split',
                caption:
                    provider.canCreate
                        ? 'Empty workspace'
                        : 'Limit reached · 5 of 5 active',
                enabled: provider.canCreate,
                onTap: onCreate,
              ),
              _SplitMenuAction(
                key: const ValueKey('browse-programs-action'),
                label: 'Browse programs',
                caption: 'Choose a split',
                onTap: onBrowse,
              ),
              _SplitMenuAction(
                key: const ValueKey('manage-splits-action'),
                label: 'Manage splits',
                caption: 'Rename or delete',
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
          child: Row(
            children: [
              Container(
                width: 3,
                height: 24,
                decoration: BoxDecoration(
                  color: selected ? accent : borderColor(context),
                  borderRadius: AppRadius.micro,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  split.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color:
                        selected
                            ? textPrimaryColor(context)
                            : textSecondaryColor(context),
                  ),
                ),
              ),
              if (selected) Icon(LucideIcons.check, size: 18, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplitMenuAction extends StatelessWidget {
  final String label;
  final String caption;
  final bool enabled;
  final VoidCallback onTap;

  const _SplitMenuAction({
    super.key,
    required this.label,
    required this.caption,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final foreground =
        enabled
            ? textPrimaryColor(context)
            : textSecondaryColor(context).withAlpha(120);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: AppRadius.control,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(
                      context,
                    ).textTheme.labelLarge?.copyWith(color: foreground),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    caption,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      height: 1.3,
                      color: textSecondaryColor(
                        context,
                      ).withAlpha(enabled ? 220 : 120),
                    ),
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../models/split.dart' as gym;
import '../../providers/split_provider.dart';
import '../../theme/app_theme.dart';
import '../../theme/radii.dart';
import '../../theme/spacing.dart';
import 'split_dialogs.dart';

class SplitSwitcher extends StatefulWidget {
  const SplitSwitcher({super.key});

  @override
  State<SplitSwitcher> createState() => _SplitSwitcherState();
}

class _SplitSwitcherState extends State<SplitSwitcher> {
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _menuEntry;

  bool get _isOpen => _menuEntry != null;

  @override
  void dispose() {
    _removeMenu();
    super.dispose();
  }

  void _toggleMenu() => _isOpen ? _closeMenu() : _openMenu();

  void _openMenu() {
    final overlay = Overlay.of(context);
    final availableWidth =
        MediaQuery.sizeOf(context).width - (AppSpacing.lg * 2);
    final menuWidth = math.min(292.0, availableWidth);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    _menuEntry = OverlayEntry(
      builder:
          (overlayContext) => _SplitMenuOverlay(
            layerLink: _layerLink,
            width: menuWidth,
            disableAnimations: disableAnimations,
            onDismiss: _closeMenu,
            onCreate: () {
              _closeMenu();
              SplitDialogs.showCreate(context);
            },
            onManage: () {
              _closeMenu();
              SplitDialogs.showManage(context);
            },
            onSelect: (splitId) async {
              _closeMenu();
              try {
                await context.read<SplitProvider>().setActiveSplit(splitId);
              } catch (_) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      '> Could not switch splits',
                      style: GoogleFonts.jetBrainsMono(
                        color: onColor(errorColor(context)),
                      ),
                    ),
                    backgroundColor: errorColor(context),
                  ),
                );
              }
            },
          ),
    );
    overlay.insert(_menuEntry!);
    setState(() {});
  }

  void _closeMenu() {
    _removeMenu();
    if (mounted) setState(() {});
  }

  void _removeMenu() {
    _menuEntry?.remove();
    _menuEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SplitProvider>();
    final active = provider.activeSplit;
    final accent = accentColor(context);
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    if (active == null) return const SizedBox.shrink();

    return CompositedTransformTarget(
      link: _layerLink,
      child: Semantics(
        label: 'Active split ${active.name}',
        hint: 'Opens the split switcher',
        button: true,
        expanded: _isOpen,
        child: Tooltip(
          message: 'Switch training split',
          child: InkWell(
            key: const ValueKey('split-switcher-button'),
            onTap: _toggleMenu,
            borderRadius: AppRadius.control,
            splashColor: accent.withAlpha(36),
            highlightColor: accent.withAlpha(18),
            child: Container(
              constraints: const BoxConstraints(minHeight: 48, maxWidth: 220),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              alignment: Alignment.center,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: surfaceColor(context).withAlpha(204),
                  border: Border.all(color: accent.withAlpha(160)),
                  borderRadius: AppRadius.control,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
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
                          '[${active.name.toUpperCase()}]',
                          key: ValueKey(active.id),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: accent,
                            letterSpacing: 0.04,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    AnimatedRotation(
                      turns: _isOpen ? 0.5 : 0,
                      duration:
                          disableAnimations
                              ? Duration.zero
                              : const Duration(milliseconds: 150),
                      child: Icon(
                        LucideIcons.chevronDown,
                        size: 14,
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
    );
  }
}

class _SplitMenuOverlay extends StatelessWidget {
  final LayerLink layerLink;
  final double width;
  final bool disableAnimations;
  final VoidCallback onDismiss;
  final VoidCallback onCreate;
  final VoidCallback onManage;
  final ValueChanged<String> onSelect;

  const _SplitMenuOverlay({
    required this.layerLink,
    required this.width,
    required this.disableAnimations,
    required this.onDismiss,
    required this.onCreate,
    required this.onManage,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            key: const ValueKey('split-menu-barrier'),
            behavior: HitTestBehavior.translucent,
            onTap: onDismiss,
          ),
        ),
        CompositedTransformFollower(
          link: layerLink,
          showWhenUnlinked: false,
          targetAnchor: Alignment.bottomRight,
          followerAnchor: Alignment.topRight,
          offset: const Offset(0, AppSpacing.xs),
          child: _AnimatedSplitMenu(
            width: width,
            disableAnimations: disableAnimations,
            onDismiss: onDismiss,
            onCreate: onCreate,
            onManage: onManage,
            onSelect: onSelect,
          ),
        ),
      ],
    );
  }
}

class _AnimatedSplitMenu extends StatefulWidget {
  final double width;
  final bool disableAnimations;
  final VoidCallback onDismiss;
  final VoidCallback onCreate;
  final VoidCallback onManage;
  final ValueChanged<String> onSelect;

  const _AnimatedSplitMenu({
    required this.width,
    required this.disableAnimations,
    required this.onDismiss,
    required this.onCreate,
    required this.onManage,
    required this.onSelect,
  });

  @override
  State<_AnimatedSplitMenu> createState() => _AnimatedSplitMenuState();
}

class _AnimatedSplitMenuState extends State<_AnimatedSplitMenu>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration:
        widget.disableAnimations
            ? Duration.zero
            : const Duration(milliseconds: 150),
  )..forward();
  late final Animation<double> _curve = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeOutCubic,
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): widget.onDismiss,
      },
      child: Focus(
        autofocus: true,
        child: FadeTransition(
          opacity: _curve,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(_curve),
            alignment: Alignment.topRight,
            child: Consumer<SplitProvider>(
              builder:
                  (context, provider, _) => _SplitMenu(
                    width: widget.width,
                    provider: provider,
                    onCreate: widget.onCreate,
                    onManage: widget.onManage,
                    onSelect: widget.onSelect,
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
  final ValueChanged<String> onSelect;

  const _SplitMenu({
    required this.width,
    required this.provider,
    required this.onCreate,
    required this.onManage,
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
                        '> TRAINING SPLIT',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: accentColor(context),
                          letterSpacing: 0.08,
                        ),
                      ),
                    ),
                    Text(
                      '${provider.splits.length}/${SplitProvider.maxSplits}',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 9,
                        color: textSecondary,
                      ),
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
                label: '[+ NEW SPLIT]',
                caption:
                    provider.canCreate
                        ? 'EMPTY WORKSPACE'
                        : 'LIMIT REACHED · 5/5 ACTIVE',
                enabled: provider.canCreate,
                onTap: onCreate,
              ),
              _SplitMenuAction(
                key: const ValueKey('manage-splits-action'),
                label: '[MANAGE SPLITS]',
                caption: 'RENAME OR DELETE',
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
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                    color:
                        selected
                            ? textPrimaryColor(context)
                            : textSecondaryColor(context),
                  ),
                ),
              ),
              if (selected)
                Text(
                  '[ACTIVE]',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 9,
                    color: accent,
                    letterSpacing: 0.06,
                  ),
                ),
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
      label: label.replaceAll(RegExp(r'[\[\]+]'), '').trim(),
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
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: foreground,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Flexible(
                  child: Text(
                    caption,
                    textAlign: TextAlign.right,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
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

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/app_theme.dart';
import '../theme/spacing.dart';

/// Which edge of the strip carries its hairline rule. A strip under an app bar
/// rules its bottom edge; one sitting above the screen's bottom rules its top.
enum StripRule { top, bottom }

/// One tab's content. The strip owns the selection mark, so a tab only says
/// what it is and what to do when tapped.
class UnderlineTabData {
  /// Zero-padded ordinal shown ahead of the label, for a set whose labels carry
  /// no order of their own (plan names). Omit it when the label is already
  /// ordinal — `WEEK 7` does not need an `07` in front of it.
  final String? index;

  final String label;

  /// Null for the tab you are already on — no splash, nothing to do.
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  const UnderlineTabData({
    required this.label,
    this.index,
    this.onTap,
    this.onLongPress,
  });
}

/// A horizontally-scrolling strip of tabs marked by a 2px underline.
///
/// The workout screen shows two of these — plans under the app bar, weeks above
/// the bottom edge — and they used to be the same control in two visual
/// languages: the plan strip an underlined label, the week bar a row of filled
/// slabs. One widget now, so switching plan and switching week look like the
/// same kind of move.
///
/// The strip lays every tab out eagerly rather than lazily. Tabs are short
/// labels, a couple of dozen at most, and laying them out is what lets the
/// selected one be scrolled into view by measurement instead of by a guessed
/// per-item width — the week bar used to assume 68px per chip, which was already
/// wrong at `WEEK 10` and drifted further with every week added.
class UnderlineTabStrip extends StatefulWidget {
  final List<UnderlineTabData> tabs;

  /// Index into [tabs] of the tab currently selected. The strip scrolls it into
  /// view on first build and whenever it changes.
  final int selectedIndex;

  /// Marks the selected tab — its underline and its label. One colour for the
  /// whole strip: the mark says *which tab*, so varying it per tab would spend
  /// hue on something the position already tells you.
  final Color color;

  /// An action pinned after the last tab and scrolling with it — the week bar's
  /// `[+ WEEK 6]`. Deliberately not styled as a tab: it adds to the set rather
  /// than selecting within it.
  final Widget? trailing;

  final StripRule rule;

  final double height;

  /// Caps a long label before it pushes every other tab off-screen.
  final double maxLabelWidth;

  const UnderlineTabStrip({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.color,
    required this.rule,
    this.trailing,
    this.height = 44,
    this.maxLabelWidth = 160,
  });

  @override
  State<UnderlineTabStrip> createState() => _UnderlineTabStripState();
}

class _UnderlineTabStripState extends State<UnderlineTabStrip> {
  /// Anchors the selected tab so [Scrollable.ensureVisible] can centre it
  /// without knowing how wide it is.
  final GlobalKey _selectedTabKey = GlobalKey();

  final ScrollController _controller = ScrollController();

  /// Whether there are tabs past each end. Only a scrollable edge is faded:
  /// fading an edge with nothing beyond it just dims the outermost label.
  bool _fadeStart = false;
  bool _fadeEnd = false;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealSelected(Duration.zero);
      _syncFades();
    });
  }

  @override
  void didUpdateWidget(UnderlineTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Follow the selection when it moves — a swipe between weeks or a new week
    // can land on a tab that sits off the end of the strip.
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.tabs.length != widget.tabs.length) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _revealSelected(const Duration(milliseconds: 220));
        _syncFades();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _revealSelected(Duration duration) {
    if (!mounted) return;
    final tabContext = _selectedTabKey.currentContext;
    if (tabContext == null) return;
    Scrollable.ensureVisible(
      tabContext,
      alignment: 0.5,
      duration: duration,
      curve: Curves.easeOut,
    );
  }

  void _syncFades() {
    if (!mounted || !_controller.hasClients) return;
    final position = _controller.position;
    // A 1px deadband: a bounce overscrolls slightly past either end, and that
    // should not flick the fades on and off.
    final start = position.pixels > position.minScrollExtent + 1;
    final end = position.pixels < position.maxScrollExtent - 1;
    if (start != _fadeStart || end != _fadeEnd) {
      setState(() {
        _fadeStart = start;
        _fadeEnd = end;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // The mask is unconditional, and the stops do all the work. Wrapping the
    // scroll view only when a fade is needed would swap the widget type at that
    // slot, which discards the scroll view's element — and with it the
    // ScrollPosition, silently resetting the offset to zero the first time a
    // fade appeared. Stops of [0, 0, 1, 1] are simply a fully opaque mask.
    final strip = ShaderMask(
      shaderCallback: (bounds) {
        // A fixed 24px ramp, not a percentage: the point is to soften one
        // label's edge, and that width does not depend on the screen's.
        final ramp = (24 / bounds.width).clamp(0.0, 0.4);
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          // dstIn reads alpha only — these are mask stops, not UI colours, so
          // opaque/transparent is all that black and white mean here.
          colors: const [
            Colors.transparent,
            Colors.black,
            Colors.black,
            Colors.transparent,
          ],
          stops: [
            0.0,
            _fadeStart ? ramp : 0.0,
            _fadeEnd ? 1 - ramp : 1.0,
            1.0,
          ],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: SingleChildScrollView(
        controller: _controller,
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(
            parent: BouncingScrollPhysics()),
        child: Row(
          // Every tap target fills the strip's full height, so a 22px label
          // does not mean a 22px hit box in a 44px bar.
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.tabs.length; i++)
              _UnderlineTab(
                key: i == widget.selectedIndex ? _selectedTabKey : null,
                data: widget.tabs[i],
                selected: i == widget.selectedIndex,
                color: widget.color,
                maxLabelWidth: widget.maxLabelWidth,
              ),
            if (widget.trailing != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
                child: Center(child: widget.trailing!),
              ),
          ],
        ),
      ),
    );

    // A Material, not a plain Container: the tabs' ink needs a surface of its
    // own here, or the splash paints into the Scaffold's Material *behind* the
    // bar's opaque ground and a tap looks like it did nothing.
    return Material(
      color: surfaceColor(context),
      child: Container(
        height: widget.height,
        decoration: BoxDecoration(
          // A single-edge border is a rule, not a box: one unbroken hairline
          // across the full width, and it stays square.
          border: widget.rule == StripRule.bottom
              ? Border(bottom: BorderSide(color: borderColor(context)))
              : Border(top: BorderSide(color: borderColor(context))),
        ),
        child: strip,
      ),
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  final UnderlineTabData data;
  final bool selected;
  final Color color;
  final double maxLabelWidth;

  const _UnderlineTab({
    super.key,
    required this.data,
    required this.selected,
    required this.color,
    required this.maxLabelWidth,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);

    return InkWell(
      onTap: data.onTap,
      onLongPress: data.onLongPress,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Center(
          // The underline borders the label, not the full-height cell, so it
          // spans exactly the text without any intrinsic-width work.
          child: Container(
            padding: const EdgeInsets.only(bottom: 6),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: selected ? color : Colors.transparent,
                  width: 2,
                ),
              ),
            ),
            child: Row(
              children: [
                if (data.index != null) ...[
                  Text(
                    data.index!,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 9,
                      letterSpacing: 0.08,
                      color: textSecondary,
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: maxLabelWidth),
                  child: Text(
                    data.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 11,
                      letterSpacing: 0.04,
                      fontWeight:
                          selected ? FontWeight.bold : FontWeight.normal,
                      color: selected ? color : textSecondary,
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

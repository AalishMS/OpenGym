import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../theme/motion.dart';
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

  /// Scrolls the strip; it makes its own when this is null. A caller that
  /// owns one can read where the strip stood, and start a strip that takes
  /// its place there (`ScrollController(initialScrollOffset:)`).
  final ScrollController? controller;

  /// The tab that was marked when this strip took the place of another
  /// showing the same tabs, as a workout switched to another plan builds a
  /// new strip where the old one stood. The mark starts under that tab and
  /// slides to [selectedIndex], and the selection is scrolled into view
  /// rather than jumped to, so the strip reads as one whose selection moved.
  /// Read when the strip is first built; null starts it at rest.
  final int? previousIndex;

  const UnderlineTabStrip({
    super.key,
    required this.tabs,
    required this.selectedIndex,
    required this.color,
    required this.rule,
    this.trailing,
    this.height = 48,
    this.controller,
    this.previousIndex,
  });

  @override
  State<UnderlineTabStrip> createState() => _UnderlineTabStripState();
}

class _UnderlineTabStripState extends State<UnderlineTabStrip>
    with SingleTickerProviderStateMixin {
  /// Anchors the selected tab so [Scrollable.ensureVisible] can centre it
  /// without knowing how wide it is.
  final GlobalKey _selectedTabKey = GlobalKey();

  ScrollController? _ownController;
  ScrollController get _controller =>
      widget.controller ?? (_ownController ??= ScrollController());

  /// The tab the mark slides from, until it has arrived under the selection.
  int? _markFrom;

  /// The mark's slide, once both ends have been measured.
  AnimationController? _markSlide;
  Rect _markStart = Rect.zero;
  Rect _markEnd = Rect.zero;

  /// The tabs' row, and the underlines at either end of the mark's slide.
  final GlobalKey _contentKey = GlobalKey();
  final GlobalKey _fromMarkKey = GlobalKey();
  final GlobalKey _toMarkKey = GlobalKey();

  /// Whether there are tabs past each end. Only a scrollable edge is faded:
  /// fading an edge with nothing beyond it just dims the outermost label.
  bool _fadeStart = false;
  bool _fadeEnd = false;

  @override
  void initState() {
    super.initState();
    final from = widget.previousIndex;
    if (from != null &&
        from != widget.selectedIndex &&
        from >= 0 &&
        from < widget.tabs.length) {
      _markFrom = from;
    }
    _controller.addListener(_syncFades);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final continuing = _markFrom != null;
      if (continuing) _slideMark();
      _revealSelected(
        continuing ? AppMotion.of(context, AppMotion.standard) : Duration.zero,
      );
      _syncFades();
    });
  }

  @override
  void didUpdateWidget(UnderlineTabStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      (oldWidget.controller ?? _ownController)?.removeListener(_syncFades);
      _controller.addListener(_syncFades);
    }
    // Switching plans or adding a week can select a tab off the end of the strip.
    if (oldWidget.selectedIndex != widget.selectedIndex ||
        oldWidget.tabs.length != widget.tabs.length) {
      // A mark still sliding lands: the selection it was going to is gone.
      _markSlide?.dispose();
      _markSlide = null;
      _markFrom = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _revealSelected(AppMotion.of(context, AppMotion.standard));
        _syncFades();
      });
    }
  }

  @override
  void dispose() {
    _controller.removeListener(_syncFades);
    _ownController?.dispose();
    _markSlide?.dispose();
    super.dispose();
  }

  /// Slides the mark from the tab marked before to the selection: a mark on
  /// screen travelling to another place on screen, so it moves on
  /// [AppMotion.move]. It lands at once under reduced motion, or when the
  /// strip is covered.
  void _slideMark() {
    final start = _underline(_fromMarkKey);
    final end = _underline(_toMarkKey);
    if (start == null ||
        end == null ||
        MediaQuery.disableAnimationsOf(context) ||
        !TickerMode.valuesOf(context).enabled) {
      setState(() => _markFrom = null);
      return;
    }
    final slide =
        _markSlide = AnimationController(
          vsync: this,
          duration: AppMotion.standard,
        );
    setState(() {
      _markStart = start;
      _markEnd = end;
    });
    slide.forward().whenComplete(() {
      if (!mounted || _markSlide != slide) return;
      slide.dispose();
      setState(() {
        _markSlide = null;
        _markFrom = null;
      });
    });
  }

  /// The underline of the tab under [key], in the row's coordinates.
  Rect? _underline(GlobalKey key) {
    final label = key.currentContext?.findRenderObject() as RenderBox?;
    final row = _contentKey.currentContext?.findRenderObject() as RenderBox?;
    if (label == null || row == null || !label.hasSize) return null;
    final origin = label.localToGlobal(Offset.zero, ancestor: row);
    return Rect.fromLTWH(
      origin.dx,
      origin.dy + label.size.height - _UnderlineTab.markWidth,
      label.size.width,
      _UnderlineTab.markWidth,
    );
  }

  void _revealSelected(Duration duration) {
    if (!mounted) return;
    final tabContext = _selectedTabKey.currentContext;
    if (tabContext == null) return;
    Scrollable.ensureVisible(
      tabContext,
      alignment: 0.5,
      duration: duration,
      curve: AppMotion.curve,
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
    final height = widget.height < 48 ? 48.0 : widget.height;
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
          stops: [0.0, _fadeStart ? ramp : 0.0, _fadeEnd ? 1 - ramp : 1.0, 1.0],
        ).createShader(bounds);
      },
      blendMode: BlendMode.dstIn,
      child: LayoutBuilder(
        builder:
            (context, constraints) => SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth),
                // Passes the constraints through, so the row lays out exactly
                // as it would on its own; the stack only carries the mark
                // while it slides.
                child: Stack(
                  key: _contentKey,
                  fit: StackFit.passthrough,
                  children: [
                    Row(
                      // Every tap target fills the strip's full height, so a
                      // 22px label does not mean a 22px hit box in a 44px bar.
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = 0; i < widget.tabs.length; i++)
                          _UnderlineTab(
                            key:
                                i == widget.selectedIndex
                                    ? _selectedTabKey
                                    : null,
                            markKey:
                                _markFrom == null
                                    ? null
                                    : i == _markFrom
                                    ? _fromMarkKey
                                    : i == widget.selectedIndex
                                    ? _toMarkKey
                                    : null,
                            data: widget.tabs[i],
                            selected: i == widget.selectedIndex,
                            // While the mark slides, no tab draws its own.
                            marked:
                                _markFrom == null
                                    ? i == widget.selectedIndex
                                    : _markSlide == null && i == _markFrom,
                            color: widget.color,
                          ),
                        if (widget.trailing != null)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                            child: Center(child: widget.trailing!),
                          ),
                      ],
                    ),
                    if (_markSlide case final slide?)
                      AnimatedBuilder(
                        animation: slide,
                        builder:
                            (context, _) => Positioned.fromRect(
                              rect:
                                  Rect.lerp(
                                    _markStart,
                                    _markEnd,
                                    AppMotion.move.transform(slide.value),
                                  )!,
                              child: ColoredBox(color: widget.color),
                            ),
                      ),
                  ],
                ),
              ),
            ),
      ),
    );

    // A Material, not a plain Container: the tabs' ink needs a surface of its
    // own here, or the splash paints into the Scaffold's Material *behind* the
    // bar's opaque ground and a tap looks like it did nothing.
    return Material(
      color: backgroundColor(context),
      child: DecoratedBox(
        decoration: BoxDecoration(
          // A single-edge border is a rule, not a box: one unbroken hairline
          // across the full width, and it stays square.
          border:
              widget.rule == StripRule.bottom
                  ? Border(bottom: BorderSide(color: hairlineColor(context)))
                  : Border(top: BorderSide(color: hairlineColor(context))),
        ),
        child: SizedBox(height: height, child: strip),
      ),
    );
  }
}

class _UnderlineTab extends StatelessWidget {
  /// The underline's thickness.
  static const double markWidth = 2;

  final UnderlineTabData data;
  final bool selected;

  /// Whether this tab draws the underline. The selected tab does, except
  /// while the strip's mark slides to it.
  final bool marked;

  /// Finds this tab's underline, for the strip to measure.
  final Key? markKey;
  final Color color;
  const _UnderlineTab({
    super.key,
    required this.data,
    required this.selected,
    required this.marked,
    required this.color,
    this.markKey,
  });

  @override
  Widget build(BuildContext context) {
    final textSecondary = textSecondaryColor(context);

    return Semantics(
      label: data.label,
      selected: selected,
      button: data.onTap != null,
      excludeSemantics: true,
      child: InkWell(
        onTap: data.onTap,
        onLongPress: data.onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          child: Center(
            // The underline borders the label, not the full-height cell, so it
            // spans exactly the text without any intrinsic-width work.
            child: Container(
              key: markKey,
              padding: const EdgeInsets.only(bottom: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: marked ? color : Colors.transparent,
                    width: markWidth,
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (data.index != null) ...[
                    Text(
                      data.index!,
                      style: Theme.of(
                        context,
                      ).textTheme.labelSmall!.copyWith(color: textSecondary),
                    ),
                    const SizedBox(width: 6),
                  ],
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: Text(
                      data.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.labelMedium!.copyWith(
                        fontWeight:
                            selected ? FontWeight.w600 : FontWeight.w400,
                        color: selected ? color : textSecondary,
                      ),
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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/supabase_service.dart';
import '../data/exercise_library.dart';
import '../models/exercise_definition.dart';
import '../services/exercise_catalog.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/app_typography.dart';
import '../theme/motion.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'app_header.dart';
import 'motion/app_modals.dart';
import 'motion/page_switcher.dart';
import 'motion/press_scale.dart';
import 'muscle_group_illustration.dart';
import 'rolling_figure.dart';

/// Whether the picker lays out for little room: one column of group rows,
/// stacked footer buttons, an icon-only custom action. Decided by the width
/// the text effectively has, so a mid-size phone with larger text drops to
/// one column before a label would clip, not only at a fixed scale.
bool _isCompact(MediaQueryData media) {
  final scale = media.textScaler.scale(1);
  return media.size.width < 360 ||
      scale >= 1.375 ||
      media.size.width / scale < 320;
}

/// Completes when the picker closes, however it was closed. Selections have
/// already been applied through [onAdd]/[onRemove] by then.
Future<void> showExercisePickerSheet(
  BuildContext context, {
  required Iterable<String> selectedExerciseNames,
  Iterable<String> alreadyAddedExerciseNames = const <String>[],
  required void Function(String name) onAdd,
  required void Function(String name) onRemove,
  String selectionOwner = 'workout',
  String? userId,
  Iterable<String>? selectedExerciseIds,
  Iterable<String>? alreadyAddedExerciseIds,
  void Function(String name, String exerciseId)? onAddIdentified,
  void Function(String name, String exerciseId)? onRemoveIdentified,
}) {
  final navigator = Navigator.of(context);
  return navigator.push(
    _ExercisePickerRoute<void>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      backgroundColor: surfaceColor(context),
      sheetAnimationStyle: appSheetAnimationStyle(context),
      builder:
          (sheetContext) => _ExercisePickerSheet(
            selectedExerciseNames: selectedExerciseNames,
            alreadyAddedExerciseNames: alreadyAddedExerciseNames,
            onAdd: onAdd,
            onRemove: onRemove,
            selectionOwner: selectionOwner,
            userId: userId,
            selectedExerciseIds: selectedExerciseIds,
            alreadyAddedExerciseIds: alreadyAddedExerciseIds,
            onAddIdentified: onAddIdentified,
            onRemoveIdentified: onRemoveIdentified,
          ),
    ),
  );
}

/// One catalog choice: the label to snapshot and its stable identity.
typedef PickedExercise = ({String name, String exerciseId});

/// The same library, but choosing one exercise closes it with that choice.
///
/// Resolves to null when the picker closes without a choice. Movements in
/// [unavailableExerciseIds] (canonical or redirected IDs) read as *Added* and
/// cannot be chosen, as in the multi-select flow.
Future<PickedExercise?> pickSingleExercise(
  BuildContext context, {
  required String title,
  Iterable<String> unavailableExerciseIds = const <String>[],
  String? userId,
}) {
  final navigator = Navigator.of(context);
  return navigator.push<PickedExercise>(
    _ExercisePickerRoute<PickedExercise>(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      backgroundColor: surfaceColor(context),
      sheetAnimationStyle: appSheetAnimationStyle(context),
      builder:
          (sheetContext) => _ExercisePickerSheet(
            title: title,
            singlePick: true,
            selectedExerciseNames: const <String>[],
            alreadyAddedExerciseNames: const <String>[],
            alreadyAddedExerciseIds: unavailableExerciseIds,
            userId: userId,
            onAdd: (_) {},
            onRemove: (_) {},
            selectionOwner: 'workout',
          ),
    ),
  );
}

/// Outside taps explicitly close the picker, like Close and dragging it down.
/// Only system Back follows the internal muscle-group navigation.
class _ExercisePickerRoute<T> extends ModalBottomSheetRoute<T> {
  _ExercisePickerRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.backgroundColor,
    required super.sheetAnimationStyle,
  }) : super(
         isScrollControlled: true,
         shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
       );

  @override
  Widget buildModalBarrier() => Semantics(
    label: barrierLabel,
    onDismiss: () => navigator?.pop(),
    child: GestureDetector(
      behavior: HitTestBehavior.opaque,
      excludeFromSemantics: true,
      onTap: () => navigator?.pop(),
      child: IgnorePointer(child: super.buildModalBarrier()),
    ),
  );
}

enum _PickerView { groups, category, selected }

class _ExercisePickerSheet extends StatefulWidget {
  final Iterable<String> selectedExerciseNames;
  final Iterable<String> alreadyAddedExerciseNames;
  final void Function(String name) onAdd;
  final void Function(String name) onRemove;
  final String selectionOwner;
  final String title;

  /// Choosing an exercise closes the picker with its name instead of
  /// toggling a selection; there is no selection list or footer.
  final bool singlePick;
  final String? userId;
  final Iterable<String>? selectedExerciseIds;
  final Iterable<String>? alreadyAddedExerciseIds;
  final void Function(String name, String exerciseId)? onAddIdentified;
  final void Function(String name, String exerciseId)? onRemoveIdentified;

  const _ExercisePickerSheet({
    required this.selectedExerciseNames,
    required this.alreadyAddedExerciseNames,
    required this.onAdd,
    required this.onRemove,
    required this.selectionOwner,
    this.title = 'Add exercises',
    this.singlePick = false,
    this.userId,
    this.selectedExerciseIds,
    this.alreadyAddedExerciseIds,
    this.onAddIdentified,
    this.onRemoveIdentified,
  });

  @override
  State<_ExercisePickerSheet> createState() => _ExercisePickerSheetState();
}

class _ExercisePickerSheetState extends State<_ExercisePickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  final Map<String, String> _selectedNames = <String, String>{};
  final Set<String> _alreadyAddedNames = <String>{};
  _PickerView _view = _PickerView.groups;
  String? _selectedCategory;
  String _query = '';

  /// The view on screen, and whether reaching it went deeper (or across) or
  /// back, so the transition knows which side to enter from.
  String? _shownViewId;
  bool _forward = true;

  /// The share of the room above the keyboard the sheet takes.
  static const double _sheetHeightFactor = 0.92;

  @override
  void initState() {
    super.initState();
    _alreadyAddedNames.addAll(
      (widget.alreadyAddedExerciseIds ??
              widget.alreadyAddedExerciseNames.map(_key))
          .map(ExerciseCatalog.canonicalId),
    );
    final names = widget.selectedExerciseNames.toList();
    final ids = widget.selectedExerciseIds?.toList();
    for (var i = 0; i < names.length; i++) {
      final key =
          ids != null && i < ids.length
              ? ExerciseCatalog.canonicalId(ids[i])
              : _key(names[i]);
      if (!_alreadyAddedNames.contains(key)) _selectedNames[key] = names[i];
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _key(String name) => ExerciseCatalog.identity(name);

  void _toggleExercise(_ExerciseResult result) {
    final key = ExerciseCatalog.canonicalId(result.id);
    if (_alreadyAddedNames.contains(key)) return;
    if (widget.singlePick) {
      Navigator.pop<PickedExercise>(context, (
        name: result.name,
        exerciseId: key,
      ));
      return;
    }
    final selectedName = _selectedNames.remove(key);
    if (selectedName != null) {
      if (widget.onRemoveIdentified != null) {
        widget.onRemoveIdentified!(selectedName, key);
      } else {
        widget.onRemove(selectedName);
      }
    } else {
      _selectedNames[key] = result.name;
      if (widget.onAddIdentified != null) {
        widget.onAddIdentified!(result.name, key);
      } else {
        widget.onAdd(result.name);
      }
    }
    setState(() {});
  }

  void _addDefinition(ExerciseDefinition d) {
    final key = ExerciseCatalog.canonicalId(d.id);
    if (_selectedNames.containsKey(key) || _alreadyAddedNames.contains(key)) {
      return;
    }
    _toggleExercise(
      _ExerciseResult(id: key, name: d.name, category: d.category),
    );
  }

  List<ExerciseDefinition> _inCategory(String category) =>
      ExerciseCatalog.active.where((d) => d.category == category).toList();

  void _openCategory(String category) {
    setState(() {
      _selectedCategory = category;
      _view = _PickerView.category;
    });
  }

  void _showGroups() {
    setState(() {
      _view = _PickerView.groups;
      _selectedCategory = null;
    });
  }

  /// Done steps back out of a muscle group (or the selected list) to the
  /// groups page, like the back button; only from there does it close.
  void _done() {
    if (_view == _PickerView.groups) {
      Navigator.pop(context);
      return;
    }
    _searchController.clear();
    _query = '';
    _showGroups();
  }

  void _showSelected() {
    setState(() {
      _searchController.clear();
      _query = '';
      _view = _PickerView.selected;
    });
  }

  List<_ExerciseResult> get _searchResults => [
    for (final d in ExerciseCatalog.search(_query))
      _ExerciseResult(id: d.id, name: d.name, category: d.category),
  ];

  Future<void> _createCustomExercise({String initialName = ''}) async {
    String inputText = initialName;
    String? errorText;
    bool saving = false;
    if (initialName.trim().isNotEmpty &&
        (_selectedNames.containsKey(_key(initialName)) ||
            _alreadyAddedNames.contains(_key(initialName)))) {
      errorText = 'Exercise with this name already exists';
    }

    await showAppDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final input = inputText.trim();
            final valid = input.isNotEmpty && errorText == null;
            final suggestions = ExerciseCatalog.suggestions(input);
            final existing = ExerciseCatalog.findByName(input);
            return PopScope(
              canPop: !saving,
              child: AlertDialog(
                backgroundColor: surfaceColor(context),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadius.card,
                ),
                title: Text(
                  'Create custom exercise',
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                content: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      TextFormField(
                        initialValue: initialName,
                        enabled: !saving,
                        maxLength: 100,
                        autofocus: true,
                        textCapitalization: TextCapitalization.words,
                        style: Theme.of(context).textTheme.bodyLarge,
                        decoration: InputDecoration(
                          labelText: 'Exercise name',
                          hintText: 'Enter exercise name',
                          errorText: errorText,
                        ),
                        onChanged: (value) {
                          setDialogState(() {
                            inputText = value;
                            final trimmed = value.trim();
                            if (trimmed.isEmpty) {
                              errorText = 'Name cannot be empty';
                            } else if (_selectedNames.containsKey(
                                  _key(trimmed),
                                ) ||
                                _alreadyAddedNames.contains(_key(trimmed))) {
                              errorText =
                                  'Exercise with this name already exists';
                            } else {
                              errorText = null;
                            }
                          });
                        },
                      ),
                      if (suggestions.isNotEmpty) ...[
                        const SizedBox(height: AppSpacing.sm),
                        const Text('Use an existing exercise?'),
                        for (final d in suggestions)
                          TextButton(
                            onPressed:
                                saving ||
                                        _selectedNames.containsKey(d.id) ||
                                        _alreadyAddedNames.contains(d.id)
                                    ? null
                                    : () {
                                      Navigator.pop(dialogContext);
                                      _addDefinition(d);
                                    },
                            child: Text(d.name),
                          ),
                      ],
                    ],
                  ),
                ),
                actions: [
                  TextButton(
                    onPressed:
                        saving ? null : () => Navigator.pop(dialogContext),
                    child: const Text('Cancel'),
                  ),
                  TextButton(
                    onPressed:
                        valid && !saving
                            ? () async {
                              setDialogState(() => saving = true);
                              try {
                                final definition = await SyncService.instance
                                    .runExclusiveLocalMutation(() async {
                                      if (!mounted ||
                                          SupabaseService.currentUserId !=
                                              widget.userId) {
                                        throw StateError(
                                          'The exercise account changed.',
                                        );
                                      }
                                      return ExerciseCatalog.createCustom(
                                        inputText,
                                        userId: widget.userId,
                                      );
                                    });
                                SyncService.instance.notifyLocalChange();
                                if (!dialogContext.mounted || !mounted) {
                                  return;
                                }
                                Navigator.pop(dialogContext);
                                _addDefinition(definition);
                              } catch (error) {
                                debugPrint('Could not create exercise: $error');
                                if (dialogContext.mounted) {
                                  setDialogState(() {
                                    saving = false;
                                    errorText =
                                        'Could not save exercise. Try again.';
                                  });
                                }
                              }
                            }
                            : null,
                    child: Text(
                      saving
                          ? 'Saving…'
                          : existing == null
                          ? 'Create'
                          : 'Use existing',
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboardInset = media.viewInsets.bottom;
    final availableHeight = media.size.height - keyboardInset;

    return PopScope(
      canPop: _view == _PickerView.groups && _query.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_query.isNotEmpty) {
          setState(() {
            _searchController.clear();
            _query = '';
          });
        } else {
          _showGroups();
        }
      },
      // Follows the keyboard on the app's quick timing.
      child: AnimatedPadding(
        duration: AppMotion.of(context, AppMotion.quick),
        curve: AppMotion.curve,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: availableHeight * _sheetHeightFactor,
            child: Column(
              children: [
                _buildHeader(),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.lg,
                  ),
                  child: _SearchField(
                    controller: _searchController,
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                Expanded(child: _buildContent()),
                if (!widget.singlePick) _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      children: [
        // The sheet already drags down to close; the handle only says so. It
        // is the Material handle other sheets show (32x4, the secondary ink),
        // without the 48px band `showDragHandle` reserves above a header that
        // has its own Close.
        Padding(
          padding: const EdgeInsets.only(top: AppSpacing.sm),
          child: ExcludeSemantics(
            child: Container(
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: textSecondaryColor(context),
                borderRadius: AppRadius.micro,
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.xs,
            AppSpacing.sm,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              Semantics(
                button: true,
                label: 'Close exercise picker',
                child: IconButton(
                  tooltip: 'Close',
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(LucideIcons.x),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  /// One id per page: typing more into a search keeps the id, so only moving
  /// between pages animates.
  String get _viewId {
    if (_query.trim().isNotEmpty) return 'search';
    return switch (_view) {
      _PickerView.groups => 'groups',
      _PickerView.category => 'category:$_selectedCategory',
      _PickerView.selected => 'selected',
    };
  }

  /// Groups are the top; a category or the selected list sits one step in,
  /// and search results one step further.
  static int _depthOf(String viewId) => switch (viewId) {
    'groups' => 0,
    'search' => 2,
    _ => 1,
  };

  Widget _buildContent() {
    final id = _viewId;
    if (id != _shownViewId) {
      final previous = _shownViewId;
      if (previous != null) _forward = _depthOf(id) >= _depthOf(previous);
      _shownViewId = id;
    }
    return PageSwitcher(
      forward: _forward,
      child: KeyedSubtree(key: ValueKey<String>(id), child: _buildView()),
    );
  }

  Widget _buildView() {
    if (_query.trim().isNotEmpty) return _buildSearchResults();
    switch (_view) {
      case _PickerView.groups:
        return _buildGroupGrid();
      case _PickerView.category:
        return _buildCategoryList();
      case _PickerView.selected:
        return _buildSelectedList();
    }
  }

  int _selectedIn(String category) =>
      _inCategory(
        category,
      ).where((d) => _selectedNames.containsKey(d.id)).length;

  Widget get _customAction =>
      _CustomExerciseButton(onTap: () => _createCustomExercise());

  Widget _buildGroupGrid() {
    final media = MediaQuery.of(context);
    final useSingleColumn = _isCompact(media);
    final categories = [
      ...ExerciseLibrary.categoryNames,
      ...ExerciseCatalog.active
          .map((d) => d.category)
          .where((c) => !ExerciseLibrary.categoryNames.contains(c))
          .toSet(),
    ];
    final columns = useSingleColumn ? 1 : 2;
    // Counted now, so a builder that runs again while this page animates out
    // reads what it was built with.
    final counts = {for (final c in categories) c: _inCategory(c).length};
    final selectedCounts = {for (final c in categories) c: _selectedIn(c)};
    final keyboardInset = media.viewInsets.bottom;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextBar(title: 'Muscle groups', trailing: _customAction),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final heroHeight =
                  useSingleColumn
                      ? 0.0
                      : _MuscleGroupTile.heroHeightFor(
                        width: constraints.maxWidth,
                        // The keyboard only borrows the room: cards keep
                        // their size and the grid scrolls under it.
                        height:
                            constraints.maxHeight +
                            keyboardInset * _sheetHeightFactor,
                        rows: (categories.length / columns).ceil(),
                        textTheme: textTheme,
                        textScaler: media.textScaler,
                      );
              Widget tile(String category) => _MuscleGroupTile(
                category: category,
                count: counts[category]!,
                selectedCount: selectedCounts[category]!,
                compact: useSingleColumn,
                heroHeight: heroHeight,
                onTap: () => _openCategory(category),
              );
              // Rows sized by their content rather than a fixed aspect
              // ratio, so larger text grows a tile instead of clipping its
              // label, and the two tiles in a row always match.
              return ListView(
                key: const ValueKey('muscle-group-grid'),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  _MuscleGroupTile.gridTopPadding,
                  AppSpacing.lg,
                  _MuscleGroupTile.gridBottomPadding,
                ),
                children: [
                  for (
                    var start = 0;
                    start < categories.length;
                    start += columns
                  )
                    Padding(
                      padding: EdgeInsets.only(
                        top: start == 0 ? 0 : _MuscleGroupTile.gap,
                      ),
                      child: IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            for (var i = start; i < start + columns; i++) ...[
                              if (i > start)
                                const SizedBox(width: _MuscleGroupTile.gap),
                              Expanded(
                                child:
                                    i < categories.length
                                        ? tile(categories[i])
                                        : const SizedBox.shrink(),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildCategoryList() {
    final category = _selectedCategory!;
    final definitions = _inCategory(category);
    final selected = _selectedIn(category);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextBar(
          backTooltip: 'Muscle groups',
          onBack: _showGroups,
          // The tile's figure, small, so the list reads as the group opened.
          leading: SizedBox(
            width: 28,
            height: 40,
            child: MuscleGroupIllustration(group: category, bothViews: false),
          ),
          title: category,
          subtitle:
              selected == 0
                  ? '${definitions.length} exercises'
                  : '${definitions.length} exercises · $selected selected',
          trailing: _customAction,
        ),
        Expanded(
          child: _ExerciseList(
            results: [
              for (final d in definitions)
                _ExerciseResult(id: d.id, name: d.name, category: category),
            ],
            selectedNames: _selectedNames,
            alreadyAddedNames: _alreadyAddedNames,
            onToggle: _toggleExercise,
            singlePick: widget.singlePick,
            showCategory: false,
          ),
        ),
      ],
    );
  }

  Widget _buildSearchResults() {
    final results = _searchResults;
    if (results.isEmpty) {
      return _EmptyState(
        title: 'No exercises found',
        body: 'Try another name or create a custom exercise.',
        actionLabel: 'Create “${_query.trim()}”',
        onAction: () => _createCustomExercise(initialName: _query.trim()),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextBar(
          title: results.length == 1 ? '1 result' : '${results.length} results',
          trailing: _customAction,
        ),
        Expanded(
          child: _ExerciseList(
            results: results,
            selectedNames: _selectedNames,
            alreadyAddedNames: _alreadyAddedNames,
            onToggle: _toggleExercise,
            singlePick: widget.singlePick,
            showCategory: true,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedList() {
    final results = [
      for (final entry in _selectedNames.entries)
        _ExerciseResult(
          id: entry.key,
          name: entry.value,
          category: ExerciseCatalog.getById(entry.key)?.category ?? 'Custom',
        ),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextBar(
          backTooltip: 'Back',
          onBack: _showGroups,
          title: 'Selected exercises',
          trailing: _customAction,
        ),
        Expanded(
          child:
              results.isEmpty
                  ? const _EmptyState(
                    title: 'No exercises selected',
                    body: 'Choose exercises from a muscle group or search.',
                  )
                  : _ExerciseList(
                    results: results,
                    selectedNames: _selectedNames,
                    alreadyAddedNames: _alreadyAddedNames,
                    onToggle: _toggleExercise,
                    singlePick: widget.singlePick,
                    showCategory: true,
                  ),
        ),
      ],
    );
  }

  Widget _buildFooter() {
    final media = MediaQuery.of(context);
    // Where the grid drops to one column, two half-width buttons cannot hold
    // their labels either; stack them and let the semantics carry the hint.
    final compact = _isCompact(media);
    final count = _selectedNames.length;
    // Quiet while there is nothing to review, the tonal accent once there is.
    final quietGround = controlFillColor(context);
    final quietInk = textSecondaryColor(context);
    final tonalGround = accentMutedColor(context);
    final tonalInk = accentOnMutedColor(context);
    final selected = TweenAnimationBuilder<double>(
      tween: Tween<double>(end: count == 0 ? 0 : 1),
      duration: AppMotion.of(context, AppMotion.quick),
      curve: AppMotion.curve,
      child: _RollingCountLabel(
        prefix: 'Selected (',
        count: count,
        suffix: ')',
      ),
      builder:
          (context, t, label) => OutlinedButton(
            style: OutlinedButton.styleFrom(
              backgroundColor: Color.lerp(quietGround, tonalGround, t),
              foregroundColor: Color.lerp(quietInk, tonalInk, t),
              // The tween above already eases the colours.
              animationDuration: Duration.zero,
              minimumSize: const Size.fromHeight(48),
              shape: const RoundedRectangleBorder(
                borderRadius: AppRadius.button,
              ),
            ),
            onPressed: _showSelected,
            child: label,
          ),
    );
    final done = FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: accentFillColor(context),
        foregroundColor: onAccentColor(context),
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      onPressed: _done,
      child: const Text('Done'),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.md,
      ),
      decoration: BoxDecoration(
        color: surfaceColor(context),
        border: Border(top: BorderSide(color: hairlineColor(context))),
      ),
      child: Semantics(
        label:
            'Selections for ${widget.selectionOwner}. Changes apply as you select.',
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) ...[
              selected,
              const SizedBox(height: AppSpacing.sm),
              done,
            ] else ...[
              Text(
                'Changes apply as you select.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: textSecondaryColor(context),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(child: selected),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: done),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ExerciseResult {
  final String id;
  final String name;
  final String category;

  const _ExerciseResult({
    required this.id,
    required this.name,
    required this.category,
  });
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onChanged;

  const _SearchField({required this.controller, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: false,
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search exercises',
        prefixIcon: const Icon(LucideIcons.search, size: 18),
        suffixIcon:
            controller.text.isEmpty
                ? null
                : IconButton(
                  tooltip: 'Clear search',
                  onPressed: () {
                    controller.clear();
                    onChanged('');
                  },
                  icon: const Icon(LucideIcons.x, size: 18),
                ),
      ),
    );
  }
}

/// The always-available way out of the library: compact enough to share a
/// row with the view's title, named in full for screen readers.
class _CustomExerciseButton extends StatelessWidget {
  final VoidCallback onTap;

  const _CustomExerciseButton({required this.onTap});

  static const String _label = 'Create custom exercise';

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    // Same cut-off as the muscle-group grid: where the tiles drop to one
    // column, the label would crowd the title, so the icon stands alone.
    final compact = _isCompact(media);
    return Semantics(
      button: true,
      label: _label,
      onTap: onTap,
      excludeSemantics: true,
      child: Tooltip(
        message: _label,
        excludeFromSemantics: true,
        child:
            compact
                ? IconButton(
                  onPressed: onTap,
                  icon: const Icon(LucideIcons.plus, size: 20),
                )
                : TextButton.icon(
                  onPressed: onTap,
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                    ),
                  ),
                  icon: const Icon(LucideIcons.plus, size: 18),
                  label: const Text('New exercise'),
                ),
      ),
    );
  }
}

/// Where the picker is, on one line: an optional back step, the current
/// view's title, and the custom-exercise action.
class _ContextBar extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? backTooltip;
  final VoidCallback? onBack;

  /// A small decorative mark between the back step and the title.
  final Widget? leading;
  final Widget? trailing;

  const _ContextBar({
    required this.title,
    this.subtitle,
    this.backTooltip,
    this.onBack,
    this.leading,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        onBack == null ? AppSpacing.lg : AppSpacing.xs,
        AppSpacing.sm,
        AppSpacing.sm,
        AppSpacing.xs,
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          children: [
            if (onBack != null)
              AppBackButton(tooltip: backTooltip ?? 'Back', onPressed: onBack),
            if (leading != null) ...[
              leading!,
              const SizedBox(width: AppSpacing.md),
            ],
            Expanded(
              child: Semantics(
                header: true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: textTheme.titleMedium,
                    ),
                    if (subtitle != null)
                      Text(
                        subtitle!,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: textTheme.bodySmall?.copyWith(
                          color: textSecondaryColor(context),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.sm),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A muscle group as an illustrated card: the front and back figures lead,
/// the name and its count below. Where two columns don't fit (narrow screens,
/// large text) it becomes a row led by a single figure, ending in a chevron.
/// A group with selections takes the selected ground and accent edge, says
/// how many in its count line, and wears a count badge.
class _MuscleGroupTile extends StatelessWidget {
  final String category;
  final int count;
  final int selectedCount;

  /// The one-column row instead of the card.
  final bool compact;

  /// The card's figure height; see [heroHeightFor]. Unused when [compact].
  final double heroHeight;
  final VoidCallback onTap;

  const _MuscleGroupTile({
    required this.category,
    required this.count,
    required this.selectedCount,
    required this.compact,
    required this.heroHeight,
    required this.onTap,
  });

  /// The grid's own insets and the gap between tiles, shared with the sizing
  /// below so the arithmetic and the layout can't drift apart.
  static const double gridTopPadding = AppSpacing.xs;
  static const double gridBottomPadding = AppSpacing.lg;
  static const double gap = AppSpacing.sm;
  static const double _heroInset = AppSpacing.sm;
  static const double _textInset = AppSpacing.md;
  static const double _minHero = 64;

  /// On a tall tablet sheet the rows stop growing here and the grid ends
  /// short instead of the figures turning into posters.
  static const double _maxHero = 160;

  static TextStyle? _nameStyle(TextTheme textTheme) =>
      textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700);

  /// How tall a card's figures can be so the first three rows fill a grid of
  /// [width] by [height]: the figures grow on a taller phone instead of
  /// leaving the bottom of the sheet empty. A fourth row (custom categories)
  /// peeks in below. Never so small the pair stops reading, and never much
  /// taller than the pair can be drawn at the card's width or than
  /// [_maxHero].
  static double heroHeightFor({
    required double width,
    required double height,
    required int rows,
    required TextTheme textTheme,
    required TextScaler textScaler,
  }) {
    double lineHeight(TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: 'Ag', style: style),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      final result = painter.height;
      painter.dispose();
      return result;
    }

    final cardWidth = (width - AppSpacing.lg * 2 - gap) / 2;
    final drawable =
        (cardWidth - _heroInset * 2) /
        MuscleGroupIllustration.aspectRatio(bothViews: true);
    final visibleRows = rows <= 3 ? rows.toDouble() : 3.4;
    final perRow =
        (height -
            gridTopPadding -
            gridBottomPadding -
            gap * (visibleRows - 1)) /
        visibleRows;
    final text =
        lineHeight(_nameStyle(textTheme)) +
        AppSpacing.xxs +
        lineHeight(textTheme.bodySmall);
    final budget = perRow - _cardChrome - text;
    return budget.clamp(
      _minHero,
      math.max(_minHero, math.min(_maxHero, drawable * 1.2)),
    );
  }

  /// The card's vertical padding plus the gap between figure and name.
  static const double _cardChrome = AppSpacing.md * 3;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final hasSelection = selectedCount > 0;
    // On the dark selected ground (the accent's wash) the plain accent can
    // fall short, so ink there is re-solved against the wash.
    final onWash =
        hasSelection && Theme.of(context).brightness == Brightness.dark;
    final ink = onWash ? accentOnMutedColor(context) : accentColor(context);
    final name = Text(
      category,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: _MuscleGroupTile._nameStyle(textTheme),
    );
    final summary = Text(
      hasSelection ? '$selectedCount of $count selected' : '$count exercises',
      // Two lines before it ever clips: the row grows and the grid scrolls.
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: textTheme.bodySmall?.copyWith(
        color: hasSelection ? ink : secondary,
        fontWeight: hasSelection ? FontWeight.w600 : null,
      ),
    );
    final badge = _CountBadge(count: selectedCount);

    final Widget content;
    if (compact) {
      content = Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            SizedBox(
              width: 36,
              height: 52,
              child: MuscleGroupIllustration(
                group: category,
                bothViews: false,
                highlightColor: onWash ? ink : null,
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  name,
                  const SizedBox(height: AppSpacing.xxs),
                  summary,
                ],
              ),
            ),
            if (hasSelection) ...[const SizedBox(width: AppSpacing.sm), badge],
            const SizedBox(width: AppSpacing.sm),
            Icon(LucideIcons.chevronRight, size: 18, color: secondary),
          ],
        ),
      );
    } else {
      // The badge closes the text block rather than sitting in a corner: the
      // figure pair spans the card's width, so a corner badge lands on it.
      content = Padding(
        padding: const EdgeInsets.fromLTRB(
          _MuscleGroupTile._heroInset,
          AppSpacing.md,
          _MuscleGroupTile._heroInset,
          AppSpacing.md,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: heroHeight,
              child: MuscleGroupIllustration(
                group: category,
                highlightColor: onWash ? ink : null,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal:
                    _MuscleGroupTile._textInset - _MuscleGroupTile._heroInset,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        name,
                        const SizedBox(height: AppSpacing.xxs),
                        summary,
                      ],
                    ),
                  ),
                  if (hasSelection) ...[
                    const SizedBox(width: AppSpacing.sm),
                    badge,
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    }

    return Semantics(
      button: true,
      label:
          hasSelection
              ? '$category, $count exercises, '
                  '$selectedCount selected'
              : '$category, $count exercises',
      excludeSemantics: true,
      onTap: onTap,
      // A slight give under the finger; still under reduced motion.
      child: PressScale(
        builder:
            (context, onHighlightChanged) => Material(
              color:
                  hasSelection
                      ? selectedGroundColor(context)
                      : controlFillColor(context),
              shape: RoundedRectangleBorder(
                side:
                    hasSelection
                        ? BorderSide(color: accentColor(context), width: 1.5)
                        : BorderSide.none,
                borderRadius: AppRadius.card,
              ),
              child: InkWell(
                onTap: onTap,
                onHighlightChanged: onHighlightChanged,
                borderRadius: AppRadius.card,
                child: content,
              ),
            ),
      ),
    );
  }
}

/// How many of a group's exercises are selected, as a small accent pill.
class _CountBadge extends StatelessWidget {
  final int count;

  const _CountBadge({required this.count});

  @override
  Widget build(BuildContext context) {
    // Sized by its figure, never stretched by the row it sits in.
    return Container(
      constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs + 2),
      decoration: BoxDecoration(
        color: accentFillColor(context),
        borderRadius: AppRadius.pill,
      ),
      child: Center(
        widthFactor: 1,
        heightFactor: 1,
        child: Text(
          '$count',
          style: AppTypography.figures(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            height: 1,
            color: onAccentColor(context),
          ),
        ),
      ),
    );
  }
}

/// A label such as "Selected (3)" whose number rolls to its new value.
///
/// The whole label stays one [Text], so screen readers and finders read it
/// as written; its number is drawn in clear ink and a [RollingFigure] sits
/// exactly over it. Under reduced motion the number is simply drawn.
class _RollingCountLabel extends StatelessWidget {
  final String prefix;
  final int count;
  final String suffix;

  const _RollingCountLabel({
    required this.prefix,
    required this.count,
    required this.suffix,
  });

  @override
  Widget build(BuildContext context) {
    final style = DefaultTextStyle.of(context).style;
    // Tabular, so the suffix holds still while the number rolls.
    final figureStyle = style.merge(
      AppTypography.figures(fontWeight: style.fontWeight),
    );
    final digits = '$count';
    final roll = !MediaQuery.disableAnimationsOf(context);
    final label = Text.rich(
      TextSpan(
        children: [
          TextSpan(text: prefix),
          TextSpan(
            text: digits,
            style:
                roll
                    ? figureStyle.copyWith(
                      color: figureStyle.color?.withValues(alpha: 0),
                    )
                    : figureStyle,
          ),
          TextSpan(text: suffix),
        ],
      ),
      maxLines: 1,
      softWrap: false,
    );
    // Shrinks rather than clips where the button runs short of room; the
    // number's overlay scales with it, so the two stay aligned.
    if (!roll) return FittedBox(fit: BoxFit.scaleDown, child: label);
    // Separate spans shape separately, so the number starts exactly where
    // the prefix alone ends.
    final painter = TextPainter(
      text: TextSpan(text: prefix, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    final start = painter.width;
    painter.dispose();
    return FittedBox(
      fit: BoxFit.scaleDown,
      child: Stack(
        children: [
          label,
          PositionedDirectional(
            start: start,
            top: 0,
            child: ExcludeSemantics(
              child: RollingFigure(digits, style: figureStyle),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  final List<_ExerciseResult> results;
  final Map<String, String> selectedNames;
  final Set<String> alreadyAddedNames;
  final ValueChanged<_ExerciseResult> onToggle;
  final bool showCategory;
  final bool singlePick;

  const _ExerciseList({
    required this.results,
    required this.selectedNames,
    required this.alreadyAddedNames,
    required this.onToggle,
    required this.showCategory,
    this.singlePick = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.xs,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      itemCount: results.length,
      separatorBuilder:
          (context, index) => Divider(
            height: 1,
            indent: AppSpacing.md,
            endIndent: AppSpacing.md,
            color: hairlineColor(context),
          ),
      itemBuilder: (context, index) {
        final result = results[index];
        final normalizedName = ExerciseCatalog.canonicalId(result.id);
        final selected = selectedNames.containsKey(normalizedName);
        final alreadyAdded = alreadyAddedNames.contains(normalizedName);
        return _ExerciseRow(
          result: result,
          selected: selected,
          alreadyAdded: alreadyAdded,
          showCategory: showCategory,
          singlePick: singlePick,
          onTap: () => onToggle(result),
        );
      },
    );
  }
}

class _ExerciseRow extends StatelessWidget {
  final _ExerciseResult result;
  final bool selected;
  final bool alreadyAdded;
  final bool showCategory;
  final bool singlePick;
  final VoidCallback onTap;

  const _ExerciseRow({
    required this.result,
    required this.selected,
    required this.alreadyAdded,
    required this.showCategory,
    required this.onTap,
    this.singlePick = false,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !alreadyAdded,
      selected: selected,
      label:
          '${result.name}${showCategory ? ', ${result.category}' : ''}'
          '${alreadyAdded ? ', already added' : (singlePick ? '' : (selected ? ', selected' : ', not selected'))}',
      child: InkWell(
        onTap: alreadyAdded ? null : onTap,
        borderRadius: AppRadius.button,
        child: Container(
          constraints: const BoxConstraints(minHeight: 56),
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: selected ? accentFillColor(context).withAlpha(28) : null,
            borderRadius: AppRadius.button,
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      result.name,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (showCategory) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        result.category,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              if (alreadyAdded)
                Text(
                  'Added',
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: textSecondaryColor(context),
                  ),
                )
              else if (!singlePick)
                Checkbox(
                  value: selected,
                  onChanged: (_) => onTap(),
                  activeColor: accentFillColor(context),
                  checkColor: onAccentColor(context),
                  shape: const RoundedRectangleBorder(
                    borderRadius: AppRadius.badge,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String title;
  final String body;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _EmptyState({
    required this.title,
    required this.body,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Center(
        child: Column(
          children: [
            const SizedBox(height: AppSpacing.xl),
            Icon(
              LucideIcons.searchX,
              size: 28,
              color: textSecondaryColor(context),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              body,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}

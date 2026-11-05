import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../services/supabase_service.dart';
import '../data/exercise_library.dart';
import '../models/exercise_definition.dart';
import '../services/exercise_catalog.dart';
import '../services/sync_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'app_header.dart';
import 'muscle_group_illustration.dart';

void showExercisePickerSheet(
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
  navigator.push(
    _ExercisePickerRoute(
      capturedThemes: InheritedTheme.capture(
        from: context,
        to: navigator.context,
      ),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
      backgroundColor: surfaceColor(context),
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

/// Outside taps explicitly close the picker, like Close and dragging it down.
/// Only system Back follows the internal muscle-group navigation.
class _ExercisePickerRoute extends ModalBottomSheetRoute<void> {
  _ExercisePickerRoute({
    required super.builder,
    required super.capturedThemes,
    required super.barrierLabel,
    required super.backgroundColor,
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

    await showDialog<void>(
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
                          border: const OutlineInputBorder(
                            borderRadius: AppRadius.field,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.field,
                            borderSide: BorderSide(color: borderColor(context)),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadius.field,
                            borderSide: BorderSide(color: accentColor(context)),
                          ),
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
      child: AnimatedPadding(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        padding: EdgeInsets.only(bottom: keyboardInset),
        child: SafeArea(
          top: false,
          child: SizedBox(
            height: availableHeight * 0.92,
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
                _buildFooter(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Add exercises',
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
    );
  }

  Widget _buildContent() {
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
    final useSingleColumn =
        media.size.width < 360 || media.textScaler.scale(16) >= 22;
    final categories = [
      ...ExerciseLibrary.categoryNames,
      ...ExerciseCatalog.active
          .map((d) => d.category)
          .where((c) => !ExerciseLibrary.categoryNames.contains(c))
          .toSet(),
    ];
    final columns = useSingleColumn ? 1 : 2;
    Widget tile(String category) => _MuscleGroupTile(
      category: category,
      count: _inCategory(category).length,
      selectedCount: _selectedIn(category),
      showChevron: useSingleColumn,
      onTap: () => _openCategory(category),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContextBar(title: 'Muscle groups', trailing: _customAction),
        Expanded(
          // Rows sized by their content rather than a fixed aspect ratio, so
          // larger text grows a tile instead of clipping its label.
          child: ListView(
            key: const ValueKey('muscle-group-grid'),
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.xs,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            children: [
              for (var start = 0; start < categories.length; start += columns)
                Padding(
                  padding: EdgeInsets.only(top: start == 0 ? 0 : AppSpacing.sm),
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        for (var i = start; i < start + columns; i++) ...[
                          if (i > start) const SizedBox(width: AppSpacing.sm),
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
    final compact = media.size.width < 360 || media.textScaler.scale(16) >= 22;
    final selected = OutlinedButton(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size.fromHeight(48),
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.button),
      ),
      onPressed: _showSelected,
      child: Text('Selected (${_selectedNames.length})'),
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
        border: Border(top: BorderSide(color: borderColor(context))),
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
        border: const OutlineInputBorder(borderRadius: AppRadius.field),
        enabledBorder: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide(color: borderColor(context)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: AppRadius.field,
          borderSide: BorderSide(color: accentColor(context)),
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
    final compact = media.size.width < 360 || media.textScaler.scale(16) >= 22;
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
  final Widget? trailing;

  const _ContextBar({
    required this.title,
    this.subtitle,
    this.backTooltip,
    this.onBack,
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

class _MuscleGroupTile extends StatelessWidget {
  final String category;
  final int count;
  final int selectedCount;
  final bool showChevron;
  final VoidCallback onTap;

  const _MuscleGroupTile({
    required this.category,
    required this.count,
    required this.selectedCount,
    required this.showChevron,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    final secondary = textSecondaryColor(context);
    final hasSelection = selectedCount > 0;
    return Semantics(
      button: true,
      label:
          hasSelection
              ? '$category, $count exercises, $selectedCount selected'
              : '$category, $count exercises',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        color: surfaceColor(context),
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: hasSelection ? accentColor(context) : borderColor(context),
          ),
          borderRadius: AppRadius.card,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Row(
              children: [
                SizedBox(
                  width: 34,
                  height: 40,
                  child: MuscleGroupIllustration(
                    group: category,
                    silhouetteColor: secondary.withValues(alpha: 0.28),
                    highlightColor: accentColor(context),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(category, style: textTheme.titleMedium),
                      const SizedBox(height: AppSpacing.xxs),
                      Text(
                        hasSelection
                            ? '$selectedCount of $count selected'
                            : '$count exercises',
                        style: textTheme.bodySmall?.copyWith(
                          color:
                              hasSelection ? accentColor(context) : secondary,
                          fontWeight: hasSelection ? FontWeight.w600 : null,
                        ),
                      ),
                    ],
                  ),
                ),
                if (showChevron)
                  Icon(LucideIcons.chevronRight, size: 18, color: secondary),
              ],
            ),
          ),
        ),
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

  const _ExerciseList({
    required this.results,
    required this.selectedNames,
    required this.alreadyAddedNames,
    required this.onToggle,
    required this.showCategory,
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
            color: borderColor(context),
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
  final VoidCallback onTap;

  const _ExerciseRow({
    required this.result,
    required this.selected,
    required this.alreadyAdded,
    required this.showCategory,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: !alreadyAdded,
      selected: selected,
      label:
          '${result.name}${showCategory ? ', ${result.category}' : ''}, ${alreadyAdded ? 'already added' : (selected ? 'selected' : 'not selected')}',
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
              else
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

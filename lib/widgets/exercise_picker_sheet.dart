import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/exercise_library.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';
import 'muscle_group_illustration.dart';

void showExercisePickerSheet(
  BuildContext context, {
  required Iterable<String> selectedExerciseNames,
  Iterable<String> alreadyAddedExerciseNames = const <String>[],
  required void Function(String name) onAdd,
  required void Function(String name) onRemove,
  String selectionOwner = 'workout',
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: surfaceColor(context),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    isScrollControlled: true,
    builder:
        (sheetContext) => _ExercisePickerSheet(
          selectedExerciseNames: selectedExerciseNames,
          alreadyAddedExerciseNames: alreadyAddedExerciseNames,
          onAdd: onAdd,
          onRemove: onRemove,
          selectionOwner: selectionOwner,
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

  const _ExercisePickerSheet({
    required this.selectedExerciseNames,
    required this.alreadyAddedExerciseNames,
    required this.onAdd,
    required this.onRemove,
    required this.selectionOwner,
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
    for (final name in widget.alreadyAddedExerciseNames) {
      _alreadyAddedNames.add(_key(name));
    }
    for (final name in widget.selectedExerciseNames) {
      final key = _key(name);
      if (!_alreadyAddedNames.contains(key)) {
        _selectedNames.putIfAbsent(key, () => name);
      }
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  String _key(String name) => name.trim().toLowerCase();

  void _toggleExercise(String name) {
    final key = _key(name);
    if (_alreadyAddedNames.contains(key)) return;
    final selectedName = _selectedNames.remove(key);
    if (selectedName != null) {
      widget.onRemove(selectedName);
    } else {
      _selectedNames[key] = name;
      widget.onAdd(name);
    }
    setState(() {});
  }

  void _addCustomExercise(String name) {
    final key = _key(name);
    if (_selectedNames.containsKey(key) || _alreadyAddedNames.contains(key)) {
      return;
    }
    _selectedNames[key] = name;
    widget.onAdd(name);
    setState(() {});
  }

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

  void _showSelected() {
    setState(() {
      _searchController.clear();
      _query = '';
      _view = _PickerView.selected;
    });
  }

  List<_ExerciseResult> get _searchResults {
    final normalizedQuery = _key(_query);
    if (normalizedQuery.isEmpty) return const [];
    return [
      for (final entry in ExerciseLibrary.exercisesByCategory.entries)
        for (final name in entry.value)
          if (name.toLowerCase().contains(normalizedQuery))
            _ExerciseResult(name: name, category: entry.key),
    ];
  }

  String? _categoryFor(String name) {
    final key = _key(name);
    for (final entry in ExerciseLibrary.exercisesByCategory.entries) {
      if (entry.value.any((exercise) => _key(exercise) == key)) {
        return entry.key;
      }
    }
    return null;
  }

  Future<void> _createCustomExercise({String initialName = ''}) async {
    String inputText = initialName;
    String? errorText;
    if (initialName.trim().isNotEmpty &&
        (_selectedNames.containsKey(_key(initialName)) ||
            _alreadyAddedNames.contains(_key(initialName)))) {
      errorText = 'Exercise with this name already exists';
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final input = inputText.trim();
            final valid = input.isNotEmpty && errorText == null;
            return AlertDialog(
              backgroundColor: surfaceColor(context),
              shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
              title: Text(
                'Create custom exercise',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              content: TextFormField(
                initialValue: initialName,
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
                    } else if (_selectedNames.containsKey(_key(trimmed)) ||
                        _alreadyAddedNames.contains(_key(trimmed))) {
                      errorText = 'Exercise with this name already exists';
                    } else {
                      errorText = null;
                    }
                  });
                },
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('Cancel'),
                ),
                TextButton(
                  onPressed:
                      valid
                          ? () {
                            final name = inputText.trim();
                            Navigator.pop(dialogContext);
                            _addCustomExercise(name);
                          }
                          : null,
                  child: const Text('Create'),
                ),
              ],
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

    return AnimatedPadding(
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
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: _SearchField(
                  controller: _searchController,
                  onChanged: (value) => setState(() => _query = value),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.xs,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: _SecondaryAction(
                  label: 'Create custom exercise',
                  icon: LucideIcons.plus,
                  onTap: _createCustomExercise,
                ),
              ),
              Expanded(child: _buildContent()),
              _buildFooter(),
            ],
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

  Widget _buildGroupGrid() {
    final media = MediaQuery.of(context);
    final useSingleColumn =
        media.size.width < 360 || media.textScaler.scale(16) >= 22;
    return GridView.builder(
      key: const ValueKey('muscle-group-grid'),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.lg,
      ),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: useSingleColumn ? 1 : 2,
        crossAxisSpacing: AppSpacing.md,
        mainAxisSpacing: AppSpacing.md,
        childAspectRatio: useSingleColumn ? 3.1 : 0.9,
      ),
      itemCount: ExerciseLibrary.categoryNames.length,
      itemBuilder: (context, index) {
        final category = ExerciseLibrary.categoryNames[index];
        return _MuscleGroupTile(
          category: category,
          count: ExerciseLibrary.exercisesByCategory[category]!.length,
          horizontal: useSingleColumn,
          onTap: () => _openCategory(category),
        );
      },
    );
  }

  Widget _buildCategoryList() {
    final category = _selectedCategory!;
    final names = ExerciseLibrary.exercisesByCategory[category]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContentHeading(
          backLabel: 'Muscle groups',
          title: category,
          onBack: _showGroups,
        ),
        Expanded(
          child: _ExerciseList(
            results: [
              for (final name in names)
                _ExerciseResult(name: name, category: category),
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
        const _SectionLabel(label: 'Search results'),
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
      for (final name in _selectedNames.values)
        _ExerciseResult(name: name, category: _categoryFor(name) ?? 'Custom'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _ContentHeading(
          backLabel: 'Back',
          title: 'Selected exercises',
          onBack: _showGroups,
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
                Expanded(
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(48),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.button,
                      ),
                    ),
                    onPressed: _showSelected,
                    child: Text('Selected (${_selectedNames.length})'),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: accentFillColor(context),
                      foregroundColor: onAccentColor(context),
                      minimumSize: const Size.fromHeight(48),
                      shape: const RoundedRectangleBorder(
                        borderRadius: AppRadius.button,
                      ),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Done'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ExerciseResult {
  final String name;
  final String category;

  const _ExerciseResult({required this.name, required this.category});
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

class _SecondaryAction extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  const _SecondaryAction({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.button,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: accentColor(context)),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Text(
                label,
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(color: accentColor(context)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MuscleGroupTile extends StatelessWidget {
  final String category;
  final int count;
  final bool horizontal;
  final VoidCallback onTap;

  const _MuscleGroupTile({
    required this.category,
    required this.count,
    required this.horizontal,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final content = <Widget>[
      MuscleGroupIllustration(
        group: category,
        silhouetteColor: textSecondaryColor(context).withValues(alpha: 0.28),
        highlightColor: accentColor(context),
      ),
      SizedBox(
        width: horizontal ? AppSpacing.lg : 0,
        height: horizontal ? 0 : AppSpacing.sm,
      ),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment:
              horizontal ? CrossAxisAlignment.start : CrossAxisAlignment.center,
          children: [
            Text(
              category,
              textAlign: horizontal ? TextAlign.start : TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '$count exercises',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: textSecondaryColor(context),
              ),
            ),
          ],
        ),
      ),
      Icon(
        LucideIcons.chevronRight,
        size: 18,
        color: textSecondaryColor(context),
      ),
    ];

    return Semantics(
      button: true,
      label: '$category, $count exercises',
      child: Material(
        color: surfaceColor(context),
        shape: RoundedRectangleBorder(
          side: BorderSide(color: borderColor(context)),
          borderRadius: AppRadius.card,
        ),
        child: InkWell(
          onTap: onTap,
          borderRadius: AppRadius.card,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child:
                horizontal ? Row(children: content) : Column(children: content),
          ),
        ),
      ),
    );
  }
}

class _ContentHeading extends StatelessWidget {
  final String backLabel;
  final String title;
  final VoidCallback onBack;

  const _ContentHeading({
    required this.backLabel,
    required this.title,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.xxl,
        AppSpacing.xs,
      ),
      child: Row(
        children: [
          TextButton.icon(
            onPressed: onBack,
            icon: const Icon(LucideIcons.chevronLeft, size: 18),
            label: Text(backLabel),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              textAlign: TextAlign.end,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;

  const _SectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xs,
      ),
      child: Text(label, style: Theme.of(context).textTheme.titleMedium),
    );
  }
}

class _ExerciseList extends StatelessWidget {
  final List<_ExerciseResult> results;
  final Map<String, String> selectedNames;
  final Set<String> alreadyAddedNames;
  final ValueChanged<String> onToggle;
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
        final normalizedName = result.name.trim().toLowerCase();
        final selected = selectedNames.containsKey(normalizedName);
        final alreadyAdded = alreadyAddedNames.contains(normalizedName);
        return _ExerciseRow(
          result: result,
          selected: selected,
          alreadyAdded: alreadyAdded,
          showCategory: showCategory,
          onTap: () => onToggle(result.name),
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
            color: selected ? accentMutedColor(context) : null,
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

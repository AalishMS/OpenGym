import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/exercise_library.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../theme/spacing.dart';

void showExercisePickerSheet(
  BuildContext context, {
  required Iterable<String> selectedExerciseNames,
  required void Function(String name) onAdd,
  required void Function(String name) onRemove,
  String selectionOwner = 'workout',
}) {
  String selectedCategory = ExerciseLibrary.categoryNames.first;
  String query = '';
  final selectedNames =
      selectedExerciseNames.map((name) => name.toLowerCase()).toSet();

  showModalBottomSheet<void>(
    context: context,
    backgroundColor: surfaceColor(context),
    shape: const RoundedRectangleBorder(borderRadius: AppRadius.sheet),
    isScrollControlled: true,
    builder: (sheetContext) {
      return StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          final accent = accentColor(context);
          final source =
              query.trim().isEmpty
                  ? ExerciseLibrary.exercisesByCategory[selectedCategory] ?? []
                  : ExerciseLibrary.allExercises;
          final exercises =
              source
                  .where(
                    (name) =>
                        name.toLowerCase().contains(query.trim().toLowerCase()),
                  )
                  .toList();

          void addExercise(String name) {
            final normalizedName = name.toLowerCase();
            if (!selectedNames.add(normalizedName)) return;
            onAdd(name);
            setSheetState(() {});
          }

          void toggleExercise(String name) {
            final normalizedName = name.toLowerCase();
            if (selectedNames.remove(normalizedName)) {
              onRemove(name);
              setSheetState(() {});
              return;
            }
            addExercise(name);
          }

          return SafeArea(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.82,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: AppSpacing.sm),
                  Container(
                    width: 36,
                    height: 3,
                    decoration: BoxDecoration(
                      color: borderColor(context),
                      borderRadius: AppRadius.micro,
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      AppSpacing.md,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Expanded(
                              child: Text(
                                'ADD EXERCISES',
                                style: Theme.of(context).textTheme.headlineSmall
                                    ?.copyWith(letterSpacing: -0.3),
                              ),
                            ),
                            _SelectionCount(count: selectedNames.length),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.xs),
                        Text(
                          'Tap an exercise to add or remove it from the $selectionOwner.',
                          style: Theme.of(
                            context,
                          ).textTheme.bodySmall?.copyWith(height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                    ),
                    child: _SearchField(
                      onChanged: (value) => setSheetState(() => query = value),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (query.trim().isEmpty)
                    SizedBox(
                      height: 48,
                      child: ListView(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.lg,
                        ),
                        children:
                            ExerciseLibrary.categoryNames.map((category) {
                              final active = category == selectedCategory;
                              return Padding(
                                padding: const EdgeInsets.only(
                                  right: AppSpacing.sm,
                                ),
                                child: Semantics(
                                  label: category,
                                  selected: active,
                                  button: true,
                                  onTap:
                                      () => setSheetState(
                                        () => selectedCategory = category,
                                      ),
                                  child: InkWell(
                                    onTap:
                                        () => setSheetState(
                                          () => selectedCategory = category,
                                        ),
                                    borderRadius: AppRadius.chip,
                                    child: SizedBox(
                                      height: 48,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: AppSpacing.md,
                                            vertical: AppSpacing.xs,
                                          ),
                                          decoration: BoxDecoration(
                                            color:
                                                active
                                                    ? accentFillColor(context)
                                                    : backgroundColor(context),
                                            border: Border.all(
                                              color:
                                                  active
                                                      ? accentFillColor(context)
                                                      : borderColor(context),
                                            ),
                                            borderRadius: AppRadius.chip,
                                          ),
                                          child: Text(
                                            category,
                                            style: Theme.of(
                                              context,
                                            ).textTheme.labelSmall?.copyWith(
                                              fontWeight: FontWeight.bold,
                                              color:
                                                  active
                                                      ? onAccentColor(context)
                                                      : textSecondaryColor(
                                                        context,
                                                      ),
                                              letterSpacing: 0.06,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              );
                            }).toList(),
                      ),
                    ),
                  const SizedBox(height: AppSpacing.md),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        0,
                        AppSpacing.lg,
                        AppSpacing.lg,
                      ),
                      itemCount: exercises.length + 1,
                      separatorBuilder:
                          (context, index) =>
                              const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, index) {
                        if (index == 0) {
                          return _ExercisePickTile(
                            label: 'CUSTOM EXERCISE',
                            accent: accent,
                            isCustom: true,
                            onTap:
                                () => _showCustomExerciseDialog(
                                  sheetContext,
                                  selectedNames,
                                  addExercise,
                                ),
                          );
                        }

                        final name = exercises[index - 1];
                        final added = selectedNames.contains(
                          name.toLowerCase(),
                        );
                        return _ExercisePickTile(
                          label: name,
                          accent: accent,
                          added: added,
                          onTap: () => toggleExercise(name),
                        );
                      },
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.lg,
                      0,
                      AppSpacing.lg,
                      AppSpacing.lg,
                    ),
                    child: _DoneButton(
                      accent: accent,
                      onTap: () => Navigator.pop(sheetContext),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      );
    },
  );
}

void _showCustomExerciseDialog(
  BuildContext context,
  Set<String> selectedNames,
  void Function(String name) onAdd,
) {
  String inputText = '';
  String? errorText;

  showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          final valid = inputText.trim().isNotEmpty && errorText == null;
          return AlertDialog(
            backgroundColor: surfaceColor(context),
            shape: const RoundedRectangleBorder(borderRadius: AppRadius.card),
            title: Text(
              '> CUSTOM EXERCISE',
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: textPrimaryColor(context),
                letterSpacing: 0.06,
              ),
            ),
            content: TextField(
              autofocus: true,
              textCapitalization: TextCapitalization.words,
              style: Theme.of(
                context,
              ).textTheme.bodyLarge?.copyWith(color: textPrimaryColor(context)),
              decoration: InputDecoration(
                hintText: 'Enter exercise name',
                hintStyle: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  color: textSecondaryColor(context),
                ),
                errorText: errorText,
                errorStyle: GoogleFonts.jetBrainsMono(
                  fontSize: 9,
                  color: errorColor(context),
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                errorBorder: InputBorder.none,
              ),
              onChanged: (value) {
                setDialogState(() {
                  inputText = value;
                  final trimmed = value.trim();
                  if (trimmed.isEmpty) {
                    errorText = 'Name cannot be empty';
                  } else if (selectedNames.contains(trimmed.toLowerCase())) {
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
                child: Text(
                  'Cancel',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color: textSecondaryColor(context),
                  ),
                ),
              ),
              TextButton(
                onPressed:
                    valid
                        ? () {
                          final name = inputText.trim();
                          Navigator.pop(dialogContext);
                          onAdd(name);
                        }
                        : null,
                child: Text(
                  'Confirm',
                  style: GoogleFonts.jetBrainsMono(
                    fontSize: 11,
                    color:
                        valid
                            ? accentColor(context)
                            : textSecondaryColor(context).withAlpha(96),
                  ),
                ),
              ),
            ],
          );
        },
      );
    },
  );
}

class _SearchField extends StatelessWidget {
  final ValueChanged<String> onChanged;

  const _SearchField({required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return TextField(
      onChanged: onChanged,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: 'Search by exercise name',
        prefixIcon: const Icon(LucideIcons.search, size: 18),
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

class _SelectionCount extends StatelessWidget {
  final int count;

  const _SelectionCount({required this.count});

  @override
  Widget build(BuildContext context) {
    final accent = accentColor(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: backgroundColor(context),
        border: Border.all(color: accent),
        borderRadius: AppRadius.badge,
      ),
      child: Text(
        '$count SELECTED',
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
          color: accent,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _ExercisePickTile extends StatelessWidget {
  final String label;
  final Color accent;
  final bool added;
  final bool isCustom;
  final VoidCallback? onTap;

  const _ExercisePickTile({
    required this.label,
    required this.accent,
    this.added = false,
    this.isCustom = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accentFill = accentFillColor(context);
    final statusLabel = added ? 'REMOVE' : (isCustom ? 'CREATE' : 'ADD');

    return Semantics(
      button: true,
      selected: added,
      label: '$label, $statusLabel',
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        splashColor: accent.withValues(alpha: 0.2),
        highlightColor: accent.withValues(alpha: 0.1),
        child: Container(
          constraints: const BoxConstraints(minHeight: 54),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
          decoration: BoxDecoration(
            color: backgroundColor(context),
            border: Border.all(
              color: added ? accent : borderColor(context),
              width: added ? 1.5 : 1,
            ),
            borderRadius: AppRadius.button,
          ),
          child: Row(
            children: [
              Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: added ? accentFill : surfaceColor(context),
                  border: Border.all(
                    color: added ? accentFill : borderColor(context),
                  ),
                  borderRadius: AppRadius.control,
                ),
                child: Icon(
                  added ? LucideIcons.check : LucideIcons.plus,
                  size: 14,
                  color:
                      added
                          ? onAccentColor(context)
                          : (isCustom ? accent : textSecondaryColor(context)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: added ? FontWeight.bold : FontWeight.w600,
                    color: added ? accent : textPrimaryColor(context),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                statusLabel,
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: added ? accent : textSecondaryColor(context),
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.6,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DoneButton extends StatelessWidget {
  final Color accent;
  final VoidCallback onTap;

  const _DoneButton({required this.accent, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadius.button,
      child: Container(
        constraints: const BoxConstraints(minHeight: 48),
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 13),
        decoration: BoxDecoration(
          color: accentFillColor(context),
          border: Border.all(color: accent),
          borderRadius: AppRadius.button,
        ),
        child: Center(
          child: Text(
            'Done',
            style: Theme.of(
              context,
            ).textTheme.labelLarge?.copyWith(color: onAccentColor(context)),
          ),
        ),
      ),
    );
  }
}

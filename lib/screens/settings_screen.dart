import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/update_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/backup_service.dart';
import '../services/hive_service.dart';
import '../services/sample_data_seeder.dart';
import '../services/supabase_service.dart';
import '../services/update_service.dart';
import '../theme/app_theme.dart';
import '../theme/radii.dart';
import '../widgets/update_dialog.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({
    super.key,
    this.onClearData,
    this.onLoadSampleData,
    this.onSignOut,
  });

  final Future<void> Function()? onClearData;
  final Future<void> Function()? onLoadSampleData;
  final Future<void> Function()? onSignOut;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  void initState() {
    super.initState();
    // Needed for the VERSION line. Cheap, cached in the provider, and harmless
    // if it fails — the label falls back to an em dash.
    context.read<UpdateProvider>().loadInstalledVersion();
  }

  String _getAccentColorName(SettingsProvider settings) {
    return SettingsProvider.accents[settings.accentIndex].name;
  }

  String? _signedInEmail() {
    try {
      return SupabaseService.currentUser?.email;
    } catch (_) {
      return null;
    }
  }

  /// The tile's second line, which doubles as the result readout for a manual
  /// check — the outcome stays visible after the snackbar has gone.
  String _updateSubtitle(UpdateProvider updates) {
    if (!UpdateService.isSupportedPlatform) {
      return 'Only available on Android';
    }
    switch (updates.status) {
      case UpdateStatus.checking:
        return 'Checking GitHub...';
      case UpdateStatus.available:
        return '${updates.release?.displayVersion ?? 'A new version'} is ready';
      case UpdateStatus.upToDate:
        return "You're up to date";
      case UpdateStatus.downloading:
        return 'Downloading... ${(updates.progress * 100).round()}%';
      case UpdateStatus.installing:
        return 'Opening the installer...';
      case UpdateStatus.failed:
        return updates.error ?? 'Last check failed';
      case UpdateStatus.idle:
        return 'Check GitHub for a new release';
    }
  }

  Future<void> _handleUpdateCheck(
    BuildContext context,
    UpdateProvider updates,
  ) async {
    // Already found one, or already working — reopen the dialog rather than
    // starting a second check on top of the first.
    if (updates.isUpdateAvailable || updates.isBusy) {
      await showUpdateDialog(context);
      return;
    }
    if (updates.status == UpdateStatus.checking) return;

    try {
      await updates.checkManually();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Update check failed: $e');
      return;
    }
    if (!context.mounted) return;

    if (updates.isUpdateAvailable) {
      await showUpdateDialog(context);
      return;
    }

    // The user asked, so say something either way. Silence on a tapped button
    // reads as a bug.
    final failed = updates.status == UpdateStatus.failed;
    final ground = failed ? errorColor(context) : accentColor(context);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          failed
              ? '> ${updates.error ?? 'Update check failed'}'
              : "> You're up to date",
          style: GoogleFonts.jetBrainsMono(color: onColor(ground)),
        ),
        backgroundColor: ground,
      ),
    );
  }

  Future<void> _runSettingsAction(
    BuildContext context,
    Future<void> Function() action,
  ) async {
    try {
      await action();
    } catch (e) {
      if (!context.mounted) return;
      _showError(context, 'Settings action failed: $e');
    }
  }

  void _showError(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          '> $message',
          style: GoogleFonts.jetBrainsMono(color: onColor(errorColor(context))),
        ),
        backgroundColor: errorColor(context),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final updates = context.watch<UpdateProvider>();
    final accent = accentColor(context);
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        flexibleSpace: headerFlexibleSpace(context),
        title: Text(
          '> SETTINGS',
          style: GoogleFonts.jetBrainsMono(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: accent,
          ),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _SectionHeader(title: 'Appearance'),
                _buildThemeSection(context, settings),
                _buildAccentColorSection(context, settings),
                const _SectionHeader(title: 'Workout'),
                _buildSwitchTile(
                  context: context,
                  icon: LucideIcons.gauge,
                  title: 'High refresh rate',
                  subtitle: 'Enable 90/120 Hz display support',
                  value: settings.highRefreshRate,
                  onChanged:
                      (value) => _runSettingsAction(
                        context,
                        () => settings.setHighRefreshRate(value),
                      ),
                ),
                _buildSwitchTile(
                  context: context,
                  icon: LucideIcons.zap,
                  title: 'Auto-fill last weights',
                  subtitle: 'Automatically fill weight from previous workout',
                  value: settings.autoFillLast,
                  onChanged:
                      (value) => _runSettingsAction(
                        context,
                        () => settings.setAutoFillLast(value),
                      ),
                ),
                const _SectionHeader(title: 'Data'),
                _buildSettingsTile(
                  icon: LucideIcons.flaskConical,
                  title: 'Load sample data',
                  subtitle: 'Add sample plans and workouts for testing',
                  onTap: () => _loadSampleData(context),
                ),
                _buildSettingsTile(
                  icon: LucideIcons.upload,
                  title: 'Export data',
                  subtitle: 'Backup all plans, sessions, and settings',
                  onTap: () => _exportData(context),
                ),
                _buildSettingsTile(
                  icon: LucideIcons.download,
                  title: 'Import data',
                  subtitle: 'Restore from a backup file (replaces all data)',
                  onTap: () => _importData(context),
                ),
                const _SectionHeader(title: 'Danger zone'),
                _buildSettingsTile(
                  icon: LucideIcons.trash2,
                  title: 'Clear all data',
                  subtitle: 'Delete all plans and workout history',
                  onTap: () => _confirmClearData(context),
                  isDestructive: true,
                ),
                if (widget.onSignOut != null || _signedInEmail() != null)
                  _buildSettingsTile(
                    icon: LucideIcons.logOut,
                    title: 'Sign out',
                    subtitle:
                        widget.onSignOut != null
                            ? 'Sign out of OpenGym'
                            : _signedInEmail() ?? 'Signed in',
                    onTap: () async {
                      await _runSettingsAction(
                        context,
                        widget.onSignOut ?? SupabaseService.signOut,
                      );
                      // AuthGate reacts and shows LoginScreen automatically.
                    },
                  ),
                const _SectionHeader(title: 'Updates'),
                _buildSettingsTile(
                  icon: LucideIcons.download,
                  title: 'Check for updates',
                  subtitle: _updateSubtitle(updates),
                  onTap: () => _handleUpdateCheck(context, updates),
                  valueIsMono: true,
                ),
                const _SectionHeader(title: 'About'),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Version',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        updates.installedVersionLabel,
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 14,
                          color: textPrimaryColor(context),
                        ),
                      ),
                    ],
                  ),
                ),
                Text(
                  'Made by Aalish',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildThemeSection(BuildContext context, SettingsProvider settings) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Theme', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 4),
          Text(
            'Choose how OpenGym looks.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          Semantics(
            label: 'Theme',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark')),
                ButtonSegment(value: ThemeMode.light, label: Text('Light')),
                ButtonSegment(value: ThemeMode.system, label: Text('System')),
              ],
              selected: {settings.themeMode},
              onSelectionChanged:
                  (selection) => _runSettingsAction(
                    context,
                    () => settings.setThemeMode(selection.first),
                  ),
              multiSelectionEnabled: false,
              showSelectedIcon: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAccentColorSection(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final border = borderColor(context);
    final accent = accentColor(context);
    final textSecondary = textSecondaryColor(context);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Accent color',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _getAccentColorName(settings),
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              color: textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(SettingsProvider.accents.length, (index) {
              final option = SettingsProvider.accents[index];
              final isSelected = settings.accentIndex == index;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return _buildColorBox(
                option,
                isSelected,
                settings,
                isDark,
                border,
                textSecondary,
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildColorBox(
    AppAccent option,
    bool isSelected,
    SettingsProvider settings,
    bool isDark,
    Color border,
    Color textSecondary,
  ) {
    // One swatch, not two. The old box showed the hand-picked dark and light
    // hexes side by side; they differed by about a shade, so the pair read as
    // noise rather than as information. There is now a single tone per mode,
    // resolved through the same solver the theme uses, so this chip is exactly
    // the colour that selecting it will paint.
    final swatch = accentToneFor(
      option.seed,
      isDark ? Brightness.dark : Brightness.light,
    );

    return Semantics(
      label: '${option.name} accent',
      button: true,
      selected: isSelected,
      child: InkWell(
        key: ValueKey(
          'accent-swatch-${SettingsProvider.accents.indexOf(option)}',
        ),
        onTap:
            () => _runSettingsAction(
              context,
              () => settings.setAccentColor(
                SettingsProvider.accents.indexOf(option),
              ),
            ),
        borderRadius: AppRadius.button,
        child: Container(
          width: 64,
          height: 64,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color:
                isSelected ? accentMutedColor(context) : surfaceColor(context),
            border: Border.all(
              color: isSelected ? swatch : border,
              width: isSelected ? 2 : 1,
            ),
            borderRadius: AppRadius.button,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: swatch,
                  borderRadius: AppRadius.badge,
                ),
              ),
              if (isSelected)
                Icon(LucideIcons.check, size: 18, color: onColor(swatch)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      tileColor: backgroundColor(context),
      secondary: Icon(icon, color: accentColor(context), size: 20),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(subtitle),
      value: value,
      onChanged: onChanged,
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool isDestructive = false,
    bool valueIsMono = false,
  }) {
    final textColor =
        isDestructive ? errorColor(context) : textPrimaryColor(context);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadius.button,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: Row(
              children: [
                Icon(
                  icon,
                  color: isDestructive ? textColor : accentColor(context),
                  size: 20,
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: textColor),
                      ),
                      Text(
                        subtitle,
                        style:
                            valueIsMono
                                ? GoogleFonts.jetBrainsMono(
                                  fontSize: 11,
                                  color: textSecondaryColor(context),
                                )
                                : Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Icon(
                  LucideIcons.chevronRight,
                  color: textSecondaryColor(context),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _loadSampleData(BuildContext context) async {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final accent = accentColor(context);

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: border, width: 1),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> LOAD SAMPLE DATA?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This will clear all existing data and load fresh sample plans and workouts.',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      overflowSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondary,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              if (widget.onLoadSampleData != null) {
                                await widget.onLoadSampleData!();
                              } else {
                                await SampleDataSeeder.clearAllData();
                                await SampleDataSeeder.seedSampleData();
                              }
                            } catch (e) {
                              if (!context.mounted) return;
                              _showError(context, 'Sample data failed: $e');
                              return;
                            }
                            if (context.mounted) {
                              context.read<WorkoutPlanProvider>().loadPlans();
                              context
                                  .read<WorkoutSessionProvider>()
                                  .loadSessions();
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '> Sample data refreshed!',
                                    style: GoogleFonts.jetBrainsMono(
                                      color: onAccentColor(context),
                                    ),
                                  ),
                                  backgroundColor: accentFillColor(context),
                                ),
                              );
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            '[LOAD]',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _exportData(BuildContext context) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final settings = context.read<SettingsProvider>();
    final accent = accentColor(context);

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: border, width: 1),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> EXPORT DATA?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: accent,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This will create a backup file containing all your plans, '
                      'sessions, and settings. Your current data will NOT be affected.',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      overflowSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondary,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            Navigator.pop(ctx);
                            try {
                              final planProvider =
                                  context.read<WorkoutPlanProvider>();
                              final sessionProvider =
                                  context.read<WorkoutSessionProvider>();
                              final result = BackupService.exportData(
                                plans: planProvider.plans,
                                sessions: sessionProvider.sessions,
                                settings: {
                                  'themeMode': settings.themeMode.index,
                                  'accentIndex': settings.accentIndex,
                                  'weightUnit': settings.weightUnit,
                                  'autoFillLast': settings.autoFillLast,
                                  'highRefreshRate': settings.highRefreshRate,
                                },
                              );
                              final bytes = utf8.encode(result.jsonString);
                              await Share.shareXFiles([
                                XFile.fromData(
                                  bytes,
                                  name: result.fileName,
                                  mimeType: 'application/json',
                                ),
                              ], text: 'OpenGym Backup');
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '> Backup exported successfully',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: onAccentColor(context),
                                      ),
                                    ),
                                    backgroundColor: accentFillColor(context),
                                  ),
                                );
                              }
                            } catch (e) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      '> Export failed: ${e.toString()}',
                                      style: GoogleFonts.jetBrainsMono(
                                        color: onColor(errorColor(context)),
                                      ),
                                    ),
                                    backgroundColor: errorColor(context),
                                  ),
                                );
                              }
                            }
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: accentFillColor(context),
                            foregroundColor: onAccentColor(context),
                          ),
                          child: Text(
                            '[EXPORT]',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  void _importData(BuildContext context) async {
    try {
      final pickResult = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['json'],
      );
      if (!context.mounted) return;
      if (pickResult == null || pickResult.files.isEmpty) return;

      final pickedFile = pickResult.files.single;
      String jsonString;
      if (pickedFile.bytes != null) {
        jsonString = utf8.decode(pickedFile.bytes!);
      } else {
        jsonString = await File(pickedFile.path!).readAsString();
      }
      if (!context.mounted) return;

      final importResult = BackupService.importData(jsonString);
      if (!importResult.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                '> ${importResult.errorMessage}',
                style: GoogleFonts.jetBrainsMono(
                  color: onColor(errorColor(context)),
                ),
              ),
              backgroundColor: errorColor(context),
            ),
          );
        }
        return;
      }

      final settingsError = _validateImportedSettings(importResult.settings!);
      if (settingsError != null) {
        _showError(context, settingsError);
        return;
      }

      final surface = surfaceColor(context);
      final border = borderColor(context);
      final textSecondary = textSecondaryColor(context);
      final error = errorColor(context);
      final settings = context.read<SettingsProvider>();

      showDialog(
        context: context,
        builder:
            (ctx) => Dialog(
              backgroundColor: surface,
              shape: RoundedRectangleBorder(
                borderRadius: AppRadius.card,
                side: BorderSide(color: border, width: 1),
              ),
              child: SingleChildScrollView(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '> IMPORT BACKUP?',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: error,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'This will REPLACE ALL of your current data including:\n'
                        '• All workout plans\n'
                        '• All workout history\n'
                        '• App settings (theme, accent color, units)\n\n'
                        'This action cannot be undone.',
                        style: GoogleFonts.jetBrainsMono(
                          fontSize: 12,
                          color: textSecondary,
                        ),
                      ),
                      const SizedBox(height: 16),
                      OverflowBar(
                        alignment: MainAxisAlignment.end,
                        spacing: 8,
                        overflowAlignment: OverflowBarAlignment.end,
                        overflowSpacing: 8,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: Text(
                              '[CANCEL]',
                              style: GoogleFonts.jetBrainsMono(
                                color: textSecondary,
                              ),
                            ),
                          ),
                          ElevatedButton(
                            onPressed: () async {
                              Navigator.pop(ctx);
                              final planProvider =
                                  context.read<WorkoutPlanProvider>();
                              final sessionProvider =
                                  context.read<WorkoutSessionProvider>();
                              try {
                                await HiveService.replaceAllPlans(
                                  importResult.plans!,
                                );
                                await HiveService.replaceAllSessions(
                                  importResult.sessions!,
                                );
                                if (!context.mounted) return;
                                final s = importResult.settings!;
                                await settings.setThemeMode(
                                  ThemeMode.values[s['themeMode'] as int],
                                );
                                await settings.setAccentColor(
                                  s['accentIndex'] as int,
                                );
                                await settings.setWeightUnit(
                                  s['weightUnit'] as String,
                                );
                                await settings.setAutoFillLast(
                                  s['autoFillLast'] as bool,
                                );
                                await settings.setHighRefreshRate(
                                  s['highRefreshRate'] as bool,
                                );
                                if (!context.mounted) return;
                                planProvider.loadPlans();
                                sessionProvider.loadSessions();
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '> Backup imported successfully',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: onAccentColor(context),
                                        ),
                                      ),
                                      backgroundColor: accentFillColor(context),
                                    ),
                                  );
                                }
                              } catch (e) {
                                if (context.mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        '> Import failed: ${e.toString()}',
                                        style: GoogleFonts.jetBrainsMono(
                                          color: onColor(error),
                                        ),
                                      ),
                                      backgroundColor: error,
                                    ),
                                  );
                                }
                              }
                            },
                            style: ElevatedButton.styleFrom(
                              backgroundColor: error,
                              foregroundColor: onColor(error),
                            ),
                            child: Text(
                              '[IMPORT]',
                              style: GoogleFonts.jetBrainsMono(),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '> Import failed: ${e.toString()}',
              style: GoogleFonts.jetBrainsMono(
                color: onColor(errorColor(context)),
              ),
            ),
            backgroundColor: errorColor(context),
          ),
        );
      }
    }
  }

  void _confirmClearData(BuildContext context) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final error = errorColor(context);

    showDialog(
      context: context,
      builder:
          (ctx) => Dialog(
            backgroundColor: surface,
            shape: RoundedRectangleBorder(
              borderRadius: AppRadius.card,
              side: BorderSide(color: border, width: 1),
            ),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '> CLEAR ALL DATA?',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: error,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'This will delete all workout plans and history. This action cannot be undone.',
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        color: textSecondary,
                      ),
                    ),
                    const SizedBox(height: 16),
                    OverflowBar(
                      alignment: MainAxisAlignment.end,
                      spacing: 8,
                      overflowAlignment: OverflowBarAlignment.end,
                      overflowSpacing: 8,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.pop(ctx),
                          child: Text(
                            '[CANCEL]',
                            style: GoogleFonts.jetBrainsMono(
                              color: textSecondary,
                            ),
                          ),
                        ),
                        ElevatedButton(
                          onPressed: () async {
                            try {
                              await (widget.onClearData ??
                                  SampleDataSeeder.clearAllData)();
                            } catch (e) {
                              if (!context.mounted) return;
                              if (ctx.mounted) Navigator.pop(ctx);
                              _showError(context, 'Clear data failed: $e');
                              return;
                            }
                            if (!context.mounted) return;
                            if (ctx.mounted) Navigator.pop(ctx);
                            context.read<WorkoutPlanProvider>().loadPlans();
                            context
                                .read<WorkoutSessionProvider>()
                                .loadSessions();
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '> All data cleared',
                                  style: GoogleFonts.jetBrainsMono(
                                    color: onAccentColor(context),
                                  ),
                                ),
                                backgroundColor: accentFillColor(context),
                              ),
                            );
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: error,
                            foregroundColor: onColor(error),
                          ),
                          child: Text(
                            '[CLEAR ALL]',
                            style: GoogleFonts.jetBrainsMono(),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
    );
  }

  String? _validateImportedSettings(Map<String, dynamic> settings) {
    final themeMode = settings['themeMode'];
    final accentIndex = settings['accentIndex'];
    final weightUnit = settings['weightUnit'];
    final autoFillLast = settings['autoFillLast'];
    final highRefreshRate = settings['highRefreshRate'];
    if (themeMode is! int ||
        themeMode < 0 ||
        themeMode >= ThemeMode.values.length ||
        accentIndex is! int ||
        accentIndex < 0 ||
        accentIndex >= SettingsProvider.accents.length ||
        weightUnit is! String ||
        (weightUnit != 'kg' && weightUnit != 'lbs') ||
        autoFillLast is! bool ||
        highRefreshRate is! bool) {
      return 'Invalid settings in backup';
    }
    return null;
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24, bottom: 8),
      child: Text(title, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

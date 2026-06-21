import 'dart:convert';
import 'dart:io' show File;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:share_plus/share_plus.dart';

import '../providers/settings_provider.dart';
import '../providers/workout_plan_provider.dart';
import '../providers/workout_session_provider.dart';
import '../services/backup_service.dart';
import '../services/hive_service.dart';
import '../services/sample_data_seeder.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  String _getAccentColorName(SettingsProvider settings) {
    return SettingsProvider.accents[settings.accentIndex].name;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final accent = settings.accentColor;
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final textPrimary = textPrimaryColor(context);
    final error = errorColor(context);

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: surface,
        title: Text(
          '> SETTINGS',
          style: GoogleFonts.jetBrainsMono(
              fontSize: 16, fontWeight: FontWeight.bold, color: accent),
        ),
        automaticallyImplyLeading: false,
      ),
      body: Consumer<SettingsProvider>(
        builder: (context, settings, child) {
          return ListView(
            children: [
              _SectionHeader(
                  title: 'APPEARANCE', accent: accent, border: border),
              _buildThemeSection(context, settings, accent),
              _buildAccentColorSection(
                  context, settings, accent, textSecondary),
              Divider(color: border),
              _SectionHeader(title: 'WORKOUT', accent: accent, border: border),
              _buildSwitchTile(
                icon: Icons.speed,
                title: 'HIGH REFRESH RATE',
                subtitle: 'Enable 90/120Hz display support',
                value: settings.highRefreshRate,
                onChanged: (value) => settings.setHighRefreshRate(value),
                accent: accent,
                textSecondary: textSecondary,
                border: border,
                textPrimary: textPrimary,
              ),
              _buildSwitchTile(
                icon: Icons.bolt,
                title: 'AUTO-FILL LAST WEIGHTS',
                subtitle: 'Automatically fill weight from previous workout',
                value: settings.autoFillLast,
                onChanged: (value) => settings.setAutoFillLast(value),
                accent: accent,
                textSecondary: textSecondary,
                border: border,
                textPrimary: textPrimary,
              ),
              Divider(color: border),
              _SectionHeader(title: 'UNITS', accent: accent, border: border),
              _buildSettingsTile(
                icon: Icons.fitness_center,
                title: 'WEIGHT UNIT',
                subtitle: settings.weightUnit == 'kg'
                    ? 'KILOGRAMS (KG)'
                    : 'POUNDS (LBS)',
                onTap: () => _showWeightUnitDialog(context, settings),
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                border: border,
              ),
              Divider(color: border),
              _SectionHeader(title: 'DATA', accent: accent, border: border),
              _buildSettingsTile(
                icon: Icons.download,
                title: 'LOAD SAMPLE DATA',
                subtitle: 'Add sample plans and workouts for testing',
                onTap: () => _loadSampleData(context),
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                border: border,
              ),
              _buildSettingsTile(
                icon: Icons.upload,
                title: 'EXPORT DATA',
                subtitle: 'Backup all plans, sessions, and settings',
                onTap: () => _exportData(context),
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                border: border,
              ),
              _buildSettingsTile(
                icon: Icons.download,
                title: 'IMPORT DATA',
                subtitle: 'Restore from a backup file (replaces all data)',
                onTap: () => _importData(context),
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                border: border,
              ),
              _buildSettingsTile(
                icon: Icons.delete_forever,
                title: 'CLEAR ALL DATA',
                subtitle: 'Delete all plans and workout history',
                onTap: () => _confirmClearData(context),
                isDestructive: true,
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
                error: error,
                border: border,
              ),
              Divider(color: border),
              _SectionHeader(title: 'ABOUT', accent: accent, border: border),
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Text(
                      'VERSION',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: textSecondary),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '1.0.0',
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 14, color: textPrimary),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              Center(
                child: Text(
                  '> Made by Aalish',
                  style: GoogleFonts.jetBrainsMono(
                    color: textSecondary,
                    fontSize: 12,
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
          );
        },
      ),
    );
  }

  Widget _buildThemeSection(
      BuildContext context, SettingsProvider settings, Color accent) {
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final textPrimary = textPrimaryColor(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'THEME',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 12, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            '> ${_getThemeName(settings.themeMode)}',
            style:
                GoogleFonts.jetBrainsMono(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              _buildThemeOption(
                context: context,
                mode: ThemeMode.dark,
                icon: Icons.dark_mode,
                label: 'DARK',
                isSelected: settings.themeMode == ThemeMode.dark,
                settings: settings,
                accent: accent,
                textSecondary: textSecondary,
                textPrimary: textPrimary,
              ),
              const SizedBox(width: 8),
              _buildThemeOption(
                context: context,
                mode: ThemeMode.light,
                icon: Icons.light_mode,
                label: 'LIGHT',
                isSelected: settings.themeMode == ThemeMode.light,
                settings: settings,
                accent: accent,
                textSecondary: textSecondary,
                textPrimary: textPrimary,
              ),
              const SizedBox(width: 8),
              _buildThemeOption(
                context: context,
                mode: ThemeMode.system,
                icon: Icons.brightness_auto,
                label: 'SYSTEM',
                isSelected: settings.themeMode == ThemeMode.system,
                settings: settings,
                accent: accent,
                textSecondary: textSecondary,
                textPrimary: textPrimary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildThemeOption({
    required BuildContext context,
    required ThemeMode mode,
    required IconData icon,
    required String label,
    required bool isSelected,
    required SettingsProvider settings,
    required Color accent,
    required Color textSecondary,
    required Color textPrimary,
  }) {
    final border = borderColor(context);

    return Expanded(
      child: InkWell(
        onTap: () => settings.setThemeMode(mode),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(25) : Colors.transparent,
            border: Border.all(
              color: isSelected ? accent : border,
              width: isSelected ? 2 : 1,
            ),
          ),
          child: Column(
            children: [
              Icon(
                icon,
                size: 20,
                color: isSelected ? accent : textSecondary,
              ),
              const SizedBox(height: 4),
              Text(
                label,
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? accent : textSecondary,
                ),
              ),
              if (isSelected) ...[
                const SizedBox(height: 2),
                Icon(Icons.check, size: 12, color: accent),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _getThemeName(ThemeMode mode) {
    switch (mode) {
      case ThemeMode.dark:
        return 'DARK';
      case ThemeMode.light:
        return 'LIGHT';
      case ThemeMode.system:
        return 'SYSTEM';
    }
  }

  Widget _buildAccentColorSection(BuildContext context,
      SettingsProvider settings, Color accent, Color textSecondary) {
    final border = borderColor(context);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ACCENT COLOR',
            style: GoogleFonts.jetBrainsMono(
                fontSize: 12, fontWeight: FontWeight.bold, color: accent),
          ),
          const SizedBox(height: 8),
          Text(
            '> ${_getAccentColorName(settings)}',
            style:
                GoogleFonts.jetBrainsMono(fontSize: 10, color: textSecondary),
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(SettingsProvider.accents.length, (index) {
              final option = SettingsProvider.accents[index];
              final isSelected = settings.accentIndex == index;
              final isDark = Theme.of(context).brightness == Brightness.dark;
              return _buildColorBox(option, isSelected, settings, accent,
                  isDark, border, textSecondary);
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
      Color currentAccent,
      bool isDark,
      Color border,
      Color textSecondary) {
    final accentToShow = isDark ? option.dark : option.light;
    final isLight = accentToShow.computeLuminance() > 0.5;

    return InkWell(
      onTap: () {
        settings.setAccentColor(SettingsProvider.accents.indexOf(option));
      },
      child: Container(
        width: 100,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected ? accentToShow.withAlpha(38) : Colors.transparent,
          border: Border.all(
            color: isSelected ? accentToShow : border,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Column(
          children: [
            Text(
              option.name,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                color: isSelected ? accentToShow : textSecondary,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: option.dark,
                    border: Border.all(
                      color: isSelected
                          ? (isLight ? Colors.black : Colors.white)
                          : border,
                      width: isSelected ? 1 : 1,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: option.light,
                    border: Border.all(
                      color: isSelected
                          ? (option.light.computeLuminance() > 0.5
                              ? Colors.black
                              : Colors.white)
                          : border,
                      width: isSelected ? 1 : 1,
                    ),
                  ),
                ),
                if (isSelected)
                  const Padding(
                    padding: EdgeInsets.only(left: 2),
                    child: Icon(Icons.check, size: 12, color: Colors.white),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
    required Color accent,
    required Color textSecondary,
    required Color border,
    required Color textPrimary,
  }) {
    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: SwitchListTile(
        secondary: Icon(icon, color: accent, size: 20),
        title: Text(title,
            style: GoogleFonts.jetBrainsMono(
                fontSize: 12, fontWeight: FontWeight.bold)),
        subtitle: Text(subtitle,
            style:
                GoogleFonts.jetBrainsMono(fontSize: 10, color: textSecondary)),
        value: value,
        onChanged: onChanged,
      ),
    );
  }

  Widget _buildSettingsTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
    required Color border,
    Color? error,
    bool isDestructive = false,
  }) {
    final textColor = isDestructive ? (error ?? error) : textPrimary;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        splashColor: accent.withAlpha(25),
        highlightColor: accent.withAlpha(13),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: border, width: 1)),
          ),
          child: Row(
            children: [
              Icon(icon,
                  color: isDestructive ? (error ?? error) : accent, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.jetBrainsMono(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: textColor,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.jetBrainsMono(
                          fontSize: 10, color: textSecondary),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: textSecondary, size: 20),
            ],
          ),
        ),
      ),
    );
  }

  void _loadSampleData(BuildContext context) async {
    final settings = context.read<SettingsProvider>();
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final accent = settings.accentColor;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> LOAD SAMPLE DATA?',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16, fontWeight: FontWeight.bold, color: accent),
              ),
              const SizedBox(height: 16),
              Text(
                'This will clear all existing data and load fresh sample plans and workouts.',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(color: textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      Navigator.pop(ctx);
                      await SampleDataSeeder.clearAllData();
                      await SampleDataSeeder.seedSampleData();
                      if (context.mounted) {
                        context.read<WorkoutPlanProvider>().loadPlans();
                        context.read<WorkoutSessionProvider>().loadSessions();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('> Sample data refreshed!',
                                style: GoogleFonts.jetBrainsMono()),
                            backgroundColor: accent,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child: Text('[LOAD]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
    final accent = settings.accentColor;

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
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
                    color: accent),
              ),
              const SizedBox(height: 16),
              Text(
                'This will create a backup file containing all your plans, '
                'sessions, and settings. Your current data will NOT be affected.',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('[CANCEL]',
                        style:
                            GoogleFonts.jetBrainsMono(color: textSecondary)),
                  ),
                  const SizedBox(width: 8),
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
                        final bytes =
                            utf8.encode(result.jsonString);
                        await Share.shareXFiles(
                          [
                            XFile.fromData(
                              bytes,
                              name: result.fileName,
                              mimeType: 'application/json',
                            ),
                          ],
                          text: 'OpenGym Backup',
                        );
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('> Backup exported successfully',
                                  style: GoogleFonts.jetBrainsMono()),
                              backgroundColor: accent,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                  '> Export failed: ${e.toString()}',
                                  style: GoogleFonts.jetBrainsMono()),
                              backgroundColor: errorColor(context),
                            ),
                          );
                        }
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.black,
                    ),
                    child:
                        Text('[EXPORT]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
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
      if (pickResult == null || pickResult.files.isEmpty) return;

      final pickedFile = pickResult.files.single;
      String jsonString;
      if (pickedFile.bytes != null) {
        jsonString = utf8.decode(pickedFile.bytes!);
      } else {
        jsonString = await File(pickedFile.path!).readAsString();
      }

      final importResult = BackupService.importData(jsonString);
      if (!importResult.success) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('> ${importResult.errorMessage}',
                  style: GoogleFonts.jetBrainsMono()),
              backgroundColor: errorColor(context),
            ),
          );
        }
        return;
      }

      final surface = surfaceColor(context);
      final border = borderColor(context);
      final textSecondary = textSecondaryColor(context);
      final error = errorColor(context);
      final settings = context.read<SettingsProvider>();
      final accent = settings.accentColor;

      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.zero,
            side: BorderSide(color: border, width: 1),
          ),
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
                      color: error),
                ),
                const SizedBox(height: 16),
                Text(
                  'This will REPLACE ALL of your current data including:\n'
                  '• All workout plans\n'
                  '• All workout history\n'
                  '• App settings (theme, accent color, units)\n\n'
                  'This action cannot be undone.',
                  style: GoogleFonts.jetBrainsMono(
                      fontSize: 12, color: textSecondary),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: Text('[CANCEL]',
                          style:
                              GoogleFonts.jetBrainsMono(color: textSecondary)),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(ctx);
                        try {
                          await HiveService.replaceAllPlans(
                              importResult.plans!);
                          await HiveService.replaceAllSessions(
                              importResult.sessions!);
                          final s = importResult.settings!;
                          settings.setThemeMode(
                              ThemeMode.values[s['themeMode'] as int]);
                          settings.setAccentColor(
                              s['accentIndex'] as int);
                          settings.setWeightUnit(
                              s['weightUnit'] as String);
                          context
                              .read<WorkoutPlanProvider>()
                              .loadPlans();
                          context
                              .read<WorkoutSessionProvider>()
                              .loadSessions();
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '> Backup imported successfully',
                                    style: GoogleFonts.jetBrainsMono()),
                                backgroundColor: accent,
                              ),
                            );
                          }
                        } catch (e) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                    '> Import failed: ${e.toString()}',
                                    style: GoogleFonts.jetBrainsMono()),
                                backgroundColor: error,
                              ),
                            );
                          }
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: error,
                        foregroundColor: Colors.white,
                      ),
                      child: Text('[IMPORT]',
                          style: GoogleFonts.jetBrainsMono()),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('> Import failed: ${e.toString()}',
                style: GoogleFonts.jetBrainsMono()),
            backgroundColor: errorColor(context),
          ),
        );
      }
    }
  }

  void _confirmClearData(BuildContext context) {
    final bg = backgroundColor(context);
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textSecondary = textSecondaryColor(context);
    final textPrimary = textPrimaryColor(context);
    final error = errorColor(context);

    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> CLEAR ALL DATA?',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16, fontWeight: FontWeight.bold, color: error),
              ),
              const SizedBox(height: 16),
              Text(
                'This will delete all workout plans and history. This action cannot be undone.',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 12, color: textSecondary),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: Text('[CANCEL]',
                        style: GoogleFonts.jetBrainsMono(color: textSecondary)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: () async {
                      await SampleDataSeeder.clearAllData();
                      if (ctx.mounted) Navigator.pop(ctx);
                      if (context.mounted) {
                        context.read<WorkoutPlanProvider>().loadPlans();
                        context.read<WorkoutSessionProvider>().loadSessions();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('> All data cleared',
                                style: GoogleFonts.jetBrainsMono()),
                            backgroundColor: Colors.orange,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: error,
                      foregroundColor: Colors.white,
                    ),
                    child:
                        Text('[CLEAR ALL]', style: GoogleFonts.jetBrainsMono()),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showWeightUnitDialog(BuildContext context, SettingsProvider settings) {
    final surface = surfaceColor(context);
    final border = borderColor(context);
    final textPrimary = textPrimaryColor(context);
    final textSecondary = textSecondaryColor(context);
    final accent = settings.accentColor;

    showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.zero,
          side: BorderSide(color: border, width: 1),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '> SELECT WEIGHT UNIT',
                style: GoogleFonts.jetBrainsMono(
                    fontSize: 16, fontWeight: FontWeight.bold, color: accent),
              ),
              const SizedBox(height: 16),
              _buildRadioTile(
                title: 'KILOGRAMS (KG)',
                value: 'kg',
                groupValue: settings.weightUnit,
                onChanged: (value) {
                  settings.setWeightUnit(value!);
                  Navigator.pop(dialogContext);
                },
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
              _buildRadioTile(
                title: 'POUNDS (LBS)',
                value: 'lbs',
                groupValue: settings.weightUnit,
                onChanged: (value) {
                  settings.setWeightUnit(value!);
                  Navigator.pop(dialogContext);
                },
                accent: accent,
                textPrimary: textPrimary,
                textSecondary: textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRadioTile({
    required String title,
    required String value,
    required String groupValue,
    required ValueChanged<String?> onChanged,
    required Color accent,
    required Color textPrimary,
    required Color textSecondary,
  }) {
    final isSelected = value == groupValue;
    return InkWell(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                color: isSelected ? accent : Colors.transparent,
                border: Border.all(color: accent, width: 1),
              ),
              child: isSelected
                  ? const Icon(Icons.check, size: 14, color: Colors.black)
                  : null,
            ),
            const SizedBox(width: 12),
            Text(
              title,
              style: GoogleFonts.jetBrainsMono(
                fontSize: 12,
                color: isSelected ? accent : textPrimary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final Color accent;
  final Color border;

  const _SectionHeader(
      {required this.title, required this.accent, required this.border});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: border, width: 1)),
      ),
      child: Row(
        children: [
          Text(
            '> $title',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: accent,
            ),
          ),
        ],
      ),
    );
  }
}

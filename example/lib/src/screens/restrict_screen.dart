import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pauza_screen_time/pauza_screen_time.dart';
import 'package:pauza_screen_time_example/src/app/dependencies.dart';

/// Restrict screen for configuring shield and managing app restrictions.
class RestrictScreen extends StatefulWidget {
  final AppDependencies deps;

  const RestrictScreen({super.key, required this.deps});

  @override
  State<RestrictScreen> createState() => _RestrictScreenState();
}

class _RestrictScreenState extends State<RestrictScreen> {
  static const _modeId = 'example-mode';
  final _titleController = TextEditingController(text: 'App Blocked');
  final _subtitleController = TextEditingController(
    text: 'This app is currently restricted',
  );
  final _buttonLabelController = TextEditingController(text: 'OK');
  List<AppIdentifier> _restrictedApps = [];
  bool _isLoading = false;

  @override
  void initState() {
    super.initState();
    _loadRestrictedApps();
  }

  @override
  void dispose() {
    _titleController.dispose();
    _subtitleController.dispose();
    _buttonLabelController.dispose();
    super.dispose();
  }

  Future<void> _loadRestrictedApps() async {
    try {
      final modesConfig = await widget.deps.appRestrictionManager
          .getModesConfig();
      final mode = modesConfig.modes.where((mode) => mode.modeId == _modeId);
      final apps = mode.isEmpty ? <AppIdentifier>[] : mode.first.blockedAppIds;
      setState(() {
        _restrictedApps = apps;
      });
      widget.deps.logController.info(
        'restrict',
        'Loaded ${apps.length} restricted apps',
      );
    } catch (e, st) {
      widget.deps.logController.error(
        'restrict',
        'Failed to load restricted apps',
        e,
        st,
      );
    }
  }

  Future<void> _configureShield() async {
    try {
      widget.deps.logController.info('restrict', 'Configuring shield...');

      final config = ShieldConfiguration(
        title: _titleController.text.trim(),
        subtitle: _subtitleController.text.trim().isEmpty
            ? null
            : _subtitleController.text.trim(),
        primaryButtonLabel: _buttonLabelController.text.trim().isEmpty
            ? null
            : _buttonLabelController.text.trim(),
      );

      await widget.deps.appRestrictionManager.configureShield(config);

      widget.deps.logController.info(
        'restrict',
        'Shield configured successfully',
      );

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Shield configured')));
      }
    } catch (e, st) {
      widget.deps.logController.error(
        'restrict',
        'Failed to configure shield',
        e,
        st,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Future<void> _restrictSelected() async {
    final selected = widget.deps.selectionController.value;
    if (selected.isEmpty) {
      widget.deps.logController.warn(
        'restrict',
        'No apps selected for restriction',
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please select apps first')),
        );
      }
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      widget.deps.logController.info(
        'restrict',
        'Restricting ${selected.length} apps...',
      );

      final mode = RestrictionMode(
        modeId: _modeId,
        isEnabled: true,
        blockedAppIds: selected.toList(),
      );
      await widget.deps.appRestrictionManager.upsertMode(mode);
      await widget.deps.appRestrictionManager.setModesEnabled(true);
      final applied = mode.blockedAppIds;

      widget.deps.logController.info(
        'restrict',
        'Successfully restricted ${applied.length} apps: ${applied.take(3).map((identifier) => identifier.value).join(", ")}${applied.length > 3 ? "..." : ""}',
      );

      await _loadRestrictedApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Restricted ${applied.length} app(s)')),
        );
      }
    } catch (e, st) {
      widget.deps.logController.error(
        'restrict',
        'Failed to restrict apps',
        e,
        st,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _unrestrictApp(AppIdentifier identifier) async {
    try {
      widget.deps.logController.info(
        'restrict',
        'Unrestricting app: ${identifier.value}',
      );

      final modesConfig = await widget.deps.appRestrictionManager
          .getModesConfig();
      final modeMatches = modesConfig.modes
          .where((mode) => mode.modeId == _modeId)
          .toList();
      final existingMode = modeMatches.isEmpty ? null : modeMatches.first;
      final nextBlocked =
          existingMode?.blockedAppIds
              .where((id) => id != identifier)
              .toList() ??
          <AppIdentifier>[];
      final changed =
          existingMode != null &&
          nextBlocked.length != existingMode.blockedAppIds.length;

      await widget.deps.appRestrictionManager.upsertMode(
        RestrictionMode(
          modeId: _modeId,
          isEnabled: existingMode?.isEnabled ?? true,
          schedule: existingMode?.schedule,
          blockedAppIds: nextBlocked,
        ),
      );

      if (changed) {
        widget.deps.logController.info(
          'restrict',
          'Successfully unrestricted: ${identifier.value}',
        );
        await _loadRestrictedApps();
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('App unrestricted')));
        }
      } else {
        widget.deps.logController.warn(
          'restrict',
          'Unrestrict was a no-op: ${identifier.value}',
        );
      }
    } catch (e, st) {
      widget.deps.logController.error(
        'restrict',
        'Failed to unrestrict app',
        e,
        st,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  Future<void> _clearAll() async {
    try {
      widget.deps.logController.info(
        'restrict',
        'Clearing all restrictions...',
      );

      await widget.deps.appRestrictionManager.removeMode(_modeId);

      widget.deps.logController.info('restrict', 'All restrictions cleared');

      await _loadRestrictedApps();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('All restrictions cleared')),
        );
      }
    } catch (e, st) {
      widget.deps.logController.error(
        'restrict',
        'Failed to clear restrictions',
        e,
        st,
      );
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Error: ${e.toString()}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Restrict screen is Android-only.\n'
            'This screen configures the shield and manages app restrictions.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Shield Configuration',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _titleController,
                      decoration: const InputDecoration(
                        labelText: 'Title',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _subtitleController,
                      decoration: const InputDecoration(
                        labelText: 'Subtitle (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _buttonLabelController,
                      decoration: const InputDecoration(
                        labelText: 'Button Label (optional)',
                        border: OutlineInputBorder(),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton.icon(
                      onPressed: _configureShield,
                      icon: const Icon(Icons.settings),
                      label: const Text('Configure Shield'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              color: Colors.orange[50],
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(Icons.checklist, color: Colors.orange),
                        SizedBox(width: 8),
                        Text(
                          'Verification Checklist',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    FutureBuilder<PermissionStatus>(
                      future: widget.deps.permissionManager
                          .checkAndroidPermission(
                            AndroidPermission.accessibility,
                          ),
                      builder: (context, snapshot) {
                        final accessibilityGranted =
                            snapshot.data?.isGranted ?? false;
                        return _ChecklistItem(
                          label: 'Accessibility Service',
                          isChecked: accessibilityGranted,
                        );
                      },
                    ),
                    FutureBuilder<PermissionStatus>(
                      future: widget.deps.permissionManager
                          .checkAndroidPermission(AndroidPermission.usageStats),
                      builder: (context, snapshot) {
                        final usageGranted = snapshot.data?.isGranted ?? false;
                        return _ChecklistItem(
                          label: 'Usage Access (optional)',
                          isChecked: usageGranted,
                        );
                      },
                    ),
                    const _ChecklistItem(
                      label: 'Overlay Permission (device-dependent)',
                      isChecked: null,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<Set<AppIdentifier>>(
              valueListenable: widget.deps.selectionController,
              builder: (context, selected, _) {
                return ElevatedButton.icon(
                  onPressed: _isLoading || selected.isEmpty
                      ? null
                      : _restrictSelected,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.block),
                  label: Text('Restrict Selected (${selected.length})'),
                  style: ElevatedButton.styleFrom(
                    minimumSize: const Size(double.infinity, 48),
                    backgroundColor: Colors.red[100],
                  ),
                );
              },
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _loadRestrictedApps,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh Restricted List'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: _clearAll,
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear All Restrictions'),
              style: OutlinedButton.styleFrom(
                minimumSize: const Size(double.infinity, 48),
                foregroundColor: Colors.red,
              ),
            ),
            const SizedBox(height: 16),
            if (_restrictedApps.isNotEmpty) ...[
              const Text(
                'Currently Restricted Apps',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              ..._restrictedApps.map(
                (identifier) => Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    title: Text(identifier.value),
                    trailing: IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => _unrestrictApp(identifier),
                      tooltip: 'Unrestrict',
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ChecklistItem extends StatelessWidget {
  final String label;
  final bool? isChecked;

  const _ChecklistItem({required this.label, this.isChecked});

  @override
  Widget build(BuildContext context) {
    Widget icon;
    if (isChecked == null) {
      icon = const Icon(Icons.help_outline, size: 20, color: Colors.grey);
    } else if (isChecked!) {
      icon = const Icon(Icons.check_circle, size: 20, color: Colors.green);
    } else {
      icon = const Icon(Icons.cancel, size: 20, color: Colors.red);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 8),
          Expanded(child: Text(label)),
        ],
      ),
    );
  }
}

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pauza_screen_time/pauza_screen_time.dart';
import 'package:pauza_screen_time_example/src/app/dependencies.dart';
import 'package:pauza_screen_time_example/src/widgets/app_list_tile.dart';

/// Apps screen for loading, searching, and selecting installed apps.
class AppsScreen extends StatefulWidget {
  final AppDependencies deps;

  const AppsScreen({super.key, required this.deps});

  @override
  State<AppsScreen> createState() => _AppsScreenState();
}

class _AppsScreenState extends State<AppsScreen> {
  List<AndroidAppInfo> _allApps = [];
  List<AndroidAppInfo> _filteredApps = [];
  bool _isLoading = false;
  bool _includeSystemApps = false;
  bool _includeIcons = true;
  final TextEditingController _searchController = TextEditingController();

  AppIdentifier _androidIdentifier(AndroidAppInfo app) => app.packageId;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_filterApps);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _filterApps() {
    final query = _searchController.text.toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredApps = List.from(_allApps);
      } else {
        _filteredApps = _allApps
            .where(
              (app) =>
                  app.name.toLowerCase().contains(query) ||
                  app.packageId.raw.toLowerCase().contains(query),
            )
            .toList();
      }
    });
  }

  Future<void> _loadApps() async {
    if (!Platform.isAndroid) {
      widget.deps.logController.warn('apps', 'Loading apps skipped (Android only)');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      widget.deps.logController.info(
        'apps',
        'Loading apps (system: $_includeSystemApps, icons: $_includeIcons)...',
      );

      final apps = await widget.deps.installedAppsManager.getAndroidInstalledApps(
        includeSystemApps: _includeSystemApps,
        includeIcons: _includeIcons,
      );

      widget.deps.logController.info('apps', 'Loaded ${apps.length} apps');

      setState(() {
        _allApps = apps;
        _filteredApps = List.from(apps);
        _searchController.clear();
      });
    } catch (e, st) {
      widget.deps.logController.error('apps', 'Failed to load apps', e, st);
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

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Apps screen is Android-only.\n'
            'This screen lists installed apps and allows multi-selection.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: 'Search apps...',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Include system apps'),
                        value: _includeSystemApps,
                        onChanged: (value) {
                          setState(() {
                            _includeSystemApps = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                    Expanded(
                      child: CheckboxListTile(
                        title: const Text('Include icons'),
                        value: _includeIcons,
                        onChanged: (value) {
                          setState(() {
                            _includeIcons = value ?? false;
                          });
                        },
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                      ),
                    ),
                  ],
                ),
                ElevatedButton.icon(
                  onPressed: _isLoading ? null : _loadApps,
                  icon: _isLoading
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.refresh),
                  label: const Text('Load Apps'),
                  style: ElevatedButton.styleFrom(minimumSize: const Size(double.infinity, 48)),
                ),
                const SizedBox(height: 8),
                ValueListenableBuilder<Set<AppIdentifier>>(
                  valueListenable: widget.deps.selectionController,
                  builder: (context, selected, _) {
                    return Text(
                      'Loaded: ${_allApps.length} | '
                      'Filtered: ${_filteredApps.length} | '
                      'Selected: ${selected.length}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    );
                  },
                ),
              ],
            ),
          ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _filteredApps.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.apps, size: 64, color: Colors.grey),
                        const SizedBox(height: 16),
                        Text(
                          _allApps.isEmpty
                              ? 'Tap "Load Apps" to get started'
                              : 'No apps match your search',
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : ValueListenableBuilder<Set<AppIdentifier>>(
                    valueListenable: widget.deps.selectionController,
                    builder: (context, selected, _) {
                      return ListView.builder(
                        itemCount: _filteredApps.length,
                        itemBuilder: (context, index) {
                          final app = _filteredApps[index];
                          final identifier = _androidIdentifier(app);
                          return AppListTile(
                            app: app,
                            isSelected: selected.contains(identifier),
                            onTap: () {
                              widget.deps.selectionController.toggle(identifier);
                            },
                          );
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

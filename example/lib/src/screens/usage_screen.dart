import 'dart:io';

import 'package:flutter/material.dart';
import 'package:pauza_screen_time/pauza_screen_time.dart';

import 'package:pauza_screen_time_example/src/app/dependencies.dart';
import 'package:pauza_screen_time_example/src/widgets/duration_format.dart';

/// Usage stats screen for querying and displaying app usage statistics.
class UsageScreen extends StatefulWidget {
  final AppDependencies deps;

  const UsageScreen({super.key, required this.deps});

  @override
  State<UsageScreen> createState() => _UsageScreenState();
}

class _UsageScreenState extends State<UsageScreen> {
  List<UsageStats> _stats = [];
  bool _isLoading = false;
  DateTime? _startDate;
  DateTime? _endDate;

  @override
  void initState() {
    super.initState();
    _setPreset24h();
  }

  void _setPreset24h() {
    final now = DateTime.now();
    setState(() {
      _endDate = now;
      _startDate = now.subtract(const Duration(hours: 24));
    });
  }

  void _setPreset7d() {
    final now = DateTime.now();
    setState(() {
      _endDate = now;
      _startDate = now.subtract(const Duration(days: 7));
    });
  }

  Future<void> _queryStats() async {
    if (!Platform.isAndroid) {
      widget.deps.logController.warn(
        'usage',
        'Query stats skipped (Android only)',
      );
      return;
    }

    if (_startDate == null || _endDate == null) {
      widget.deps.logController.warn('usage', 'Date range not set');
      return;
    }

    setState(() {
      _isLoading = true;
    });

    try {
      widget.deps.logController.info(
        'usage',
        'Querying usage stats from ${_startDate!.toIso8601String()} to ${_endDate!.toIso8601String()}...',
      );

      final stats = await widget.deps.usageStatsManager.getUsageStats(
        startDate: _startDate!,
        endDate: _endDate!,
        includeIcons: true,
      );

      // Sort descending by totalDuration
      stats.sort((a, b) => b.totalDuration.compareTo(a.totalDuration));

      widget.deps.logController.info(
        'usage',
        'Retrieved ${stats.length} usage stats entries',
      );

      setState(() {
        _stats = stats;
      });
    } catch (e, st) {
      widget.deps.logController.error(
        'usage',
        'Failed to query usage stats',
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

  Future<void> _selectCustomRange() async {
    final now = DateTime.now();
    final start = await showDatePicker(
      context: context,
      initialDate: _startDate ?? now.subtract(const Duration(days: 1)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now,
    );
    if (start == null) return;
    if (!mounted) return;

    final end = await showDatePicker(
      context: context,
      initialDate: _endDate ?? now,
      firstDate: start,
      lastDate: now,
    );
    if (end == null) return;
    if (!mounted) return;

    setState(() {
      _startDate = start;
      _endDate = end;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!Platform.isAndroid) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24.0),
          child: Text(
            'Usage stats screen is Android-only.\n'
            'This screen queries and displays app usage statistics.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 16),
          ),
        ),
      );
    }

    // Check if Usage Access is granted
    return FutureBuilder<PermissionStatus>(
      future: widget.deps.permissionManager.checkAndroidPermission(
        AndroidPermission.usageStats,
      ),
      builder: (context, snapshot) {
        final hasPermission = snapshot.data?.isGranted ?? false;

        if (!hasPermission &&
            snapshot.connectionState == ConnectionState.done) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.warning, size: 64, color: Colors.orange),
                  const SizedBox(height: 16),
                  const Text(
                    'Usage Access Required',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Enable Usage Access in Settings to view app usage statistics.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton.icon(
                    onPressed: () => widget.deps.permissionManager
                        .openAndroidPermissionSettings(
                          AndroidPermission.usageStats,
                        ),
                    icon: const Icon(Icons.settings),
                    label: const Text('Open Usage Access Settings'),
                  ),
                ],
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
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton(
                          onPressed: _setPreset24h,
                          child: const Text('Last 24h'),
                        ),
                        ElevatedButton(
                          onPressed: _setPreset7d,
                          child: const Text('Last 7d'),
                        ),
                        OutlinedButton.icon(
                          onPressed: _selectCustomRange,
                          icon: const Icon(Icons.calendar_today, size: 18),
                          label: const Text('Custom'),
                        ),
                      ],
                    ),
                    if (_startDate != null && _endDate != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Range: ${_formatDate(_startDate!)} - ${_formatDate(_endDate!)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.grey,
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    ElevatedButton.icon(
                      onPressed: _isLoading ? null : _queryStats,
                      icon: _isLoading
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.query_stats),
                      label: const Text('Query Stats'),
                      style: ElevatedButton.styleFrom(
                        minimumSize: const Size(double.infinity, 48),
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _stats.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(
                              Icons.bar_chart,
                              size: 64,
                              color: Colors.grey,
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'No usage data yet.\n'
                              'Query stats or use your device for a few minutes.',
                              textAlign: TextAlign.center,
                              style: TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: _stats.length,
                        itemBuilder: (context, index) {
                          final stat = _stats[index];
                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: ListTile(
                              leading: stat.appInfo.icon != null
                                  ? Image.memory(
                                      stat.appInfo.icon!,
                                      width: 48,
                                      height: 48,
                                      errorBuilder:
                                          (context, error, stackTrace) =>
                                              const Icon(Icons.apps),
                                    )
                                  : const Icon(Icons.apps),
                              title: Text(stat.appInfo.name),
                              subtitle: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    stat.appInfo.packageId.raw,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Launches: ${stat.totalLaunchCount}',
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                ],
                              ),
                              trailing: Text(
                                formatDuration(stat.totalDuration),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _formatDate(DateTime dt) {
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-'
        '${dt.day.toString().padLeft(2, '0')}';
  }
}

import 'package:flutter/material.dart';

import 'package:attendance_app/core/models/sync_queue_item.dart';
import 'package:attendance_app/core/repositories/sync_queue_repository.dart';
import 'package:attendance_app/core/services/sync_service.dart';

/// Chip-sized live badge for the offline-first sync engine.
///
/// Displays the current sync state (`Synced`, `Syncing...`, `N pending`,
/// `N sync errors`, `Offline`) and opens a bottom sheet with the queue
/// contents plus a "Sync Now" button when tapped.
///
/// Reads from [SyncService.instance] and rebuilds automatically whenever
/// sync state changes.
class SyncStatusPill extends StatefulWidget {
  const SyncStatusPill({super.key});

  @override
  State<SyncStatusPill> createState() => _SyncStatusPillState();
}

class _SyncStatusPillState extends State<SyncStatusPill> {
  @override
  void initState() {
    super.initState();
    SyncService.instance.addListener(_onSyncChanged);
  }

  @override
  void dispose() {
    SyncService.instance.removeListener(_onSyncChanged);
    super.dispose();
  }

  void _onSyncChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _showSheet() => showModalBottomSheet<void>(
        context: context,
        useRootNavigator: true,
        isScrollControlled: true,
        enableDrag: true,
        builder: (BuildContext context) => const _SyncQueueSheet(),
      );

  @override
  Widget build(BuildContext context) {
    final service = SyncService.instance;
    final state = service.syncState;
    final pending = service.pendingCount;
    final failed = service.failedCount;

    Color color;
    IconData icon;
    String label;
    bool spinning;

    switch (state) {
      case SyncState.syncing:
        color = Colors.blue;
        icon = Icons.sync;
        label = 'Syncing...';
        spinning = true;
      case SyncState.offline:
        color = Colors.amber;
        icon = pending > 0 ? Icons.cloud_off : Icons.wifi_off;
        label = pending > 0 ? '$pending pending offline' : 'Offline';
        spinning = false;
      case SyncState.error:
        color = Colors.red;
        icon = Icons.error_outline;
        label = failed > 0 ? '$failed sync errors' : 'Sync error';
        spinning = false;
      case SyncState.idle:
        if (failed > 0) {
          color = Colors.red;
          icon = Icons.error_outline;
          label = '$failed sync errors';
        } else if (pending > 0) {
          color = Colors.amber;
          icon = Icons.cloud_off;
          label = '$pending pending';
        } else {
          color = Colors.green;
          icon = Icons.check_circle;
          label = 'Synced';
        }
        spinning = false;
    }

    return Tooltip(
      message:
          'Tap to view the offline sync queue and run a manual push/pull sync',
      child: InkWell(
        onTap: _showSheet,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            border: Border.all(color: color.withValues(alpha: 0.40)),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (spinning)
                SizedBox.square(
                  dimension: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.0,
                    color: color,
                  ),
                )
              else
                Icon(icon, size: 16, color: color),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
/// Bottom sheet exposing the offline sync queue and a manual sync entry point.
class _SyncQueueSheet extends StatefulWidget {
  const _SyncQueueSheet();

  @override
  State<_SyncQueueSheet> createState() => _SyncQueueSheetState();
}

class _SyncQueueSheetState extends State<_SyncQueueSheet> {
  final _repository = SyncQueueRepository();
  final _service = SyncService.instance;

  List<SyncQueueItem> _pending = <SyncQueueItem>[];
  List<SyncQueueItem> _quarantined = <SyncQueueItem>[];
  bool _syncing = false;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final pending = await _repository.getPendingItems();
    final quarantined = await _repository.getQuarantinedItems();
    if (!mounted) return;
    setState(() {
      _pending = pending;
      _quarantined = quarantined;
    });
  }

  Future<void> _syncNow() async {
    setState(() => _syncing = true);
    try {
      await _service.syncNow();
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sync complete'),
          duration: Duration(seconds: 2),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Sync failed: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  Future<void> _retryItem(String id) async {
    final ok = await _service.retryItem(id);
    if (!mounted) return;
    if (ok) {
      await _reload();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Item re-queued for retry')),
      );
    }
  }

  static String _formatLastSynced(DateTime? time) {
    if (time == null) return 'Never';
    final diff = DateTime.now().difference(time);
    if (diff.inDays > 0) {
      return '${diff.inDays} day${diff.inDays == 1 ? '' : 's'} ago';
    }
    if (diff.inHours > 0) {
      return '${diff.inHours} hour${diff.inHours == 1 ? '' : 's'} ago';
    }
    if (diff.inMinutes > 0) {
      return '${diff.inMinutes} minute${diff.inMinutes == 1 ? '' : 's'} ago';
    }
    return 'just now';
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '-';
    final local = time.toLocal();
    return '${local.hour.toString().padLeft(2, '0')}:${local.minute.toString().padLeft(2, '0')}';
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Icon(
            icon,
            size: 18,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontWeight: FontWeight.w500),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 13),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, int count, Color color) {
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Row(
        children: <Widget>[
          Container(
            width: 7,
            height: 7,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Text(
            '$title ($count)',
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _empty(String text) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12,
          fontStyle: FontStyle.italic,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _queueItemTile(SyncQueueItem item, {required bool retry}) {
    final theme = Theme.of(context);
    final hasError = item.lastError != null && retry;
    final type =
        '${item.entityType[0].toUpperCase()}${item.entityType.substring(1)}';
    return ListTile(
      dense: true,
      visualDensity: VisualDensity.compact,
      title: Text(
        '$type ${item.operation.value}',
        style: const TextStyle(fontSize: 13),
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            item.entityId,
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
              fontFamily: 'monospace',
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
          if (hasError)
            Text(
              'Error: ${item.lastError}',
              style: const TextStyle(fontSize: 11.5, color: Colors.red),
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          Text(
            'queued ${_formatTime(item.createdAt)}  \u2022  retry ${item.retryCount}',
            style: TextStyle(
              fontSize: 11.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
          ),
        ],
      ),
      trailing: retry
          ? IconButton(
              icon: const Icon(Icons.repeat, size: 18),
              tooltip: 'Retry',
              onPressed: () => _retryItem(item.id),
            )
          : null,
      contentPadding: EdgeInsets.zero,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              margin: const EdgeInsets.symmetric(vertical: 8),
              width: 32,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.cloud_sync,
                        color: colorScheme.primary,
                        size: 22,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Sync queue',
                          style: theme.textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.refresh),
                        tooltip: 'Refresh',
                        onPressed: _syncing ? null : _reload,
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  _infoRow(
                    Icons.access_time,
                    'Last synced',
                    _formatLastSynced(_service.lastSyncedAt),
                  ),
                  const Divider(height: 28),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: _syncing ? null : _syncNow,
                      icon: _syncing
                          ? SizedBox.square(
                              dimension: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.0,
                                color: colorScheme.primary,
                              ),
                            )
                          : const Icon(Icons.refresh, size: 18),
                      label: Text(_syncing ? 'Syncing...' : 'Sync Now'),
                    ),
                  ),
                  const SizedBox(height: 24),
                  _sectionHeader('Pending uploads', _pending.length, Colors.amber),
                  ..._pending.map((item) => _queueItemTile(item, retry: false)),
                  if (_pending.isEmpty) _empty('Nothing waiting to push.'),
                  const SizedBox(height: 20),
                  _sectionHeader(
                      'Failed / quarantined', _quarantined.length, Colors.red),
                  ..._quarantined.map((item) => _queueItemTile(item, retry: true)),
                  if (_quarantined.isEmpty) _empty('No failed items.'),
                  const SizedBox(height: 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
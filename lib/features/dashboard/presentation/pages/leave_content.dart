import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/models/leave_request.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/leave_store.dart';

/// Leave management page backed by the database.
class LeaveContent extends StatefulWidget {
  const LeaveContent({super.key});

  @override
  State<LeaveContent> createState() => _LeaveContentState();
}

class _LeaveContentState extends State<LeaveContent> {
  String _filterStatus = 'All';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<LeaveStore>().loadAll();
    });
  }

  List<LeaveRequest> _filtered(LeaveStore store) {
    if (_filterStatus == 'All') return store.requests;
    final status = LeaveStatus.fromString(_filterStatus.toLowerCase());
    return store.requests.where((r) => r.status == status).toList();
  }

  Future<void> _showApplyDialog() async {
    final authStore = context.read<AuthStore>();
    final defaultName = authStore.currentUser?.displayName ?? '';

    final result = await showDialog<_ApplyLeaveResult>(
      context: context,
      builder: (ctx) => _ApplyLeaveDialog(defaultRequesterName: defaultName),
    );

    if (result == null || !mounted) return;

    await context.read<LeaveStore>().applyLeave(
      requesterName: result.requesterName,
      leaveType: result.leaveType,
      startDate: result.startDate,
      endDate: result.endDate,
      reason: result.reason,
    );
  }

  Future<void> _updateStatus(LeaveRequest request, LeaveStatus newStatus) async {
    await context.read<LeaveStore>().updateStatus(request.id!, newStatus);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final store = context.watch<LeaveStore>();
    final items = _filtered(store);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Leave Management',
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                FilledButton.icon(
                  onPressed: _showApplyDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Apply Leave'),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Stat chips
            Wrap(
              spacing: 12,
              runSpacing: 8,
              children: [
                _statChip('Pending', store.pendingCount, Colors.orange),
                _statChip('Approved', store.approvedCount, Colors.green),
                _statChip('Rejected', store.rejectedCount, Colors.red),
              ],
            ),
            const SizedBox(height: 16),

            // Filter row
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: ['All', 'Pending', 'Approved', 'Rejected']
                    .map(
                      (status) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: FilterChip(
                          label: Text(status),
                          selected: _filterStatus == status,
                          onSelected: (selected) {
                            setState(() => _filterStatus = selected ? status : 'All');
                          },
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 12),

            // Leave request list
            Expanded(
              child: items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.event_busy_outlined,
                            size: 48,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No leave requests',
                            style: theme.textTheme.titleMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      itemCount: items.length,
                      padding: const EdgeInsets.only(bottom: 24),
                      itemBuilder: (ctx, index) {
                        final item = items[index];
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          child: Padding(
                            padding: const EdgeInsets.all(14),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    CircleAvatar(
                                      radius: 18,
                                      backgroundColor: colorScheme.primaryContainer,
                                      child: Text(
                                        item.requesterName.isNotEmpty
                                            ? item.requesterName[0].toUpperCase()
                                            : '?',
                                        style: TextStyle(
                                          color: colorScheme.onPrimaryContainer,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.requesterName,
                                            style: theme.textTheme.bodyMedium?.copyWith(
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          Text(
                                            '${item.leaveType} • ${item.dateRange}',
                                            style: theme.textTheme.bodySmall?.copyWith(
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 4,
                                      ),
                                      decoration: BoxDecoration(
                                        color: item.status.color.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Text(
                                        item.status.displayName,
                                        style: TextStyle(
                                          color: item.status.color,
                                          fontWeight: FontWeight.w600,
                                          fontSize: 12,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (item.reason.isNotEmpty) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    item.reason,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                                if (item.status == LeaveStatus.pending) ...[
                                  const SizedBox(height: 10),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.end,
                                    children: [
                                      OutlinedButton(
                                        onPressed: () =>
                                            _updateStatus(item, LeaveStatus.rejected),
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: Colors.red,
                                        ),
                                        child: const Text('Reject'),
                                      ),
                                      const SizedBox(width: 8),
                                      FilledButton(
                                        onPressed: () =>
                                            _updateStatus(item, LeaveStatus.approved),
                                        child: const Text('Approve'),
                                      ),
                                    ],
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, int count, Color color) {
    return Chip(
      avatar: CircleAvatar(
        backgroundColor: color,
        radius: 6,
      ),
      label: Text('$label: $count'),
      visualDensity: VisualDensity.compact,
    );
  }
}

// ---------------------------------------------------------------------------
// Apply Leave Dialog
// ---------------------------------------------------------------------------

class _ApplyLeaveResult {
  const _ApplyLeaveResult({
    required this.requesterName,
    required this.leaveType,
    required this.startDate,
    required this.endDate,
    required this.reason,
  });

  final String requesterName;
  final String leaveType;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
}

class _ApplyLeaveDialog extends StatefulWidget {
  const _ApplyLeaveDialog({required this.defaultRequesterName});

  final String defaultRequesterName;

  @override
  State<_ApplyLeaveDialog> createState() => _ApplyLeaveDialogState();
}

class _ApplyLeaveDialogState extends State<_ApplyLeaveDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _reasonController;
  String _leaveType = 'Sick Leave';
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  static const _leaveTypes = [
    'Sick Leave',
    'Casual Leave',
    'Personal Leave',
    'Emergency Leave',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.defaultRequesterName);
    _reasonController = TextEditingController();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime.now().subtract(const Duration(days: 30)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
        if (_endDate.isBefore(_startDate)) _endDate = _startDate;
      } else {
        _endDate = picked;
      }
    });
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    Navigator.of(context).pop(
      _ApplyLeaveResult(
        requesterName: _nameController.text,
        leaveType: _leaveType,
        startDate: _startDate,
        endDate: _endDate,
        reason: _reasonController.text,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Apply Leave'),
      content: SizedBox(
        width: 420,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: const InputDecoration(
                    labelText: 'Requester name',
                    prefixIcon: Icon(Icons.person_outline_rounded),
                  ),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) return 'Required';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                DropdownButtonFormField<String>(
                  initialValue: _leaveType,
                  decoration: const InputDecoration(labelText: 'Leave type'),
                  items: _leaveTypes
                      .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) _leaveType = value;
                  },
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: true),
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text(DateFormat('d MMM yyyy').format(_startDate)),
                      ),
                    ),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 8),
                      child: Text('to'),
                    ),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(isStart: false),
                        icon: const Icon(Icons.calendar_today_rounded, size: 16),
                        label: Text(DateFormat('d MMM yyyy').format(_endDate)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _reasonController,
                  maxLines: 3,
                  decoration: const InputDecoration(
                    labelText: 'Reason (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _submit,
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

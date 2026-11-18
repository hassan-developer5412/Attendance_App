import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:attendance_app/core/constants/app_constants.dart';
import 'package:attendance_app/core/models/timetable_slot.dart';
import 'package:attendance_app/core/repositories/timetable_repository.dart';
import 'package:attendance_app/core/state/auth_store.dart';
import 'package:attendance_app/core/state/institute_store.dart';
import 'package:attendance_app/core/state/rbac_store.dart';
import 'package:attendance_app/core/state/timetable_store.dart';
import 'package:attendance_app/core/widgets/permission_guard.dart';
import 'package:attendance_app/core/widgets/themed_dropdown.dart';

/// Weekly Class & Lab Timetable page.
///
/// Displays a weekly schedule (Mon–Sat) grouped by day and period, with filter
/// toggles by Class or Teacher. Slots are colour-coded with a Lab vs Theory
/// badge. Add/Edit is gated by [PermissionCodes.timetableManage].
class TimetableContent extends StatefulWidget {
  const TimetableContent({super.key});

  @override
  State<TimetableContent> createState() => _TimetableContentState();
}

class _TimetableContentState extends State<TimetableContent> {
  static const _days = <int>[1, 2, 3, 4, 5, 6]; // Monday–Saturday
  static const _periods = <int>[1, 2, 3, 4, 5, 6, 7, 8];

  static const _dayNames = <String>[
    'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat',
  ];

  String _filterMode = 'class'; // 'class' | 'teacher'
  String? _selectedClassId;
  String? _selectedTeacherId;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    try {
      final store = context.read<TimetableStore>();
      await store.init();
      if (!mounted) return;
      final instituteStore = context.read<InstituteStore>();
      await instituteStore.init();
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _selectedClassId = instituteStore.classes.isNotEmpty
            ? instituteStore.classes.first.id
            : null;
        _selectedTeacherId = instituteStore.teachers.isNotEmpty
            ? instituteStore.teachers.first.id
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
    }
  }

  List<TimetableSlot> _getFilteredSlots(TimetableStore store) {
    if (_filterMode == 'class' && _selectedClassId != null) {
      return store.slotsForClass(_selectedClassId!);
    }
    if (_filterMode == 'teacher' && _selectedTeacherId != null) {
      return store.slotsForTeacher(_selectedTeacherId!);
    }
    return store.slots;
  }

  TimetableSlot? _slotAtOrNull(List<TimetableSlot> slots, int dayOfWeek, int periodSlot) {
    for (final s in slots) {
      if (s.dayOfWeek == dayOfWeek && s.periodSlot == periodSlot) {
        return s;
      }
    }
    return null;
  }

  Future<void> _openAddEditDialog({TimetableSlot? existing}) async {
    final instituteStore = context.read<InstituteStore>();
    final timetableStore = context.read<TimetableStore>();

    final classItems = <DropdownMenuItem<String>>[];
    for (final c in instituteStore.classes) {
      classItems.add(
        DropdownMenuItem<String>(value: c.id, child: Text(c.displayName)),
      );
    }

    final subjectItems = <DropdownMenuItem<String>>[];
    for (final s in instituteStore.subjects) {
      subjectItems.add(
        DropdownMenuItem<String>(
          value: s.id,
          child: Text('${s.name} (${s.code})'),
        ),
      );
    }

    final teacherItems = <DropdownMenuItem<String>>[];
    for (final t in instituteStore.teachers
        .where((t) => t.isActive && !t.isDeleted)) {
      teacherItems.add(
        DropdownMenuItem<String>(value: t.id, child: Text(t.name)),
      );
    }

    String newClassId = existing?.classId ??
        _selectedClassId ??
        (instituteStore.classes.isNotEmpty ? instituteStore.classes.first.id : '');
    String newSubjectId = existing?.subjectId ??
        (instituteStore.subjects.isNotEmpty ? instituteStore.subjects.first.id : '');
    String newTeacherId = existing?.teacherId ??
        _selectedTeacherId ??
        (teacherItems.isNotEmpty ? teacherItems.first.value! : '');
    String newRoomName = existing?.roomName ?? '';
    int newDayOfWeek = existing?.dayOfWeek ?? DateTime.now().weekday.clamp(1, 6);
    int newPeriodSlot = existing?.periodSlot ?? 1;
    String newStartTime = existing?.startTime ?? '09:00';
    String newEndTime = existing?.endTime ?? '09:50';
    bool newIsLab = existing?.isLab ?? false;
    String? dialogError;

    final startTimeController = TextEditingController(text: newStartTime);
    final endTimeController = TextEditingController(text: newEndTime);
    final roomController = TextEditingController(text: newRoomName);

    TimeOfDay parseTime(String hhMm) {
      final parts = hhMm.split(':');
      final h = parts.isNotEmpty ? int.tryParse(parts[0]) ?? 9 : 9;
      final m = parts.length > 1 ? int.tryParse(parts[1]) ?? 0 : 0;
      return TimeOfDay(hour: h, minute: m);
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              title: Text(
                existing == null ? 'Add Timetable Slot' : 'Edit Timetable Slot',
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (dialogError != null) ...[
                      Container(
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: Theme.of(ctx).colorScheme.errorContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Theme.of(ctx).colorScheme.error),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.error_outline_rounded,
                                color: Theme.of(ctx).colorScheme.error, size: 20),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dialogError!,
                                style: TextStyle(
                                  color: Theme.of(ctx).colorScheme.error,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    AppDropdownButtonFormField<String>(
                      items: classItems,
                      initialValue: newClassId.isNotEmpty ? newClassId : null,
                      hint: const Text('Class'),
                      onChanged: (v) =>
                          setDialogState(() => newClassId = v ?? ''),
                      decoration: const InputDecoration(labelText: 'Class *'),
                    ),
                    const SizedBox(height: 10),
                    AppDropdownButtonFormField<String>(
                      items: subjectItems,
                      initialValue: newSubjectId.isNotEmpty ? newSubjectId : null,
                      hint: const Text('Subject'),
                      onChanged: (v) =>
                          setDialogState(() => newSubjectId = v ?? ''),
                      decoration: const InputDecoration(labelText: 'Subject *'),
                    ),
                    const SizedBox(height: 10),
                    AppDropdownButtonFormField<String>(
                      items: teacherItems,
                      initialValue: newTeacherId.isNotEmpty ? newTeacherId : null,
                      hint: const Text('Teacher'),
                      onChanged: (v) =>
                          setDialogState(() => newTeacherId = v ?? ''),
                      decoration: const InputDecoration(labelText: 'Teacher *'),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: AppDropdownButtonFormField<int>(
                            items: _days
                                .map((d) => DropdownMenuItem<int>(
                                      value: d,
                                      child: Text(
                                        _dayNames[_days.indexOf(d)],
                                      ),
                                    ))
                                .toList(),
                            initialValue: newDayOfWeek,
                            onChanged: (v) =>
                                setDialogState(() => newDayOfWeek = v ?? 1),
                            decoration: const InputDecoration(labelText: 'Day *'),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: AppDropdownButtonFormField<int>(
                            items: _periods
                                .map((p) => DropdownMenuItem<int>(
                                      value: p,
                                      child: Text('Period $p'),
                                    ))
                                .toList(),
                            initialValue: newPeriodSlot,
                            onChanged: (v) =>
                                setDialogState(() => newPeriodSlot = v ?? 1),
                            decoration: const InputDecoration(
                              labelText: 'Period *',
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: startTimeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'Start Time *',
                              suffixIcon: Icon(Icons.access_time_rounded),
                            ),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: parseTime(newStartTime),
                              );
                              if (picked != null) {
                                final formatted =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                setDialogState(() {
                                  newStartTime = formatted;
                                  startTimeController.text = formatted;
                                });
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: TextFormField(
                            controller: endTimeController,
                            readOnly: true,
                            decoration: const InputDecoration(
                              labelText: 'End Time *',
                              suffixIcon: Icon(Icons.access_time_rounded),
                            ),
                            onTap: () async {
                              final picked = await showTimePicker(
                                context: ctx,
                                initialTime: parseTime(newEndTime),
                              );
                              if (picked != null) {
                                final formatted =
                                    '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}';
                                setDialogState(() {
                                  newEndTime = formatted;
                                  endTimeController.text = formatted;
                                });
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    TextFormField(
                      controller: roomController,
                      decoration: const InputDecoration(
                        labelText: 'Room / Lab Name *',
                        hintText: 'Room 4 / Comp Lab A',
                      ),
                      onChanged: (v) => newRoomName = v.trim(),
                    ),
                    const SizedBox(height: 10),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: const Text('Lab Session'),
                      subtitle: const Text('Distinguish practical lab from theory'),
                      value: newIsLab,
                      onChanged: (v) => setDialogState(() => newIsLab = v),
                    ),
                  ],
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () async {
                      try {
                        await timetableStore.deleteSlot(existing.id);
                        if (dialogContext.mounted) {
                          Navigator.of(dialogContext).pop();
                        }
                      } catch (e) {
                        setDialogState(() => dialogError = e.toString());
                      }
                    },
                    icon: Icon(Icons.delete_outline_rounded,
                        color: Theme.of(ctx).colorScheme.error),
                    label: Text(
                      'Delete',
                      style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                    ),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () async {
                    if (newClassId.isEmpty ||
                        newSubjectId.isEmpty ||
                        newTeacherId.isEmpty ||
                        newRoomName.isEmpty) {
                      setDialogState(() {
                        dialogError = 'Please fill all required fields.';
                      });
                      return;
                    }

                    final slot = TimetableSlot(
                      id: existing?.id,
                      instituteId: AppConstants.defaultInstituteId,
                      academicSessionId:
                          instituteStore.currentAcademicSession?.id,
                      classId: newClassId,
                      subjectId: newSubjectId,
                      teacherId: newTeacherId,
                      roomName: newRoomName,
                      dayOfWeek: newDayOfWeek,
                      periodSlot: newPeriodSlot,
                      startTime: newStartTime,
                      endTime: newEndTime,
                      isLab: newIsLab,
                    );

                    try {
                      if (existing == null) {
                        await timetableStore.addSlot(
                          instituteId: slot.instituteId,
                          academicSessionId: slot.academicSessionId,
                          classId: slot.classId,
                          subjectId: slot.subjectId,
                          teacherId: slot.teacherId,
                          roomName: slot.roomName,
                          dayOfWeek: slot.dayOfWeek,
                          periodSlot: slot.periodSlot,
                          startTime: slot.startTime,
                          endTime: slot.endTime,
                          isLab: slot.isLab,
                        );
                      } else {
                        await timetableStore.updateSlot(slot);
                      }
                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    } on TimetableConflictException catch (e) {
                      setDialogState(() {
                        dialogError = e.message;
                      });
                    } catch (e) {
                      setDialogState(() {
                        dialogError = 'Failed to save timetable slot: $e';
                      });
                    }
                  },
                  child: const Text('Save'),
                ),
              ],
            );
          },
        );
      },
    );

    startTimeController.dispose();
    endTimeController.dispose();
    roomController.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final timetableStore = context.watch<TimetableStore>();
    final instituteStore = context.watch<InstituteStore>();
    final authStore = context.watch<AuthStore>();
    final rbacStore = context.watch<RBACStore>();
    final canManage = authStore.currentUser != null &&
        rbacStore.hasPermission(PermissionCodes.timetableManage);

    final filteredSlots = _getFilteredSlots(timetableStore);

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Weekly Timetable',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              PermissionGuard(
                permission: PermissionCodes.timetableManage,
                child: FilledButton.icon(
                  onPressed: () => _openAddEditDialog(),
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text('Add Slot'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text('Filter by: ', style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Class'),
                selected: _filterMode == 'class',
                onSelected: (_) => setState(() => _filterMode = 'class'),
              ),
              const SizedBox(width: 8),
              ChoiceChip(
                label: const Text('Teacher'),
                selected: _filterMode == 'teacher',
                onSelected: (_) => setState(() => _filterMode = 'teacher'),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_filterMode == 'class') ...[
            AppDropdownButtonFormField<String>(
              items: instituteStore.classes
                  .map(
                    (c) => DropdownMenuItem<String>(
                      value: c.id,
                      child: Text(c.displayName),
                    ),
                  )
                  .toList(),
              initialValue: _selectedClassId,
              hint: const Text('Select Class'),
              onChanged: (v) => setState(() => _selectedClassId = v),
              decoration: const InputDecoration(labelText: 'Class'),
              isExpanded: true,
            ),
          ] else ...[
            AppDropdownButtonFormField<String>(
              items: instituteStore.teachers
                  .where((t) => t.isActive && !t.isDeleted)
                  .map(
                    (t) => DropdownMenuItem<String>(
                      value: t.id,
                      child: Text(t.name),
                    ),
                  )
                  .toList(),
              initialValue: _selectedTeacherId,
              hint: const Text('Select Teacher'),
              onChanged: (v) => setState(() => _selectedTeacherId = v),
              decoration: const InputDecoration(labelText: 'Teacher'),
              isExpanded: true,
            ),
          ],
          const SizedBox(height: 16),
          Expanded(
            child: GridView(
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                childAspectRatio: 1.0,
                crossAxisSpacing: 6,
                mainAxisSpacing: 6,
              ),
              children: [
                const SizedBox.shrink(),
                for (final day in _days)
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _dayNames[_days.indexOf(day)],
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                for (final period in _periods) ...[
                  Container(
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      'P$period',
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  for (final day in _days)
                    _slotCell(
                      filteredSlots,
                      day,
                      period,
                      theme,
                      colorScheme,
                      instituteStore,
                      canManage,
                    ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _slotCell(
    List<TimetableSlot> slots,
    int dayOfWeek,
    int periodSlot,
    ThemeData theme,
    ColorScheme colorScheme,
    InstituteStore instituteStore,
    bool canManage,
  ) {
    final slot = _slotAtOrNull(slots, dayOfWeek, periodSlot);
    final isLab = slot?.isLab ?? false;
    final badgeColor = isLab ? colorScheme.tertiary : colorScheme.primary;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () {
        if (canManage && slot != null) {
          _openAddEditDialog(existing: slot);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: slot != null
              ? badgeColor.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerLowest,
          border: Border.all(
            color: slot != null
                ? badgeColor.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: slot == null
            ? const Center(child: Text('—', style: TextStyle(fontSize: 10)))
            : Padding(
                padding: const EdgeInsets.all(6),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isLab ? 'LAB' : 'THEORY',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: badgeColor,
                          fontWeight: FontWeight.bold,
                          fontSize: 8,
                        ),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      instituteStore.subjectById(slot.subjectId)?.name ??
                          slot.subjectId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      _teacherName(slot.teacherId, instituteStore) ??
                          slot.teacherId,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 1),
                    Text(
                      slot.roomName,
                      style: theme.textTheme.bodySmall?.copyWith(
                        fontSize: 9,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  String? _teacherName(String teacherId, InstituteStore instituteStore) {
    if (teacherId.isEmpty) return null;
    for (final t in instituteStore.teachers) {
      if (t.id == teacherId) return t.name;
    }
    return null;
  }
}

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:attendance_app/core/models/notice.dart';
import 'package:attendance_app/core/state/institute_store.dart';

/// Result returned by [NoticeFormDialog.showPublishDialog].
class NoticeFormResult {
  const NoticeFormResult({
    required this.title,
    required this.body,
    this.targetRole,
    this.departmentId,
    this.attachmentUrl,
    required this.isPinned,
  });

  final String title;
  final String body;
  final String? targetRole;
  final String? departmentId;
  final String? attachmentUrl;
  final bool isPinned;
}

/// Dialog for publishing a new notice or editing an existing one.
///
/// Open via the static [showPublishDialog] helper which returns a
/// [NoticeFormResult] when the user confirms, or `null` when cancelled.
class NoticeFormDialog extends StatefulWidget {
  const NoticeFormDialog({super.key, this.existing});

  /// When non-null the dialog opens in edit mode with fields pre-filled.
  final Notice? existing;

  // ---------------------------------------------------------------------------
  // Static launcher
  // ---------------------------------------------------------------------------

  /// Shows the dialog and returns a [NoticeFormResult] on confirm, or `null`
  /// if the user cancels.
  static Future<NoticeFormResult?> showPublishDialog(
    BuildContext context, {
    Notice? existing,
  }) {
    return showDialog<NoticeFormResult>(
      context: context,
      builder: (_) => NoticeFormDialog(existing: existing),
    );
  }

  @override
  State<NoticeFormDialog> createState() => _NoticeFormDialogState();
}

class _NoticeFormDialogState extends State<NoticeFormDialog> {
  final _formKey = GlobalKey<FormState>();

  late final TextEditingController _titleController;
  late final TextEditingController _bodyController;
  late final TextEditingController _attachmentController;

  String? _targetRole; // null means 'all'
  String? _departmentId;
  bool _isPinned = false;

  bool get _isEditMode => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleController = TextEditingController(text: e?.title ?? '');
    _bodyController = TextEditingController(text: e?.body ?? '');
    _attachmentController =
        TextEditingController(text: e?.attachmentUrl ?? '');
    _targetRole = (e?.targetRole == null || e!.targetRole == 'all')
        ? null
        : e.targetRole;
    _departmentId = e?.departmentId;
    _isPinned = e?.isPinned ?? false;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _bodyController.dispose();
    _attachmentController.dispose();
    super.dispose();
  }

  void _submit() {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final attachmentUrl = _attachmentController.text.trim();
    Navigator.of(context).pop(
      NoticeFormResult(
        title: _titleController.text.trim(),
        body: _bodyController.text.trim(),
        targetRole: _targetRole, // null == 'all'
        departmentId: _departmentId,
        attachmentUrl: attachmentUrl.isEmpty ? null : attachmentUrl,
        isPinned: _isPinned,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    InstituteStore? instituteStore;
    try {
      instituteStore = Provider.of<InstituteStore>(context, listen: false);
    } catch (_) {}
    final activeDepartments = instituteStore?.activeDepartments ?? const [];

    return AlertDialog(
      title: Row(
        children: [
          Icon(
            _isEditMode ? Icons.edit_note_rounded : Icons.campaign_rounded,
            color: colorScheme.primary,
          ),
          const SizedBox(width: 10),
          Text(
            _isEditMode ? 'Edit Notice' : 'Publish Notice',
            style: theme.textTheme.titleLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Title ──────────────────────────────────────────────────
                TextFormField(
                  controller: _titleController,
                  decoration: const InputDecoration(
                    labelText: 'Title *',
                    prefixIcon: Icon(Icons.title_rounded),
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Title is required' : null,
                ),
                const SizedBox(height: 14),

                // ── Body ───────────────────────────────────────────────────
                TextFormField(
                  controller: _bodyController,
                  decoration: const InputDecoration(
                    labelText: 'Notice Body *',
                    alignLabelWithHint: true,
                    prefixIcon: Padding(
                      padding: EdgeInsets.only(bottom: 48),
                      child: Icon(Icons.article_outlined),
                    ),
                  ),
                  minLines: 3,
                  maxLines: 6,
                  textCapitalization: TextCapitalization.sentences,
                  validator: (val) =>
                      val == null || val.trim().isEmpty ? 'Body is required' : null,
                ),
                const SizedBox(height: 14),

                // ── Target Audience ────────────────────────────────────────
                DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _targetRole,
                  decoration: const InputDecoration(
                    labelText: 'Target Audience',
                    prefixIcon: Icon(Icons.people_alt_outlined),
                  ),
                  items: const [
                    DropdownMenuItem(value: null, child: Text('All')),
                    DropdownMenuItem(value: 'teacher', child: Text('Teachers')),
                    DropdownMenuItem(value: 'student', child: Text('Students')),
                  ],
                  onChanged: (val) => setState(() => _targetRole = val),
                ),
                const SizedBox(height: 14),

                // ── Department ─────────────────────────────────────────────
                DropdownButtonFormField<String?>(
                  // ignore: deprecated_member_use
                  value: _departmentId,
                  decoration: const InputDecoration(
                    labelText: 'Department',
                    prefixIcon: Icon(Icons.apartment_rounded),
                  ),
                  items: [
                    const DropdownMenuItem(
                        value: null, child: Text('All Departments')),
                    ...activeDepartments.map(
                      (d) => DropdownMenuItem(value: d.id, child: Text(d.name)),
                    ),
                  ],
                  onChanged: (val) => setState(() => _departmentId = val),
                ),
                const SizedBox(height: 14),

                // ── Attachment URL ─────────────────────────────────────────
                TextFormField(
                  controller: _attachmentController,
                  decoration: const InputDecoration(
                    labelText: 'Attachment URL (optional)',
                    prefixIcon: Icon(Icons.attachment_rounded),
                    hintText: 'https://…',
                  ),
                  keyboardType: TextInputType.url,
                ),
                const SizedBox(height: 8),

                // ── Pin to Top ─────────────────────────────────────────────
                Card(
                  elevation: 0,
                  margin: EdgeInsets.zero,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                    side: BorderSide(color: colorScheme.outlineVariant),
                  ),
                  child: SwitchListTile(
                    value: _isPinned,
                    onChanged: (val) => setState(() => _isPinned = val),
                    title: const Text('Pin to Top'),
                    subtitle: const Text(
                      'Pinned notices appear above all others',
                    ),
                    secondary: Icon(
                      Icons.push_pin_rounded,
                      color: _isPinned ? colorScheme.primary : null,
                    ),
                    dense: true,
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
        FilledButton.icon(
          onPressed: _submit,
          icon: Icon(
            _isEditMode ? Icons.save_rounded : Icons.send_rounded,
            size: 18,
          ),
          label: Text(_isEditMode ? 'Save Changes' : 'Publish'),
        ),
      ],
    );
  }
}

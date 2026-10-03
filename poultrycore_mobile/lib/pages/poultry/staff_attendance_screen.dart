import 'package:flutter/material.dart';

import '../../api/api_client.dart';
import '../../design/tokens.dart';
import '../../design/ui/buttons.dart';
import '../../design/ui/form_section.dart';
import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';

/// Poultry Staff → "Attendance" for one person, as the web's
/// "Record attendance" dialog in `app/poultry-staff/page.tsx`. Upserts the
/// day through `POST /api/Poultry/staff-attendance` (upsertPoultryStaffAttendance).
class StaffAttendanceScreen extends StatefulWidget {
  const StaffAttendanceScreen({
    super.key,
    required this.session,
    required this.company,
    required this.staff,
  });

  final Session session;
  final Company company;
  final Map<String, dynamic> staff;

  @override
  State<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

/// POULTRY_ATTENDANCE_STATUS.
const _statuses = ['Present', 'Absent', 'Late', 'HalfDay', 'OffDay'];

class _StaffAttendanceScreenState extends State<StaffAttendanceScreen> {
  DateTime _date = DateTime.now();
  String _status = 'Present';
  final _shift = TextEditingController();
  final _notes = TextEditingController();
  bool _saving = false;

  String get _name =>
      '${widget.staff['firstName'] ?? ''} ${widget.staff['lastName'] ?? ''}'.trim();

  String get _day =>
      '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';

  @override
  void dispose() {
    _shift.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.session.farmClient.post(
        '/api/Poultry/staff-attendance',
        query: {
          'farmId': widget.company.farmId,
          'createdBy': widget.session.tokens.userId ?? '',
        },
        body: {
          'poultryStaffId': widget.staff['poultryStaffId'],
          'attendanceDate': _day,
          'status': _status,
          'shift': _shift.text.trim().isEmpty ? null : _shift.text.trim(),
          'notes': _notes.text.trim().isEmpty ? null : _notes.text.trim(),
        },
      );
      if (!mounted) return;
      Navigator.of(context).pop(true);
      messenger.showSnackBar(SnackBar(
          content: Text('Attendance recorded · $_name · $_status on $_day')));
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text('Could not record attendance. ${e.message}')));
    } catch (_) {
      if (!mounted) return;
      setState(() => _saving = false);
      messenger.showSnackBar(const SnackBar(content: Text('Could not record attendance.')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final tokens = context.tokens;
    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Attendance', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
            Text(_name, style: TextStyle(fontSize: 11.5, color: tokens.mutedForeground)),
          ],
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 28),
        children: [
          FormSection(title: 'Day', color: SectionColor.indigo, columns: 1, children: [
            AppField(
              label: 'Date',
              full: true,
              child: AppDateField(value: _date, onChanged: (d) => setState(() => _date = d ?? _date)),
            ),
            AppField(
              label: 'Status',
              full: true,
              child: AppSelect<String>(
                value: _status,
                items: [for (final s in _statuses) AppSelectItem(value: s, label: s)],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ),
            AppField(label: 'Shift', full: true,
                child: AppInput(controller: _shift, hintText: 'e.g. Morning')),
            AppField(label: 'Notes', full: true, child: AppInput(controller: _notes)),
          ]),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: AppButton(
                  label: 'Cancel',
                  variant: AppButtonVariant.ghost,
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  onPressed: _saving ? null : () => Navigator.of(context).pop(),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: AppButton(
                  label: 'Save attendance',
                  size: AppButtonSize.lg,
                  fullWidth: true,
                  busy: _saving,
                  onPressed: _saving ? null : _save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

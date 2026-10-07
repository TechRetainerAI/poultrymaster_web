// Settings → Terms & Conditions (app/terms/page.tsx).

import 'package:flutter/material.dart';

import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/trackers/tracker_widgets.dart';

const termsSections = [
  ('Use of the Platform',
      'VisibilityCore is provided to help you manage poultry farm operations, records, and reporting. You agree to use the platform only for lawful farm management activities.'),
  ('Data Responsibility',
      'You are responsible for ensuring that data entered into your account is accurate and up to date. This includes flock data, inventory, financial data, and employee records.'),
  ('Privacy and Access',
      'Only authorized users within your farm team should have access to your account. Keep login credentials secure and update passwords when staff roles change.'),
  ('Service Availability',
      'We strive to keep the service available and reliable. Planned maintenance or unexpected outages may occur, and we continuously work to reduce interruptions.'),
  ('Limitation of Liability',
      'The platform is provided as a farm management tool. Final business decisions remain your responsibility, including production, medication, and financial actions.'),
  ('Updates to Terms',
      'These terms may be updated from time to time. Continued use of the platform after updates means you accept the revised terms and conditions.'),
];

class TermsScreen extends StatelessWidget {
  const TermsScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, session, company, href: '/terms');
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Terms & Conditions')),
      body: ListView(padding: const EdgeInsets.fromLTRB(16, 16, 16, 28), children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Terms & Conditions', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: TColors.slate900)),
              SizedBox(height: 4),
              Text('Please read these terms before using VisibilityCore.', style: TextStyle(color: TColors.slate600)),
            ]),
          ),
          const SizedBox(width: 8),
          const TBadge('Effective immediately', bg: Color(0xFFFFF7ED), fg: Color(0xFFC2410C), border: Color(0xFFFDBA74)),
        ]),
        const SizedBox(height: 20),
        TCard(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Agreement Overview', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: TColors.slate900)),
            const SizedBox(height: 4),
            const Text('This summary highlights the key terms that govern use of the platform.', style: TextStyle(fontSize: 14, color: TColors.slate500)),
            const SizedBox(height: 16),
            for (final (title, body) in termsSections) ...[
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: TColors.slate900)),
              const SizedBox(height: 6),
              Text(body, style: const TextStyle(fontSize: 14, height: 1.5, color: TColors.slate700)),
              const SizedBox(height: 18),
            ],
          ]),
        ),
      ]),
    );
  }
}

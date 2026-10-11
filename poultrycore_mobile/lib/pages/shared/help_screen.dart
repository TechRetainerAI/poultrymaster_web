// Settings → Help Center (app/help/page.tsx): search, the Feature Guide,
// the FAQ with category chips and Collapse / Expand all, and Need More Help?

import 'package:flutter/material.dart';

import '../../design/ui/inputs.dart';
import '../../models/company.dart';
import '../../state/session.dart';
import '../../widgets/module_sidebar.dart';
import '../poultry/reports/report_routes.dart' show openAppHref;
import '../poultry/trackers/tracker_widgets.dart';

const helpFaqs = <({String category, String question, String answer})>[
  (category: 'Getting Started', question: 'How do I set up my farm?', answer: 'Go to Settings from the sidebar menu. Enter your farm name, location, and preferred currency. Click \'Edit Settings\' to modify and \'Save Changes\' to confirm.'),
  (category: 'Getting Started', question: 'How do I add employees/staff?', answer: 'Navigate to the Employees page from the sidebar. Click \'Add Employee\' and fill in their details including name, email, phone, and role. Staff members can be given limited access compared to admins.'),
  (category: 'Flocks', question: 'How do I create a new flock?', answer: 'Go to Flocks from the sidebar and click \'Add Flock\'. Enter the flock name, breed, quantity, start date, and assign it to a house. Flocks can be marked as active or inactive.'),
  (category: 'Flocks', question: 'What are flock batches?', answer: 'Flock batches allow you to group birds within a flock by arrival date or source. Navigate to Flock Batches to manage batches. Each batch tracks its own quantity and metadata.'),
  (category: 'Flocks', question: 'How do I deactivate a flock?', answer: 'On the Flocks page, edit the flock you want to deactivate. Set the \'Active\' toggle to off and provide a reason for inactivation. The flock will remain in your records for reporting purposes.'),
  (category: 'Production', question: 'How do I log daily production?', answer: 'Go to Production Records and click \'Log Production\'. Select the flock, date, and enter egg counts for 9 AM, 12 PM, and 4 PM collections. You can also record broken eggs, feed usage, and medication.'),
  (category: 'Production', question: 'How are egg totals calculated?', answer: 'Egg totals are displayed in both raw counts and crates. One crate equals 30 eggs. For example, 95 eggs = 3 crates + 5 pieces (3c + 5p).'),
  (category: 'Production', question: 'Where can I see egg production trends?', answer: 'Use Egg sorting for daily collection by flock and totals by size. Use Egg tracker (under Analytics) for the egg inventory ledger from production and sales. The Reports page provides charts for production trends over time.'),
  (category: 'Feed & Inventory', question: 'How do I record feed usage?', answer: 'Navigate to Feed Usage and click \'Add Usage\'. Select the flock, date, feed type, and quantity in kg. Feed records are automatically linked to production records for the same flock and date.'),
  (category: 'Feed & Inventory', question: 'How do I manage inventory?', answer: 'The Inventory page lets you track all farm supplies including feed, medication, equipment, and eggs. Add items with quantities, unit prices, suppliers, and expiry dates. Use filters to search and categorize.'),
  (category: 'Sales & Expenses', question: 'How do I record a sale?', answer: 'Go to Sales and click \'Record Sale\'. Select the customer, items sold (eggs in crates/pieces, or other products), quantity, unit price, and payment method. The system calculates totals automatically.'),
  (category: 'Sales & Expenses', question: 'How do I track expenses?', answer: 'Navigate to Expenses and click \'Add Expense\'. Select the flock, category (Feed, Veterinary, Equipment, Labor, Utilities, Other), enter the amount, payment method, and description.'),
  (category: 'Sales & Expenses', question: 'Can I export sales or expense data?', answer: 'Yes! On both the Sales and Expenses pages, you\'ll find PDF and CSV export buttons in the filter bar. Exports include all currently filtered records.'),
  (category: 'Customers', question: 'How do I manage customers?', answer: 'The Customers page lets you add, edit, and delete customer records. Each customer has a name, email, phone, city, and address. Customers can be linked to sales for tracking.'),
  (category: 'Reports', question: 'What reports are available?', answer: 'The Reports page provides production summaries, financial overviews, flock performance metrics, and trend analysis. Data can be filtered by date range and flock for detailed insights.'),
  (category: 'Health', question: 'How do I log health records?', answer: 'Navigate to Health Records from the sidebar. Record vaccinations, treatments, and health observations for each flock. Track medication usage and health trends over time.'),
  (category: 'Account', question: 'How do I change my password?', answer: 'Go to your Profile page by clicking the user icon in the top-right corner of the header. You\'ll find the option to update your password and other account settings.'),
  (category: 'Account', question: 'What\'s the difference between Admin and Staff roles?', answer: 'Admins have full access to all features including settings, employee management, and delete operations. Staff members have limited access — they can view and create records but may not be able to delete or access certain admin-only features.'),
];

const helpFeatureGuides = <(IconData, String, String, String, Color, Color)>[
  (Icons.flutter_dash, 'Flocks', 'Manage your flocks, batches, and bird tracking', '/flocks', Color(0xFFFEF3C7), Color(0xFFB45309)),
  (Icons.egg_outlined, 'Production', 'Log daily egg production and track metrics', '/production-records', Color(0xFFE0F2FE), Color(0xFF0369A1)),
  (Icons.inventory_2_outlined, 'Feed Usage', 'Record and monitor feed consumption', '/feed-usage', Color(0xFFECFCCB), Color(0xFF4D7C0F)),
  (Icons.shopping_cart_outlined, 'Sales', 'Record sales and track revenue', '/sales', Color(0xFFEDE9FE), Color(0xFF6D28D9)),
  (Icons.attach_money, 'Expenses', 'Track costs and financial records', '/expenses', Color(0xFFFFE4E6), Color(0xFFBE123C)),
  (Icons.people_outline, 'Customers', 'Manage your customer database', '/customers', Color(0xFFCCFBF1), Color(0xFF0F766E)),
  (Icons.bar_chart, 'Reports', 'View analytics and generate reports', '/reports', Color(0xFFE0E7FF), Color(0xFF4338CA)),
  (Icons.monitor_heart_outlined, 'Health Records', 'Track vaccinations and treatments', '/health', Color(0xFFFEE2E2), Color(0xFFB91C1C)),
  (Icons.description_outlined, 'Inventory', 'Manage farm supplies and stock', '/inventory', Color(0xFFD1FAE5), Color(0xFF047857)),
  (Icons.settings_outlined, 'Company Setup', 'Configure farm preferences', '/poultry-company-setup', Color(0xFFE2E8F0), Color(0xFF334155)),
];

/// A colour per FAQ category: the chosen chip, the rail, the badge.
const _tones = <String, (Color, Color, Color, Color)>{
  'Getting Started': (Color(0xFF059669), Color(0xFF34D399), Color(0xFFECFDF5), Color(0xFF047857)),
  'Flocks': (Color(0xFFD97706), Color(0xFFFBBF24), Color(0xFFFFFBEB), Color(0xFFB45309)),
  'Production': (Color(0xFF0284C7), Color(0xFF38BDF8), Color(0xFFF0F9FF), Color(0xFF0369A1)),
  'Feed & Inventory': (Color(0xFF65A30D), Color(0xFFA3E635), Color(0xFFF7FEE7), Color(0xFF4D7C0F)),
  'Sales & Expenses': (Color(0xFF7C3AED), Color(0xFFA78BFA), Color(0xFFF5F3FF), Color(0xFF6D28D9)),
  'Customers': (Color(0xFF0D9488), Color(0xFF2DD4BF), Color(0xFFF0FDFA), Color(0xFF0F766E)),
  'Health': (Color(0xFFE11D48), Color(0xFFFB7185), Color(0xFFFFF1F2), Color(0xFFBE123C)),
  'Reports': (Color(0xFF4F46E5), Color(0xFF818CF8), Color(0xFFEEF2FF), Color(0xFF4338CA)),
  'Account': (Color(0xFF334155), Color(0xFF94A3B8), Color(0xFFF1F5F9), Color(0xFF334155)),
};
const _fallbackTone = (Color(0xFF4F46E5), Color(0xFFCBD5E1), Color(0xFFF8FAFC), Color(0xFF475569));

class HelpCenterScreen extends StatefulWidget {
  const HelpCenterScreen({super.key, required this.session, required this.company});
  final Session session;
  final Company company;
  @override
  State<HelpCenterScreen> createState() => _HelpCenterScreenState();
}

class _HelpCenterScreenState extends State<HelpCenterScreen> {
  String _q = '', _category = 'All';
  final _closed = <String>{};

  @override
  Widget build(BuildContext context) {
    final lead = sidebarLeading(context, widget.session, widget.company, href: '/help');
    final q = _q.toLowerCase();
    final categories = ['All', ...{for (final f in helpFaqs) f.category}];
    final filtered = [
      for (final f in helpFaqs)
        if ((q.isEmpty || f.question.toLowerCase().contains(q) || f.answer.toLowerCase().contains(q)) && (_category == 'All' || f.category == _category)) f,
    ];
    final allOpen = filtered.every((f) => !_closed.contains(f.question));
    return Scaffold(
      appBar: AppBar(leading: lead.leading, leadingWidth: lead.width, title: const Text('Help Center')),
      body: ListView(padding: const EdgeInsets.fromLTRB(14, 16, 14, 28), children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(color: Color(0xFFE0E7FF), shape: BoxShape.circle),
            child: const Icon(Icons.help_outline, size: 32, color: Color(0xFF4F46E5)),
          ),
        ),
        const SizedBox(height: 12),
        const Text('Help Center', textAlign: TextAlign.center, style: TextStyle(fontSize: 26, fontWeight: FontWeight.w700, color: TColors.slate900)),
        const SizedBox(height: 6),
        const Text('Find answers to common questions, learn how to use VisibilityCore features, and get support.',
            textAlign: TextAlign.center, style: TextStyle(color: TColors.slate600)),
        const SizedBox(height: 16),
        AppInput(
          hintText: 'Search for help topics...',
          prefixIcon: const Icon(Icons.search, color: TColors.slate400),
          onChanged: (v) => setState(() => _q = v),
        ),
        const SizedBox(height: 22),
        const Row(children: [
          Icon(Icons.menu_book_outlined, size: 20, color: Color(0xFF4F46E5)),
          SizedBox(width: 8),
          Text('Feature Guide', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
        ]),
        const SizedBox(height: 12),
        LayoutBuilder(builder: (context, c) {
          final w = (c.maxWidth - 10) / 2;
          return Wrap(spacing: 10, runSpacing: 10, children: [
            for (final (icon, title, _, path, bg, fg) in helpFeatureGuides)
              SizedBox(
                width: w,
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => openAppHref(context, widget.session, widget.company, path, label: title),
                  child: TCard(
                    child: Column(children: [
                      Container(width: 44, height: 44, decoration: BoxDecoration(color: bg, shape: BoxShape.circle), child: Icon(icon, color: fg)),
                      const SizedBox(height: 8),
                      Text(title, textAlign: TextAlign.center, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                    ]),
                  ),
                ),
              ),
          ]);
        }),
        const SizedBox(height: 22),
        Wrap(alignment: WrapAlignment.spaceBetween, crossAxisAlignment: WrapCrossAlignment.center, spacing: 8, runSpacing: 4, children: [
          Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: 6, children: [
            const Icon(Icons.help_outline, size: 20, color: Color(0xFF4F46E5)),
            const Text('Frequently Asked Questions', style: TextStyle(fontSize: 17, fontWeight: FontWeight.w600, color: TColors.slate900)),
            Text('${filtered.length} ${filtered.length == 1 ? 'answer' : 'answers'}', style: const TextStyle(fontSize: 13, color: TColors.slate500)),
          ]),
          if (filtered.isNotEmpty)
            InkWell(
              onTap: () => setState(() {
                if (allOpen) {
                  _closed.addAll(filtered.map((f) => f.question));
                } else {
                  _closed.clear();
                }
              }),
              child: Text(allOpen ? 'Collapse all' : 'Expand all', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF4F46E5))),
            ),
        ]),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [for (final cat in categories) _chip(cat)]),
        const SizedBox(height: 14),
        if (filtered.isEmpty)
          TCard(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('No results found for "$_q". Try a different search term.', textAlign: TextAlign.center, style: const TextStyle(color: TColors.slate500)),
            ),
          )
        else
          for (final f in filtered) _faq(f),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: const Color(0x80EEF2FF), border: Border.all(color: const Color(0xFFC7D2FE)), borderRadius: BorderRadius.circular(12)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Row(children: [
              Icon(Icons.mail_outline, size: 20, color: Color(0xFF312E81)),
              SizedBox(width: 8),
              Text('Need More Help?', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: Color(0xFF312E81))),
            ]),
            const SizedBox(height: 4),
            const Text("Can't find what you're looking for? Reach out to our support team.", style: TextStyle(fontSize: 14, color: Color(0xFF4338CA))),
            const SizedBox(height: 14),
            for (final (icon, title, value) in const [
              (Icons.mail_outline, 'Email Support', 'techretainer@gmail.com'),
              (Icons.phone_outlined, 'Phone Support', '+1 (917) 420-2946 / 0533431086'),
            ])
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(8)),
                child: Row(children: [
                  Icon(icon, size: 20, color: const Color(0xFF4F46E5)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: TColors.slate900)),
                      SelectableText(value, style: const TextStyle(fontSize: 14, color: TColors.slate600)),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _chip(String cat) {
    final tone = cat == 'All' ? _fallbackTone : (_tones[cat] ?? _fallbackTone);
    final on = _category == cat;
    final n = cat == 'All' ? helpFaqs.length : helpFaqs.where((f) => f.category == cat).length;
    return InkWell(
      key: ValueKey('faq-cat-$cat'),
      borderRadius: BorderRadius.circular(999),
      onTap: () => setState(() => _category = cat),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: on ? tone.$1 : Colors.white,
          border: Border.all(color: on ? tone.$1 : TColors.slate200),
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text.rich(TextSpan(children: [
          TextSpan(text: cat, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: on ? Colors.white : TColors.slate800)),
          TextSpan(text: '  $n', style: TextStyle(fontSize: 10, color: on ? Colors.white70 : TColors.slate400)),
        ])),
      ),
    );
  }

  Widget _faq(({String category, String question, String answer}) f) {
    final tone = _tones[f.category] ?? _fallbackTone;
    final open = !_closed.contains(f.question);
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: TColors.slate200),
      ),
      child: Container(
        decoration: BoxDecoration(border: Border(left: BorderSide(color: tone.$2, width: 4))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          InkWell(
            onTap: () => setState(() {
              if (!_closed.remove(f.question)) _closed.add(f.question);
            }),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    TBadge(f.category, bg: tone.$3, fg: tone.$4),
                    const SizedBox(height: 6),
                    Text(f.question, style: const TextStyle(fontWeight: FontWeight.w500, color: TColors.slate900)),
                  ]),
                ),
                Icon(open ? Icons.expand_less : Icons.expand_more, color: TColors.slate400),
              ]),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Text(f.answer, style: const TextStyle(fontSize: 14, height: 1.5, color: TColors.slate600)),
            ),
        ]),
      ),
    );
  }
}

// Contact support (components/help/contact-support.tsx + lib/help/support.ts):
// the email and call lines on top, then a message box sent by WhatsApp or by
// email. Nothing goes to our server: the message is handed to the phone's own
// WhatsApp or email app, and only the user's own words are sent -- no company,
// page or device details, and no subject line.
//
// Used on the Help Center and twice on the Business Office (top and bottom),
// as on the web.

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../design/ui/inputs.dart';
import 'package:poultrycore_mobile/design/tone.dart';
import '../../poultry/trackers/tracker_widgets.dart' show TColors;

const supportEmail = 'techretainer@gmail.com';

/// Display form, USA line first (support.ts SUPPORT_PHONES).
const supportPhones = ['+1 (917) 420-2946', '+233 50 363 8419', '053 343 1086'];

/// International form of the US line, for wa.me (digits only, no +).
const supportWhatsapp = '19174202946';

String mailtoLink(String message) {
  final body = message.trim();
  return body.isEmpty ? 'mailto:$supportEmail' : 'mailto:$supportEmail?body=${Uri.encodeComponent(body)}';
}

String whatsappLink(String message) {
  final text = message.trim();
  return text.isEmpty ? 'https://wa.me/$supportWhatsapp' : 'https://wa.me/$supportWhatsapp?text=${Uri.encodeComponent(text)}';
}

/// The web's tel: href: digits and + only.
String telLink(String phone) => 'tel:${phone.replaceAll(RegExp(r'[^\d+]'), '')}';

/// Opens a link outside the app (WhatsApp, the mail app, the dialer, YouTube).
/// Tests swap it to record what would open.
Future<bool> Function(String url) openExternalLink = (url) async {
  try {
    return await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    return false;
  }
};

/// Opens [url]; says so in a snackbar when no app on the phone can.
Future<void> openExternal(BuildContext context, String url) async {
  final ok = await openExternalLink(url);
  if (!ok && context.mounted) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No app on this phone can open that link.')));
  }
}

const _indigo50 = Tone.bg(0x80EEF2FF);
const _indigo100 = Tone.line(0xFFE0E7FF);
const _indigo200 = Tone.line(0xFFC7D2FE);
const _indigo500 = Tone.fg(0xFF6366F1);
const _indigo700 = Tone.fg(0xFF4338CA);
const _indigo900 = Tone.fg(0xFF312E81);
const _emerald600 = Tone.bg(0xFF059669);

class ContactSupport extends StatefulWidget {
  const ContactSupport({super.key});
  @override
  State<ContactSupport> createState() => ContactSupportState();
}

class ContactSupportState extends State<ContactSupport> {
  final _message = TextEditingController();
  final _focus = FocusNode();

  /// The web's ask(): put a question in the box and bring the card into view.
  void ask(String message) {
    setState(() => _message.text = message);
    Scrollable.ensureVisible(context, alignment: 0.5, duration: const Duration(milliseconds: 300));
    Future.delayed(const Duration(milliseconds: 300), () {
      if (mounted) _focus.requestFocus();
    });
  }

  @override
  void dispose() {
    _message.dispose();
    _focus.dispose();
    super.dispose();
  }

  Widget _contact(IconData icon, String text, String href, Key key) => InkWell(
        key: key,
        onTap: () => openExternal(context, href),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 16, color: _indigo500),
            const SizedBox(width: 8),
            Flexible(child: Text(text, style: const TextStyle(fontSize: 14, color: TColors.slate600))),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('contact-support'),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _indigo50,
        border: Border.all(color: _indigo200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const Row(children: [
          Icon(Icons.chat_bubble_outline, size: 20, color: _indigo900),
          SizedBox(width: 8),
          Expanded(child: Text('Contact support', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600, color: _indigo900))),
        ]),
        const SizedBox(height: 4),
        const Text('Describe what you were doing and what went wrong. Only your message is sent.',
            style: TextStyle(fontSize: 14, color: _indigo700)),
        const SizedBox(height: 12),
        // Contacts on top, so farms see "call us" first.
        Wrap(spacing: 24, runSpacing: 4, children: [
          _contact(Icons.mail_outline, supportEmail, 'mailto:$supportEmail', const ValueKey('support-email')),
          for (final p in supportPhones) _contact(Icons.phone_outlined, p, telLink(p), ValueKey('support-call-$p')),
        ]),
        const Padding(padding: EdgeInsets.only(top: 10, bottom: 12), child: Divider(height: 1, color: _indigo100)),
        AppInput(
          key: const ValueKey('support-message'),
          controller: _message,
          focusNode: _focus,
          keyboardType: TextInputType.multiline,
          minLines: 3,
          maxLines: 7,
          hintText: "e.g. I recorded a sale this morning but it isn't showing on Daily Closing.",
        ),
        const SizedBox(height: 12),
        Wrap(spacing: 8, runSpacing: 8, children: [
          FilledButton.icon(
            key: const ValueKey('support-whatsapp'),
            style: FilledButton.styleFrom(backgroundColor: Tone.button(_emerald600), foregroundColor: Colors.white),
            onPressed: () => openExternal(context, whatsappLink(_message.text)),
            icon: const Icon(Icons.chat_bubble_outline, size: 16),
            label: const Text('Send on WhatsApp'),
          ),
          OutlinedButton.icon(
            key: const ValueKey('support-mail'),
            style: OutlinedButton.styleFrom(backgroundColor: Tone.button(Tone.bg(0xFFFFFFFF)), foregroundColor: TColors.slate800),
            onPressed: () => openExternal(context, mailtoLink(_message.text)),
            icon: const Icon(Icons.mail_outline, size: 16),
            label: const Text('Send by email'),
          ),
        ]),
      ]),
    );
  }
}

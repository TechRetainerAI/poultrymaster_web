import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme.dart';
import '../../models/session.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

class OtpScreen extends StatefulWidget {
  final TwoFactorChallenge challenge;
  const OtpScreen({super.key, required this.challenge});

  @override
  State<OtpScreen> createState() => _OtpScreenState();
}

class _OtpScreenState extends State<OtpScreen> {
  final _code = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.trim().isEmpty) return;
    setState(() => _busy = true);
    try {
      await AuthService.verifyOtp(widget.challenge, _code.text.trim());
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) showSnack(context, e.toString(), error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Two-factor code')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Iconsax.sms_tracking, size: 56, color: AppColors.primary),
              const SizedBox(height: 20),
              Text('Check your email', textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: 8),
              Text(widget.challenge.message,
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: 28),
              TextField(
                controller: _code,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                autofocus: true,
                style: t.headlineSmall?.copyWith(letterSpacing: 8),
                decoration: const InputDecoration(hintText: '••••••'),
                onSubmitted: (_) => _verify(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _verify,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Verify & sign in'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:iconsax_flutter/iconsax_flutter.dart';

import '../../core/theme.dart';
import '../../services/auth_service.dart';
import '../../widgets/common.dart';

class ForgotPasswordScreen extends StatefulWidget {
  const ForgotPasswordScreen({super.key});

  @override
  State<ForgotPasswordScreen> createState() => _ForgotPasswordScreenState();
}

class _ForgotPasswordScreenState extends State<ForgotPasswordScreen> {
  final _email = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final email = _email.text.trim();
    if (!email.contains('@')) {
      showSnack(context, 'Enter a valid email address', error: true);
      return;
    }
    setState(() => _busy = true);
    try {
      final message = await AuthService.forgotPassword(email);
      if (!mounted) return;
      showSnack(context, message);
      Navigator.of(context).pop();
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
      appBar: AppBar(title: const Text('Reset password')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Iconsax.key, size: 56, color: AppColors.primary),
              const SizedBox(height: 20),
              Text('Forgot your password?',
                  textAlign: TextAlign.center, style: t.headlineSmall),
              const SizedBox(height: 8),
              Text('Enter your account email and we will send you a reset link.',
                  textAlign: TextAlign.center,
                  style: t.bodyMedium?.copyWith(color: AppColors.inkMuted)),
              const SizedBox(height: 24),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(
                    labelText: 'Email', prefixIcon: Icon(Iconsax.sms, size: 20)),
                onSubmitted: (_) => _submit(),
              ),
              const SizedBox(height: 20),
              FilledButton(
                onPressed: _busy ? null : _submit,
                child: _busy
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child:
                            CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                    : const Text('Send reset link'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

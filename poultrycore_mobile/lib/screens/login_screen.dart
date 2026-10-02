import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/auth_api.dart';
import '../config/env.dart';
import '../design/login_palette.dart';
import '../state/session.dart';
import '../widgets/env_banner.dart';

/// Sign-in, matching `app/login/page.tsx` on the live site.
///
/// The page is a dark slate panel with orange accents — not the neutral theme
/// the rest of the app uses. On a phone the web shows only this panel (the
/// marketing column is `hidden lg:flex`), so this screen is the mobile page.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.session, required this.onSignedIn});

  final Session session;
  final VoidCallback onSignedIn;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _orgCode = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _code = TextEditingController();

  bool _busy = false;
  bool _showPassword = false;
  bool _rememberMe = false;
  String? _error;
  String? _twoFactorFor;

  @override
  void initState() {
    super.initState();
    // The web pre-fills the remembered Business Office code and hides the field
    // until the user chooses to change office.
    final remembered = widget.session.tokens.rememberedOrgCode;
    if (remembered != null) _orgCode.text = remembered;
  }

  @override
  void dispose() {
    _orgCode.dispose();
    _username.dispose();
    _password.dispose();
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    final LoginOutcome outcome;
    if (_twoFactorFor != null) {
      outcome = await widget.session.auth
          .verifyTwoFactor(username: _twoFactorFor!, code: _code.text.trim());
    } else {
      outcome = await widget.session.auth.login(
        username: _username.text.trim(),
        password: _password.text,
        rememberMe: _rememberMe,
      );
    }

    if (!mounted) return;

    if (outcome.ok) {
      await widget.session.applyOrgScope(
        orgCode: _orgCode.text.trim(),
        remember: _rememberMe,
      );
      if (!mounted) return;
      widget.onSignedIn();
      return;
    }

    setState(() {
      _busy = false;
      if (outcome.requiresTwoFactor) {
        _twoFactorFor = outcome.username ?? _username.text.trim();
        _error = null;
      } else {
        _error = outcome.message ?? 'Login failed.';
      }
    });

    if (outcome.requiresTwoFactor && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(outcome.message ?? 'A code was sent to your email.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final twoFactor = _twoFactorFor != null;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(gradient: LoginPalette.panel),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              // p-8
              padding: const EdgeInsets.all(32),
              child: ConstrainedBox(
                // max-w-md
                constraints: const BoxConstraints(maxWidth: 448),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: EnvBanner()),
                      const SizedBox(height: 24),

                      // w-16 h-16 rounded-full bg-white/10
                      Center(
                        child: Container(
                          height: 64,
                          width: 64,
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: .10),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.visibility_rounded,
                              size: 34, color: Colors.white),
                        ),
                      ),
                      const SizedBox(height: 32), // mb-8

                      // text-3xl font-bold text-white
                      Text(
                        twoFactor ? 'Verify' : 'Sign In',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: -.5,
                        ),
                      ),
                      const SizedBox(height: 32),

                      if (_error != null) ...[
                        _ErrorBlock(message: _error!),
                        const SizedBox(height: 24), // mb-6
                      ],

                      if (!twoFactor) ...[
                        _DarkField(
                          controller: _orgCode,
                          hint: 'Organization Code',
                          icon: Icons.apartment_outlined,
                          iconColor: LoginPalette.orange300,
                          textCapitalization: TextCapitalization.characters,
                          formatters: [
                            FilteringTextInputFormatter.allow(RegExp(r'[A-Za-z0-9_\-]')),
                            LengthLimitingTextInputFormatter(30),
                            _UpperCaseFormatter(),
                          ],
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Tick “Remember me” below to keep this Business Office for next time.',
                          style: TextStyle(fontSize: 12, color: LoginPalette.slate400),
                        ),
                        const SizedBox(height: 24), // space-y-6

                        _DarkField(
                          controller: _username,
                          hint: 'Username',
                          icon: Icons.person_outline,
                          textInputAction: TextInputAction.next,
                          validator: (v) => (v == null || v.trim().isEmpty)
                              ? 'Enter your username'
                              : null,
                        ),
                        const SizedBox(height: 24),

                        _DarkField(
                          controller: _password,
                          hint: 'Password',
                          icon: Icons.lock_outline,
                          obscure: !_showPassword,
                          validator: (v) =>
                              (v == null || v.isEmpty) ? 'Enter your password' : null,
                          onSubmitted: (_) => _submit(),
                          trailing: _EyeButton(
                            visible: _showPassword,
                            onTap: _busy
                                ? null
                                : () =>
                                    setState(() => _showPassword = !_showPassword),
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Remember me  ·  Forgot password?
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Flexible(
                              child: InkWell(
                                onTap: _busy
                                    ? null
                                    : () =>
                                        setState(() => _rememberMe = !_rememberMe),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    SizedBox(
                                      height: 18,
                                      width: 18,
                                      child: Checkbox(
                                        value: _rememberMe,
                                        onChanged: _busy
                                            ? null
                                            : (v) => setState(
                                                () => _rememberMe = v ?? false),
                                        side: const BorderSide(
                                            color: LoginPalette.slate500),
                                        activeColor: LoginPalette.orange500,
                                        checkColor: Colors.white,
                                        materialTapTargetSize:
                                            MaterialTapTargetSize.shrinkWrap,
                                        visualDensity: VisualDensity.compact,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    const Text('Remember me',
                                        style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w500,
                                            color: Colors.white)),
                                  ],
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: _busy ? null : () => _notYet('Forgot password'),
                              child: const Text('Forgot password?',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: LoginPalette.orange400)),
                            ),
                          ],
                        ),
                      ] else ...[
                        _DarkField(
                          controller: _code,
                          hint: 'Verification code',
                          icon: Icons.mark_email_unread_outlined,
                          keyboardType: TextInputType.number,
                          formatters: [FilteringTextInputFormatter.digitsOnly],
                          onSubmitted: (_) => _submit(),
                          validator: (v) =>
                              (v == null || v.trim().isEmpty) ? 'Enter the code' : null,
                        ),
                        const SizedBox(height: 12),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: GestureDetector(
                            onTap: _busy
                                ? null
                                : () => setState(() {
                                      _twoFactorFor = null;
                                      _code.clear();
                                    }),
                            child: const Text('Use a different account',
                                style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w500,
                                    color: LoginPalette.orange400)),
                          ),
                        ),
                      ],

                      const SizedBox(height: 24),

                      // w-full h-12 bg-orange-500 text-white font-medium text-base
                      SizedBox(
                        height: 48,
                        child: FilledButton(
                          onPressed: _busy ? null : _submit,
                          style: FilledButton.styleFrom(
                            backgroundColor: LoginPalette.orange500,
                            disabledBackgroundColor:
                                LoginPalette.orange500.withValues(alpha: .5),
                            foregroundColor: Colors.white,
                            disabledForegroundColor:
                                Colors.white.withValues(alpha: .8),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                          child: Text(
                            _busy
                                ? 'Signing in...'
                                : (twoFactor ? 'Verify' : 'Sign In'),
                            style: const TextStyle(
                                fontSize: 16, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),

                      Center(
                        child: Wrap(
                          alignment: WrapAlignment.center,
                          children: [
                            const Text('Not registered? ',
                                style: TextStyle(
                                    fontSize: 14, color: LoginPalette.slate300)),
                            GestureDetector(
                              onTap: () => _notYet('Create an account'),
                              child: const Text('Create an account',
                                  style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,
                                      color: LoginPalette.orange400)),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 18),
                      Center(
                        child: Text(
                          '${Env.banner} · ${Uri.parse(Env.loginApi).host}',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              fontSize: 11, color: LoginPalette.slate400),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _notYet(String what) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$what is on the web at ${Uri.parse(Env.loginApi).host}.')),
    );
  }
}

/// h-12, bg-slate-700/50, border-slate-600, white text, slate-400 placeholder,
/// pl-10 with a slate-300 icon at left-3, orange-500 on focus.
class _DarkField extends StatelessWidget {
  const _DarkField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.iconColor = LoginPalette.slate300,
    this.obscure = false,
    this.validator,
    this.trailing,
    this.keyboardType,
    this.formatters,
    this.textInputAction,
    this.onSubmitted,
    this.textCapitalization = TextCapitalization.none,
  });

  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final Color iconColor;
  final bool obscure;
  final String? Function(String?)? validator;
  final Widget? trailing;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? formatters;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final TextCapitalization textCapitalization;

  @override
  Widget build(BuildContext context) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: c, width: w),
        );

    return TextFormField(
      controller: controller,
      obscureText: obscure,
      validator: validator,
      keyboardType: keyboardType,
      inputFormatters: formatters,
      textInputAction: textInputAction,
      onFieldSubmitted: onSubmitted,
      textCapitalization: textCapitalization,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      cursorColor: LoginPalette.orange500,
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: LoginPalette.slate400, fontSize: 15),
        filled: true,
        fillColor: LoginPalette.slate700.withValues(alpha: .5),
        isDense: true,
        constraints: const BoxConstraints(minHeight: 48), // h-12
        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        prefixIcon: Padding(
          padding: const EdgeInsets.only(left: 12, right: 8),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 0, minHeight: 0),
        suffixIcon: trailing,
        border: border(LoginPalette.slate600),
        enabledBorder: border(LoginPalette.slate600),
        focusedBorder: border(LoginPalette.orange500),
        errorBorder: border(LoginPalette.red500),
        focusedErrorBorder: border(LoginPalette.red500),
        errorStyle: const TextStyle(color: LoginPalette.red300, fontSize: 12),
      ),
    );
  }
}

/// The password reveal control: h-8 w-8, border-slate-500, bg-slate-600/60.
class _EyeButton extends StatelessWidget {
  const _EyeButton({required this.visible, required this.onTap});
  final bool visible;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: 32,
          width: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: LoginPalette.slate600.withValues(alpha: .6),
            border: Border.all(color: LoginPalette.slate500),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Icon(visible ? Icons.visibility_off : Icons.visibility,
              size: 18, color: LoginPalette.slate200),
        ),
      ),
    );
  }
}

/// bg-red-900/20, border-red-500/30, rounded-lg, text-red-300 text-sm.
class _ErrorBlock extends StatelessWidget {
  const _ErrorBlock({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 288), // max-h-72
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: LoginPalette.red900.withValues(alpha: .20),
        border: Border.all(color: LoginPalette.red500.withValues(alpha: .30)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: SingleChildScrollView(
        child: Text(message,
            style: const TextStyle(fontSize: 14, color: LoginPalette.red300)),
      ),
    );
  }
}

/// The web uppercases the organisation code as it is typed.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(TextEditingValue _, TextEditingValue next) =>
      next.copyWith(text: next.text.toUpperCase());
}

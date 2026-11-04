import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/custom_logo.dart';
import '../../services/server_api_service.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({Key? key}) : super(key: key);

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isLogin = true;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final l10n = AppLocalizations.of(context);
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (_isLogin) {
        final result = await ServerApiService.login(
          _emailController.text.trim(),
          _passwordController.text.trim(),
        );
        if (result['success'] == true && mounted) {
          Navigator.of(context).pop();
        } else {
          setState(() => _errorMessage = result['error'] ?? l10n.translate('loginFailed'));
        }
      } else {
        if (_passwordController.text != _confirmPasswordController.text) {
          throw Exception(l10n.translate('passwordsDoNotMatch'));
        }
        final result = await ServerApiService.signup({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'displayName': _emailController.text.trim().split('@').first,
        });
        if (result['success'] == true && mounted) {
          Navigator.of(context).pop();
        } else {
          setState(() => _errorMessage = result['error'] ?? l10n.translate('signupFailed'));
        }
      }
    } catch (e) {
      setState(() => _errorMessage = e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: colors.surface,
      body: SafeArea(
        child: Stack(
          children: [
            Positioned(
              top: 16,
              left: 16,
              child: IconButton(
                icon: Icon(
                  Directionality.of(context) == TextDirection.rtl
                      ? Icons.arrow_forward_rounded
                      : Icons.arrow_back_rounded,
                  color: colors.onSurface,
                ),
                tooltip: l10n.translate('back') ?? 'Back',
                constraints: const BoxConstraints(),
                padding: EdgeInsets.zero,
                visualDensity: VisualDensity.compact,
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            Center(
              child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  YallaNewsLogo(size: 72, color: colors.primary),
                  const SizedBox(height: 24),
                  Text(
                    _isLogin ? l10n.translate('login') : l10n.translate('signUp'),
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: colors.onSurface),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_errorMessage!, style: TextStyle(color: colors.onErrorContainer)),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: TextStyle(color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: l10n.translate('email'),
                      hintStyle: TextStyle(color: colors.onSurfaceVariant),
                      prefixIcon: Icon(Icons.email_rounded, color: colors.primary),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    validator: (v) => v != null && v.contains('@') ? null : l10n.translate('enterValidEmail'),
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: TextStyle(color: colors.onSurface),
                    decoration: InputDecoration(
                      hintText: l10n.translate('password'),
                      hintStyle: TextStyle(color: colors.onSurfaceVariant),
                      prefixIcon: Icon(Icons.lock_rounded, color: colors.primary),
                      filled: true,
                      fillColor: colors.surfaceContainerHighest,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    validator: (v) => v != null && v.length >= 6 ? null : l10n.translate('passwordMinLength'),
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      style: TextStyle(color: colors.onSurface),
                      decoration: InputDecoration(
                        hintText: l10n.translate('confirmPassword'),
                        hintStyle: TextStyle(color: colors.onSurfaceVariant),
                        prefixIcon: Icon(Icons.lock_outline_rounded, color: colors.primary),
                        filled: true,
                        fillColor: colors.surfaceContainerHighest,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v == _passwordController.text ? null : l10n.translate('passwordsDoNotMatch'),
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: colors.primary,
                        foregroundColor: colors.onPrimary,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ).copyWith(elevation: WidgetStateProperty.all(0)),
                      child: _isLoading
                          ? SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: colors.onPrimary, strokeWidth: 2))
                          : Text(_isLogin ? l10n.translate('login') : l10n.translate('signUp'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin ? l10n.translate('noAccount') : l10n.translate('hasAccount'),
                      style: TextStyle(color: colors.primary),
                    ),
                  ),
                ],
              ),
            ),
          ),
          ),
        ],
      ),
    ),
  );
  }
}

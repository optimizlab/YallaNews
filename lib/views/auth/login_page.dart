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
          setState(() => _errorMessage = result['error'] ?? 'Login failed');
        }
      } else {
        if (_passwordController.text != _confirmPasswordController.text) {
          throw Exception('Passwords do not match');
        }
        final result = await ServerApiService.signup({
          'email': _emailController.text.trim(),
          'password': _passwordController.text.trim(),
          'displayName': _emailController.text.trim().split('@').first,
        });
        if (result['success'] == true && mounted) {
          Navigator.of(context).pop();
        } else {
          setState(() => _errorMessage = result['error'] ?? 'Signup failed');
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
    return Scaffold(
      backgroundColor: const Color(0xFF1A1A2E),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const YallaNewsLogo(size: 72, color: Colors.white),
                  const SizedBox(height: 24),
                  Text(
                    _isLogin ? l10n.translate('login') : l10n.translate('signUp'),
                    style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w800, color: Colors.white),
                  ),
                  const SizedBox(height: 24),
                  if (_errorMessage != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFFC62828).withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(_errorMessage!, style: const TextStyle(color: Color(0xFFEF9A9A))),
                    ),
                    const SizedBox(height: 16),
                  ],
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.translate('email'),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.email_rounded, color: Color(0xFF64B5F6)),
                      filled: true,
                      fillColor: const Color(0xFF2A2A4A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    validator: (v) => v != null && v.contains('@') ? null : 'Enter a valid email',
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      hintText: l10n.translate('password'),
                      hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                      prefixIcon: const Icon(Icons.lock_rounded, color: Color(0xFF64B5F6)),
                      filled: true,
                      fillColor: const Color(0xFF2A2A4A),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                    validator: (v) => v != null && v.length >= 6 ? null : 'Password must be at least 6 characters',
                  ),
                  if (!_isLogin) ...[
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _confirmPasswordController,
                      obscureText: true,
                      style: const TextStyle(color: Colors.white),
                      decoration: InputDecoration(
                        hintText: l10n.translate('confirmPassword'),
                        hintStyle: TextStyle(color: Colors.white.withOpacity(0.5)),
                        prefixIcon: const Icon(Icons.lock_outline_rounded, color: Color(0xFF64B5F6)),
                        filled: true,
                        fillColor: const Color(0xFF2A2A4A),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                      validator: (v) => v == _passwordController.text ? null : 'Passwords do not match',
                    ),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _submit,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1565C0),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ).copyWith(elevation: WidgetStateProperty.all(0)),
                      child: _isLoading
                          ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : Text(_isLogin ? l10n.translate('login') : l10n.translate('signUp'), style: GoogleFonts.outfit(fontWeight: FontWeight.w700)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isLoading ? null : () => setState(() => _isLogin = !_isLogin),
                    child: Text(
                      _isLogin ? l10n.translate('noAccount') : l10n.translate('hasAccount'),
                      style: const TextStyle(color: Color(0xFFB0BEC5)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

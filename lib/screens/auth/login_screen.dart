import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
import '../../app/theme/brand_colors.dart';
import '../../widgets/design/design.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _verificationCodeController = TextEditingController();
  bool _isSignUp = false;
  bool _obscurePassword = true;

  // Hardcoded verification code
  static const String _validVerificationCode = 'KAKA2026';

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _verificationCodeController.dispose();
    super.dispose();
  }

  Future<void> _handleAuth() async {
    if (!_formKey.currentState!.validate()) return;

    // Validate verification code for sign up
    if (_isSignUp &&
        _verificationCodeController.text.trim() != _validVerificationCode) {
      // Show error for invalid verification code
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Invalid verification code. Please contact an administrator.'),
            backgroundColor: BrandColors.pinkDarker,
            duration: Duration(seconds: 4),
          ),
        );
      }
      return;
    }

    final authNotifier = ref.read(authNotifierProvider.notifier);
    _isSignUp
        ? await authNotifier.signUp(
            _emailController.text.trim(), _passwordController.text)
        : await authNotifier.signIn(
            _emailController.text.trim(), _passwordController.text);

    // Router will automatically redirect based on user role
    // Admin users -> /schools, Regular users -> /staff-link
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);
    final isLoading = authState.isLoading;

    final text = Theme.of(context).textTheme;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(AppTokens.gutter),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const AppIconTile(
                    icon: Icons.local_shipping_outlined,
                    size: 62,
                  ),
                  const SizedBox(height: 14),
                  Text('BTS Delivery', style: text.displaySmall),
                  const SizedBox(height: 6),
                  Text(
                    _isSignUp
                        ? 'Create your delivery account'
                        : 'Sign in to manage school deliveries',
                    style: text.bodySmall,
                  ),
                  const SizedBox(height: 24),
                  AppPanel(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          TextFormField(
                            controller: _emailController,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            decoration: const InputDecoration(
                              labelText: 'Email',
                              prefixIcon: Icon(Icons.mail_outline_rounded),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your email';
                              }
                              if (!RegExp(r'^[^@]+@[^@]+\.[^@]+')
                                  .hasMatch(value)) {
                                return 'Please enter a valid email address';
                              }
                              return null;
                            },
                            enabled: !isLoading,
                          ),
                          const SizedBox(height: 16),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            textInputAction: _isSignUp
                                ? TextInputAction.next
                                : TextInputAction.done,
                            decoration: InputDecoration(
                              labelText: 'Password',
                              prefixIcon:
                                  const Icon(Icons.lock_outline_rounded),
                              suffixIcon: IconButton(
                                icon: Icon(_obscurePassword
                                    ? Icons.visibility
                                    : Icons.visibility_off),
                                tooltip: _obscurePassword
                                    ? 'Show password'
                                    : 'Hide password',
                                onPressed: () {
                                  setState(() {
                                    _obscurePassword = !_obscurePassword;
                                  });
                                },
                              ),
                            ),
                            validator: (value) {
                              if (value == null || value.isEmpty) {
                                return 'Please enter your password';
                              }
                              if (_isSignUp && value.length < 6) {
                                return 'Password must be at least 6 characters';
                              }
                              return null;
                            },
                            onFieldSubmitted: (_) =>
                                _isSignUp ? null : _handleAuth(),
                            enabled: !isLoading,
                          ),

                          // Verification Code (only for sign up)
                          if (_isSignUp) ...[
                            const SizedBox(height: 16),
                            TextFormField(
                              controller: _verificationCodeController,
                              textInputAction: TextInputAction.done,
                              textCapitalization: TextCapitalization.characters,
                              decoration: const InputDecoration(
                                labelText: 'Verification Code',
                                hintText:
                                    'Enter code provided by administrator',
                                prefixIcon: Icon(Icons.verified_user_outlined),
                                helperText:
                                    'Contact your administrator for the verification code',
                                helperMaxLines: 2,
                              ),
                              validator: (value) {
                                if (value == null || value.trim().isEmpty) {
                                  return 'Please enter the verification code';
                                }
                                return null;
                              },
                              onFieldSubmitted: (_) => _handleAuth(),
                              enabled: !isLoading,
                            ),
                          ],
                          const SizedBox(height: 24),
                          FilledButton(
                            onPressed: isLoading ? null : _handleAuth,
                            child: isLoading
                                ? const SizedBox(
                                    height: 20,
                                    width: 20,
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2),
                                  )
                                : Text(_isSignUp ? 'Sign Up' : 'Sign In'),
                          ),
                          if (authState.hasError) ...[
                            const SizedBox(height: 12),
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: AppTone.pink.tint,
                                borderRadius: BorderRadius.circular(
                                    AppTokens.controlRadius),
                              ),
                              child: Text(
                                authState.error.toString(),
                                style: text.bodySmall
                                    ?.copyWith(color: AppTone.pink.ink),
                              ),
                            ),
                          ],
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: isLoading
                                ? null
                                : () {
                                    setState(() {
                                      _isSignUp = !_isSignUp;
                                      // Clear verification code when switching modes
                                      _verificationCodeController.clear();
                                    });
                                  },
                            child: Text(_isSignUp
                                ? 'Already have an account? Sign In'
                                : 'Don\'t have an account? Sign Up'),
                          ),
                        ],
                      ),
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

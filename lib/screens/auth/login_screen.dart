import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/auth_providers.dart';
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
    final colors = AppPalette.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.gutter, 24, AppTokens.gutter, 24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  AppLargeTitle(
                    title: 'BTS Delivery',
                    subtitle: _isSignUp
                        ? 'Create your delivery account'
                        : 'Sign in to manage school deliveries',
                  ),
                  const SizedBox(height: AppTokens.sectionGap),
                  AppPanel(
                    padding: const EdgeInsets.all(20),
                    child: Form(
                      key: _formKey,
                      child: AutofillGroup(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextFormField(
                              controller: _emailController,
                              keyboardType: TextInputType.emailAddress,
                              textInputAction: TextInputAction.next,
                              autofillHints: const [
                                AutofillHints.email,
                                AutofillHints.username,
                              ],
                              autocorrect: false,
                              decoration: const InputDecoration(
                                labelText: 'Email',
                                prefixIcon: Icon(AppIcons.email, size: 20),
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
                              autofillHints: [
                                _isSignUp
                                    ? AutofillHints.newPassword
                                    : AutofillHints.password,
                              ],
                              decoration: InputDecoration(
                                labelText: 'Password',
                                prefixIcon: const Icon(AppIcons.lock, size: 20),
                                suffixIcon: IconButton(
                                  icon: Icon(
                                    _obscurePassword
                                        ? AppIcons.showPassword
                                        : AppIcons.hidePassword,
                                    size: 20,
                                  ),
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
                                textCapitalization:
                                    TextCapitalization.characters,
                                autocorrect: false,
                                decoration: const InputDecoration(
                                  labelText: 'Verification code',
                                  hintText:
                                      'Enter code provided by administrator',
                                  prefixIcon:
                                      Icon(AppIcons.verificationCode, size: 20),
                                  helperText:
                                      'Contact your administrator for the verification code',
                                  helperMaxLines: 3,
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
                            AppPrimaryButton(
                              label: _isSignUp ? 'Sign up' : 'Sign in',
                              loading: isLoading,
                              onPressed: _handleAuth,
                            ),
                            if (authState.hasError) ...[
                              const SizedBox(height: 12),
                              Semantics(
                                liveRegion: true,
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: colors.errorContainer,
                                    borderRadius: BorderRadius.circular(
                                        AppTokens.controlRadius),
                                  ),
                                  child: Padding(
                                    padding: const EdgeInsets.all(12),
                                    child: Row(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        ExcludeSemantics(
                                          child: Icon(AppIcons.error,
                                              size: 20, color: colors.error),
                                        ),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            authState.error.toString(),
                                            style: AppTypography.subheadline
                                                .copyWith(color: colors.error),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(height: 12),
                            AppSecondaryButton(
                              onPressed: isLoading
                                  ? null
                                  : () {
                                      setState(() {
                                        _isSignUp = !_isSignUp;
                                        // Clear verification code when switching modes
                                        _verificationCodeController.clear();
                                      });
                                    },
                              label: _isSignUp
                                  ? 'Already have an account? Sign in'
                                  : 'Don’t have an account? Sign up',
                            ),
                          ],
                        ),
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

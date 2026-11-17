import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';
import '../../widgets/design/design.dart';

class StaffLinkScreen extends ConsumerStatefulWidget {
  const StaffLinkScreen({super.key});

  @override
  ConsumerState<StaffLinkScreen> createState() => _StaffLinkScreenState();
}

class _StaffLinkScreenState extends ConsumerState<StaffLinkScreen> {
  final _code = TextEditingController();

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_code.text.trim().isEmpty || ref.read(authNotifierProvider).isLoading) {
      return;
    }
    FocusScope.of(context).unfocus();
    await ref.read(authNotifierProvider.notifier).linkToStaff(_code.text);
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(authNotifierProvider);
    final staff = ref.watch(currentStaffProvider);
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
                  const AppLargeTitle(
                    title: 'Staff account',
                    subtitle:
                        'Enter the invitation code from your administrator.',
                  ),
                  const SizedBox(height: AppTokens.sectionGap),
                  AppPanel(
                    padding: const EdgeInsets.all(20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          children: [
                            const AppIconTile(icon: HeroiconsOutline.key),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Semantics(
                                header: true,
                                child: Text(
                                  'Link your staff account',
                                  style: AppTypography.headline
                                      .copyWith(color: colors.ink),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        TextField(
                          controller: _code,
                          decoration: const InputDecoration(
                            labelText: 'Invitation code',
                            prefixIcon: Icon(HeroiconsOutline.key, size: 20),
                          ),
                          inputFormatters: [
                            FilteringTextInputFormatter.allow(
                                RegExp(r'[a-zA-Z0-9_.-]')),
                          ],
                          autocorrect: false,
                          enableSuggestions: false,
                          autofillHints: const [AutofillHints.oneTimeCode],
                          textInputAction: TextInputAction.done,
                          onSubmitted: (_) => _submit(),
                        ),
                        if (state.hasError || staff.hasError) ...[
                          const SizedBox(height: 12),
                          Semantics(
                            liveRegion: true,
                            child: Text(
                              state.hasError
                                  ? state.error.toString()
                                  : 'Unable to check your account link.',
                              style: AppTypography.subheadline
                                  .copyWith(color: colors.error),
                            ),
                          ),
                          if (staff.hasError) ...[
                            const SizedBox(height: 8),
                            AppSecondaryButton(
                              label: 'Check link again',
                              icon: AppIcons.retry,
                              large: false,
                              onPressed: () =>
                                  ref.invalidate(currentStaffProvider),
                            ),
                          ],
                        ],
                        const SizedBox(height: 16),
                        AppPrimaryButton(
                          label: state.isLoading ? 'Linking…' : 'Link account',
                          onPressed: state.isLoading ? null : _submit,
                        ),
                        const SizedBox(height: 12),
                        AppSecondaryButton(
                          label: 'Sign out',
                          icon: AppIcons.logout,
                          onPressed: state.isLoading
                              ? null
                              : ref.read(authNotifierProvider.notifier).signOut,
                        ),
                      ],
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

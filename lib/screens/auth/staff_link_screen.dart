import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/auth_providers.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: const Text('Link your staff account'),
        actions: [
          TextButton(
            onPressed: state.isLoading
                ? null
                : ref.read(authNotifierProvider.notifier).signOut,
            child: const Text('Sign out'),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                      'Enter the invitation code from your administrator.'),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _code,
                    decoration: const InputDecoration(
                      labelText: 'Invitation code',
                      border: OutlineInputBorder(),
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(
                          RegExp(r'[a-zA-Z0-9_.-]')),
                    ],
                    autocorrect: false,
                    enableSuggestions: false,
                    onSubmitted: (_) => _submit(),
                  ),
                  if (state.hasError || staff.hasError) ...[
                    const SizedBox(height: 12),
                    Text(
                      state.hasError
                          ? state.error.toString()
                          : 'Unable to check your account link.',
                      style:
                          TextStyle(color: Theme.of(context).colorScheme.error),
                    ),
                    if (staff.hasError)
                      TextButton(
                        onPressed: () => ref.invalidate(currentStaffProvider),
                        child: const Text('Check link again'),
                      ),
                  ],
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: state.isLoading ? null : _submit,
                    child: Text(state.isLoading ? 'Linking…' : 'Link account'),
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

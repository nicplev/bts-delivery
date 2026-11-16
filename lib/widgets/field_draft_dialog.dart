import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../providers/auth_providers.dart';
import '../providers/field_draft_providers.dart';
import '../repositories/classroom_edit.dart';
import '../services/offline/field_draft_store.dart';
import '../services/result.dart';

class FieldDraftInput {
  const FieldDraftInput({
    required this.id,
    required this.label,
    required this.validator,
    this.initialText = '',
    this.keyboardType,
    this.maxLines = 1,
  });

  final String id;
  final String label;
  final String? Function(String) validator;
  final String initialText;
  final TextInputType? keyboardType;
  final int maxLines;
}

String fieldEditFeedback(String label, ClassroomEditStatus status) {
  return switch (status) {
    ClassroomEditStatus.saved => '$label saved',
    ClassroomEditStatus.pending => '$label saved on this device · Sync pending',
    ClassroomEditStatus.unconfirmed => '$label saved for sync review',
  };
}

Future<void> showFieldDraftDialog({
  required BuildContext context,
  required WidgetRef ref,
  required FieldDraftTarget target,
  required String title,
  required String savedLabel,
  required List<FieldDraftInput> inputs,
  String? description,
  required Future<Result<ClassroomEditStatus>> Function(FieldDraft draft)
      onSave,
}) async {
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to edit this record.')),
    );
    return;
  }

  final notification = await showDialog<String>(
    context: context,
    useRootNavigator: false,
    barrierDismissible: false,
    builder: (_) => _FieldDraftDialog(
      uid: uid,
      draftKey: target.keyFor(uid),
      title: title,
      savedLabel: savedLabel,
      inputs: inputs,
      description: description,
      onSave: onSave,
    ),
  );
  if (!context.mounted || notification == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(notification)),
  );
}

class _FieldDraftDialog extends ConsumerStatefulWidget {
  const _FieldDraftDialog({
    required this.uid,
    required this.draftKey,
    required this.title,
    required this.savedLabel,
    required this.inputs,
    required this.description,
    required this.onSave,
  });

  final String uid;
  final String draftKey;
  final String title;
  final String savedLabel;
  final List<FieldDraftInput> inputs;
  final String? description;
  final Future<Result<ClassroomEditStatus>> Function(FieldDraft draft) onSave;

  @override
  ConsumerState<_FieldDraftDialog> createState() => _FieldDraftDialogState();
}

class _FieldDraftDialogState extends ConsumerState<_FieldDraftDialog> {
  final _form = GlobalKey<FormState>();
  final _controllers = <String, TextEditingController>{};
  Future<void> _writes = Future.value();
  Timer? _debounce;
  FieldDraftStore? _store;
  FieldDraft? _draft;
  String? _persistedRevision;
  String? _draftError;
  String? _submitError;
  String? _submitNotice;
  bool _loading = true;
  bool _busy = false;
  bool _discarding = false;
  bool _closing = false;
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onInactive: _flushForLifecycle);
    unawaited(_restore());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    if (!_closing) _flushForLifecycle();
    _debounce?.cancel();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  Future<void> _restore() async {
    setState(() {
      _loading = true;
      _draftError = null;
    });
    try {
      final store = await ref.read(fieldDraftStoreProvider.future);
      final stored = await store.read(widget.draftKey);
      if (!mounted) return;
      _store = store;
      _draft = stored;
      _persistedRevision = stored?.revision;
      for (final input in widget.inputs) {
        _controllers[input.id] = TextEditingController(
          text: stored?.values[input.id] ?? input.initialText,
        );
      }
    } catch (_) {
      _draftError = 'Couldn’t open drafts on this device.';
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final signedIn =
        ref.watch(authStateProvider).valueOrNull?.uid == widget.uid;
    final canEdit = !_busy && !_loading && _store != null && signedIn;
    final status = _draftError ??
        _submitError ??
        (_draft == null
            ? null
            : _draft?.revision == _persistedRevision
                ? 'Draft saved on this device'
                : 'Saving draft…');

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) unawaited(_close());
      },
      child: AlertDialog(
        scrollable: true,
        title: Text(widget.title),
        content: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!signedIn)
                const Text('This draft belongs to the previous account.')
              else if (_loading)
                const Center(child: CircularProgressIndicator())
              else if (_store != null) ...[
                if (widget.description != null) Text(widget.description!),
                for (final input in widget.inputs)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: TextFormField(
                      key: ValueKey(input.id),
                      controller: _controllers[input.id],
                      enabled: canEdit,
                      autofocus: widget.inputs.length == 1,
                      maxLines: input.maxLines,
                      keyboardType: input.keyboardType,
                      decoration: InputDecoration(labelText: input.label),
                      validator: (value) => input.validator(value ?? ''),
                      onChanged: (_) => _changed(),
                    ),
                  ),
              ],
              if (signedIn && _submitNotice != null) Text(_submitNotice!),
              if (signedIn && status != null)
                Semantics(
                  liveRegion: true,
                  child: Text(
                    status,
                    style: TextStyle(
                      color: _draftError != null || _submitError != null
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          if (canEdit && _draft != null)
            TextButton(
              onPressed: _discard,
              child: const Text('Discard draft'),
            ),
          TextButton(
            onPressed: _busy ? null : _close,
            child: const Text('Close'),
          ),
          if (!signedIn || _loading)
            const SizedBox.shrink()
          else if (_store == null)
            FilledButton(
              onPressed: () {
                ref.invalidate(fieldDraftStoreProvider);
                unawaited(_restore());
              },
              child: const Text('Retry'),
            )
          else
            FilledButton(
              onPressed: canEdit ? _save : null,
              child: Text(_busy ? 'Saving…' : 'Save'),
            ),
        ],
      ),
    );
  }

  FieldDraft _capture() => FieldDraft(
        revision: const Uuid().v4(),
        values: {
          for (final input in widget.inputs)
            input.id: _controllers[input.id]!.text,
        },
      );

  void _changed() {
    setState(() {
      _draft = _capture();
      _submitError = null;
      _submitNotice = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), _flushForLifecycle);
  }

  void _flushForLifecycle() {
    if (!_discarding && !_closing) unawaited(_flush());
  }

  Future<bool> _flush() async {
    _debounce?.cancel();
    final store = _store;
    final draft = _draft;
    if (store == null || draft == null) return true;

    // Serialize writes so a slow checkpoint cannot republish older input after
    // an explicit discard or race with the exact revision submitted on Save.
    final key = widget.draftKey;
    final write = _writes.then((_) async {
      if (_persistedRevision != draft.revision) {
        await store.write(key, draft);
        _persistedRevision = draft.revision;
      }
    });
    _writes = write.then((_) {}, onError: (Object _) {});
    try {
      await write;
      if (mounted) setState(() => _draftError = null);
      return true;
    } catch (_) {
      if (mounted) {
        setState(() =>
            _draftError = 'Couldn’t save the draft on this device. Retry.');
      }
      return false;
    }
  }

  Future<void> _close() async {
    if (_busy || _closing) return;
    setState(() => _busy = true);
    while (mounted) {
      final revision = _draft?.revision;
      final stored = await _flush();
      if (!mounted) return;
      if (!stored) {
        setState(() => _busy = false);
        return;
      }
      if (revision == _draft?.revision) {
        _closing = true;
        Navigator.of(context).pop();
        return;
      }
    }
  }

  Future<void> _discard() async {
    final draft = _draft;
    if (_busy || draft == null) return;
    setState(() => _busy = true);
    _discarding = true;
    _debounce?.cancel();
    try {
      await _writes;
      final stored = _persistedRevision;
      if (stored != null) {
        await _store!.remove(widget.draftKey, revision: stored);
      }
      if (!mounted) return;
      _closing = true;
      Navigator.of(context).pop();
    } catch (_) {
      if (mounted) {
        _discarding = false;
        setState(() {
          _busy = false;
          _draftError = 'Couldn’t discard the draft. Try again.';
        });
      }
    }
  }

  Future<void> _save() async {
    if (_busy || !_form.currentState!.validate()) return;
    final draft = _draft ?? _capture();
    setState(() {
      _busy = true;
      _draft = draft;
      _submitError = null;
      _submitNotice = null;
    });
    final stored = await _flush();
    if (!mounted) return;
    if (!stored) {
      setState(() => _busy = false);
      return;
    }
    if (ref.read(authStateProvider).valueOrNull?.uid != widget.uid) {
      setState(() => _busy = false);
      return;
    }

    try {
      final result = await widget.onSave(draft);
      final status = result.dataOrNull;
      if (status == null) {
        if (mounted) {
          setState(() {
            _busy = false;
            _submitError = result.errorOrNull ?? 'Couldn’t save this change.';
          });
        }
        return;
      }
      var message = fieldEditFeedback(widget.savedLabel, status);
      try {
        await _store!.remove(widget.draftKey, revision: draft.revision);
      } catch (_) {
        message = '$message. The draft could not be cleared.';
      }
      if (!mounted) return;
      if (_draft?.revision != draft.revision) {
        await _flush();
        if (mounted) {
          setState(() {
            _busy = false;
            _submitNotice = message;
          });
        }
        return;
      }
      _closing = true;
      Navigator.of(context).pop(message);
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _submitError = 'Couldn’t submit this change. Your draft is saved.';
        });
      }
    }
  }
}

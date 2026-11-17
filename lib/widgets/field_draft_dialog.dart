import 'dart:async';

import 'package:flutter/material.dart';
import 'design/design.dart';
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

typedef FieldDraftSave = Future<Result<ClassroomEditStatus>> Function(
    FieldDraft draft);

/// What a custom field-draft form body (see [showFieldDraftSheet]) can use.
///
/// The text in [controller] is the draft: after changing it in code (a
/// stepper, a "fill in" button) call [changed] so it is saved on the device.
abstract interface class FieldDraftFields {
  TextEditingController controller(String inputId);

  /// Whether the inputs accept changes (false while saving or signed out).
  bool get enabled;

  /// Records the current text as a new draft revision.
  void changed();

  /// Validates and submits, exactly like the Save button.
  void save();
}

/// Shows the shared field-draft form as a neutral dialog. Unsaved input is
/// kept in the device draft store and restored next time.
Future<void> showFieldDraftDialog({
  required BuildContext context,
  required WidgetRef ref,
  required FieldDraftTarget target,
  required String title,
  required String savedLabel,
  required List<FieldDraftInput> inputs,
  String? description,
  required FieldDraftSave onSave,
}) {
  return _present(
    context: context,
    ref: ref,
    target: target,
    show: (uid, draftKey) => showDialog<String>(
      context: context,
      useRootNavigator: false,
      barrierDismissible: false,
      builder: (_) => _FieldDraftDialog(
        uid: uid,
        draftKey: draftKey,
        title: title,
        savedLabel: savedLabel,
        inputs: inputs,
        description: description,
        onSave: onSave,
      ),
    ),
  );
}

/// Shows the shared field-draft form as a glass sheet whose body is drawn by
/// [builder] (e.g. a stepper). Drafts, validation, the save path and its
/// messages behave exactly like [showFieldDraftDialog]; the sheet adds the
/// draft status, the [saveLabel] primary button and "Discard draft".
Future<void> showFieldDraftSheet({
  required BuildContext context,
  required WidgetRef ref,
  required FieldDraftTarget target,
  required String title,
  required String savedLabel,
  required String saveLabel,
  required List<FieldDraftInput> inputs,
  required Widget Function(BuildContext context, FieldDraftFields fields)
      builder,
  required FieldDraftSave onSave,
}) {
  return _present(
    context: context,
    ref: ref,
    target: target,
    show: (uid, draftKey) => showAppGlassSheet<String>(
      context: context,
      title: title,
      // Dragging would bypass the draft flush that runs before closing.
      enableDrag: false,
      builder: (_) => _FieldDraftSheet(
        uid: uid,
        draftKey: draftKey,
        savedLabel: savedLabel,
        saveLabel: saveLabel,
        inputs: inputs,
        builder: builder,
        onSave: onSave,
      ),
    ),
  );
}

Future<void> _present({
  required BuildContext context,
  required WidgetRef ref,
  required FieldDraftTarget target,
  required Future<String?> Function(String uid, String draftKey) show,
}) async {
  final uid = ref.read(authStateProvider).valueOrNull?.uid;
  if (uid == null) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Sign in to edit this record.')),
    );
    return;
  }

  final notification = await show(uid, target.keyFor(uid));
  if (!context.mounted || notification == null) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(notification)),
  );
}

abstract class _FieldDraftForm extends ConsumerStatefulWidget {
  const _FieldDraftForm({
    required this.uid,
    required this.draftKey,
    required this.savedLabel,
    required this.inputs,
    required this.onSave,
  });

  final String uid;
  final String draftKey;
  final String savedLabel;
  final List<FieldDraftInput> inputs;
  final FieldDraftSave onSave;
}

/// Draft persistence and submission shared by the dialog and the sheet.
abstract class _FieldDraftFormState<W extends _FieldDraftForm>
    extends ConsumerState<W> implements FieldDraftFields {
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

  bool get _signedIn =>
      ref.watch(authStateProvider).valueOrNull?.uid == widget.uid;

  bool _canEdit(bool signedIn) =>
      !_busy && !_loading && _store != null && signedIn;

  bool get _statusIsError => _draftError != null || _submitError != null;

  String? get _status =>
      _draftError ??
      _submitError ??
      (_draft == null
          ? null
          : _draft?.revision == _persistedRevision
              ? 'Draft saved on this device'
              : 'Saving draft…');

  @override
  TextEditingController controller(String inputId) => _controllers[inputId]!;

  @override
  bool get enabled => _canEdit(_signedIn);

  @override
  void changed() => _changed();

  @override
  void save() => unawaited(_save());

  void _retryStore() {
    ref.invalidate(fieldDraftStoreProvider);
    unawaited(_restore());
  }

  Widget _guard(Widget child) => PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) unawaited(_close());
        },
        child: child,
      );

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

class _FieldDraftDialog extends _FieldDraftForm {
  const _FieldDraftDialog({
    required super.uid,
    required super.draftKey,
    required this.title,
    required super.savedLabel,
    required super.inputs,
    required this.description,
    required super.onSave,
  });

  final String title;
  final String? description;

  @override
  ConsumerState<_FieldDraftDialog> createState() => _FieldDraftDialogState();
}

class _FieldDraftDialogState extends _FieldDraftFormState<_FieldDraftDialog> {
  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    final canEdit = _canEdit(signedIn);
    final status = _status;
    final colors = AppPalette.of(context);

    return _guard(
      AlertDialog(
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
                if (widget.description != null) ...[
                  Text(widget.description!,
                      style: AppTypography.subheadline
                          .copyWith(color: colors.muted)),
                  const SizedBox(height: 12),
                ],
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
                _FieldDraftStatus(label: status, isError: _statusIsError),
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
              onPressed: _retryStore,
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
}

class _FieldDraftSheet extends _FieldDraftForm {
  const _FieldDraftSheet({
    required super.uid,
    required super.draftKey,
    required super.savedLabel,
    required this.saveLabel,
    required super.inputs,
    required this.builder,
    required super.onSave,
  });

  final String saveLabel;
  final Widget Function(BuildContext context, FieldDraftFields fields) builder;

  @override
  ConsumerState<_FieldDraftSheet> createState() => _FieldDraftSheetState();
}

class _FieldDraftSheetState extends _FieldDraftFormState<_FieldDraftSheet> {
  @override
  Widget build(BuildContext context) {
    final signedIn = _signedIn;
    final canEdit = _canEdit(signedIn);
    final status = _status;
    final colors = AppPalette.of(context);

    return _guard(
      SingleChildScrollView(
        child: Form(
          key: _form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (!signedIn)
                Text('This draft belongs to the previous account.',
                    style: AppTypography.body.copyWith(color: colors.ink))
              else if (_loading)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 24),
                  child: Center(child: CircularProgressIndicator()),
                )
              else if (_store != null)
                widget.builder(context, this),
              if (signedIn && _submitNotice != null) ...[
                const SizedBox(height: 12),
                Text(_submitNotice!,
                    style:
                        AppTypography.subheadline.copyWith(color: colors.ink)),
              ],
              if (signedIn && status != null) ...[
                const SizedBox(height: 12),
                Center(
                  child:
                      _FieldDraftStatus(label: status, isError: _statusIsError),
                ),
              ],
              if (signedIn && !_loading) ...[
                const SizedBox(height: 10),
                if (_store == null)
                  AppPrimaryButton(label: 'Retry', onPressed: _retryStore)
                else
                  AppPrimaryButton(
                    label: _busy ? 'Saving…' : widget.saveLabel,
                    onPressed: canEdit ? _save : null,
                  ),
              ],
              if (canEdit && _draft != null) ...[
                const SizedBox(height: 4),
                Center(
                  child: AppSecondaryButton(
                    label: 'Discard draft',
                    expand: false,
                    large: false,
                    onPressed: _discard,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Draft state line ("Draft saved on this device", "Saving draft…" or a
/// draft/submit error in the error colour). Announced as a live region.
class _FieldDraftStatus extends StatelessWidget {
  const _FieldDraftStatus({
    required this.label,
    this.isError = false,
  });

  final String label;
  final bool isError;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final ink = isError ? colors.error : colors.muted;
    return Semantics(
      liveRegion: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(isError ? AppIcons.error : AppIcons.savedOnDevice,
                size: 16, color: isError ? colors.error : colors.ink),
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label,
              style: AppTypography.footnote.copyWith(
                color: ink,
                fontWeight: isError ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

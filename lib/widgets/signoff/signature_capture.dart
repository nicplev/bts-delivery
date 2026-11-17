part of '../signoff_tab.dart';

/// Focused, full-height signature capture (no tab bar). The name and strokes
/// live in controllers owned by the sign-off tab, so Back keeps them.
class _SignatureCaptureScreen extends StatefulWidget {
  const _SignatureCaptureScreen({
    required this.schoolId,
    required this.schoolName,
    required this.visitId,
    required this.visitDate,
    required this.name,
    required this.signature,
    required this.onReview,
  });

  final String schoolId;
  final String schoolName;
  final String visitId;
  final DateTime? visitDate;
  final TextEditingController name;
  final SignatureController signature;
  final Future<bool> Function(BuildContext context) onReview;

  @override
  State<_SignatureCaptureScreen> createState() =>
      _SignatureCaptureScreenState();
}

class _SignatureCaptureScreenState extends State<_SignatureCaptureScreen> {
  bool _reviewing = false;

  Future<void> _reviewAndSave(BuildContext captureContext) async {
    if (_reviewing) return;
    FocusScope.of(context).unfocus();
    setState(() => _reviewing = true);
    final saved = await widget.onReview(captureContext);
    if (!mounted) return;
    setState(() => _reviewing = false);
    if (saved && ModalRoute.of(context)?.isCurrent == true) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final visitDate = widget.visitDate;
    final subtitle = [
      widget.schoolName,
      if (visitDate != null) DateTimeUtils.formatDate(visitDate),
      'Visit ${widget.visitId}',
    ].join(' · ');
    return PopScope(
      canPop: !_reviewing,
      child: ScaffoldMessenger(
        child: Scaffold(
          backgroundColor: colors.canvas,
          body: Builder(
            builder: (captureContext) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SafeArea(
                  bottom: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        AppTokens.gutter, 4, AppTokens.gutter, 8),
                    child: Row(
                      children: [
                        Tooltip(
                          message: 'Back to review',
                          excludeFromSemantics: true,
                          child: AppGlassIconButton(
                            icon: AppIcons.back,
                            semanticLabel: 'Back to review',
                            onPressed: _reviewing
                                ? null
                                : () => Navigator.of(context).pop(),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Semantics(
                                header: true,
                                child: Text(
                                  'Signature',
                                  textAlign: TextAlign.center,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: AppTypography.headline
                                      .copyWith(color: colors.ink),
                                ),
                              ),
                              Text(
                                subtitle,
                                textAlign: TextAlign.center,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: AppTypography.footnote
                                    .copyWith(color: colors.muted),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8 + AppTokens.navButtonSize),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: MediaQuery.removePadding(
                    context: context,
                    removeTop: true,
                    child: AppFloatingActionArea(
                      // At large text sizes a pinned, wrapped label plus the
                      // keyboard would leave no room for the form, so the
                      // action follows the form instead.
                      action: _SignOffTabState._largeText(context)
                          ? null
                          : AppGlassPrimaryButton(
                              label: _reviewLabel,
                              loading: _reviewing,
                              onPressed: _reviewing
                                  ? null
                                  : () => _reviewAndSave(captureContext),
                            ),
                      child: Builder(
                        builder: (context) =>
                            _buildForm(context, colors, captureContext),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String get _reviewLabel => _reviewing ? 'Checking…' : 'Review and save';

  Widget _buildForm(
    BuildContext context,
    AppPalette colors,
    BuildContext captureContext,
  ) {
    final inlineAction = _SignOffTabState._largeText(context);
    final reserved =
        inlineAction ? 0.0 : AppFloatingActionArea.reservedHeight(context);
    // The pack summary and the reminder follow the canvas; at large text they
    // lead, so the canvas stays next to the inline action.
    final summary = [
      Consumer(
        builder: (context, ref, _) => _PackSummaryCard(
          progress: _watchPackProgress(ref, widget.schoolId),
          compact: true,
        ),
      ),
      const SizedBox(height: 16),
      Text(
        'You’ll check the full record once more before it saves.',
        textAlign: TextAlign.center,
        style: AppTypography.footnote.copyWith(color: colors.muted),
      ),
    ];
    return SingleChildScrollView(
      padding: AppInsets.scroll(context, top: 8),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (inlineAction) ...[...summary, const SizedBox(height: 16)],
              Semantics(
                container: true,
                child: TextField(
                  controller: widget.name,
                  enabled: !_reviewing,
                  maxLength: 200,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  // Keep the field clear of the floating action.
                  scrollPadding: EdgeInsets.fromLTRB(20, 20, 20, reserved + 20),
                  decoration: InputDecoration(
                    labelText: 'Name',
                    filled: true,
                    fillColor: colors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                      borderSide: BorderSide.none,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                      borderSide: colors.highContrast
                          ? BorderSide(color: colors.outline)
                          : BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                      borderSide: BorderSide(color: colors.ink, width: 1.5),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.only(start: 16),
                      child: Semantics(
                        header: true,
                        child: Text(
                          'Signature',
                          style: AppTypography.footnote
                              .copyWith(color: colors.muted),
                        ),
                      ),
                    ),
                  ),
                  AppSecondaryButton(
                    label: 'Clear',
                    large: false,
                    expand: false,
                    onPressed: _reviewing ? null : widget.signature.clear,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Semantics(
                container: true,
                label: 'Signature drawing area',
                child: AbsorbPointer(
                  absorbing: _reviewing,
                  child: LayoutBuilder(
                    builder: (context, constraints) => SizedBox(
                      height: math.max(
                          200.0, math.min(constraints.maxWidth * 0.5, 280.0)),
                      child: DecoratedBox(
                        position: DecorationPosition.foreground,
                        decoration: BoxDecoration(
                          borderRadius:
                              BorderRadius.circular(AppTokens.cardRadius),
                          border: colors.highContrast
                              ? Border.all(color: colors.outline, width: 1.5)
                              : null,
                        ),
                        child: ClipRRect(
                          borderRadius:
                              BorderRadius.circular(AppTokens.cardRadius),
                          // The canvas is white with black ink in every
                          // theme so the saved image matches what was drawn.
                          child: ColoredBox(
                            color: Colors.white,
                            child: CustomPaint(
                              painter: const _BaselinePainter(),
                              child: Signature(
                                controller: widget.signature,
                                backgroundColor: Colors.transparent,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (!inlineAction) ...[
                const SizedBox(height: 16),
                ...summary,
              ] else ...[
                const SizedBox(height: 16),
                AppPrimaryButton(
                  label: _reviewLabel,
                  loading: _reviewing,
                  onPressed:
                      _reviewing ? null : () => _reviewAndSave(captureContext),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Dashed baseline across the lower part of the signature canvas.
class _BaselinePainter extends CustomPainter {
  const _BaselinePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = const Color(0xFFD1D1D6)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;
    final y = size.height * 0.78;
    const inset = 28.0;
    for (var x = inset; x < size.width - inset; x += 7) {
      canvas.drawLine(
          Offset(x, y), Offset(math.min(x + 2, size.width - inset), y), paint);
    }
  }

  @override
  bool shouldRepaint(_BaselinePainter oldDelegate) => false;
}

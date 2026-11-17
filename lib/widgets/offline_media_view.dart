import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

import '../models/offline/offline_media.dart';
import '../models/delivery_visit.dart';
import '../providers/offline_media_providers.dart';
import '../services/offline/connectivity_service.dart';
import 'design/design.dart';
import '../services/date_utils.dart';

/// What a media asset can show right now. Every viewer resolves it the same
/// way, so the states and their wording stay identical: the verified saved
/// copy first, then (online only) the server copy.
sealed class _ResolvedMedia {
  const _ResolvedMedia();
}

final class _ResolvedLoading extends _ResolvedMedia {
  const _ResolvedLoading();
}

final class _ResolvedMessage extends _ResolvedMedia {
  const _ResolvedMessage(this.text, this.icon);
  final String text;
  final IconData icon;
}

final class _ResolvedFile extends _ResolvedMedia {
  const _ResolvedFile(this.file, this.key);
  final File file;
  final Object key;
}

final class _ResolvedUrl extends _ResolvedMedia {
  const _ResolvedUrl(this.url, this.key);
  final String url;
  final Object key;
}

_ResolvedMedia _resolveMedia(
  WidgetRef ref,
  OfflineMediaAsset asset, {
  String? expectedUid,
  bool localOnly = false,
}) {
  final uid = ref.watch(offlineMediaOwnerProvider(asset.schoolId));
  if (uid == null || (expectedUid != null && uid != expectedUid)) {
    return const _ResolvedMessage(
        'Media unavailable to this account', AppIcons.lock);
  }

  final saved = asset.visit == null
      ? null
      : ref.watch(offlineMediaAssetStateProvider(asset));
  if (saved?.isLoading == true && saved?.hasValue == false) {
    return const _ResolvedLoading();
  }
  final path = saved?.valueOrNull?.localPath;
  if (path != null && File(path).existsSync()) {
    return _ResolvedFile(File(path), (uid, path));
  }

  if (localOnly) {
    return const _ResolvedMessage(
        'Previously saved file is unavailable', AppIcons.error);
  }
  if (!ref.watch(isOnlineProvider)) {
    return const _ResolvedMessage(
        'Download this file before going offline', AppIcons.offline);
  }
  final remote = ref.watch(onlineMediaUrlProvider((asset: asset, uid: uid)));
  return remote.when(
    loading: () => const _ResolvedLoading(),
    error: (_, __) =>
        const _ResolvedMessage('Could not open this file', AppIcons.error),
    data: (url) => _ResolvedUrl(url, (uid, url)),
  );
}

Widget _fileImage(_ResolvedFile media, BoxFit fit) => Image.file(
      media.file,
      key: ValueKey(media.key),
      fit: fit,
      errorBuilder: (_, __, ___) => const _MediaMessage(
        'Saved file unavailable. Download it again.',
        icon: AppIcons.error,
      ),
    );

Widget _networkImage(_ResolvedUrl media, BoxFit fit) => Image.network(
      media.url,
      key: ValueKey(media.key),
      fit: fit,
      errorBuilder: (_, __, ___) => const _MediaMessage(
          'Could not open this image',
          icon: AppIcons.error),
    );

class OfflineMediaPreview extends ConsumerWidget {
  const OfflineMediaPreview({
    super.key,
    required this.asset,
    this.fit = BoxFit.contain,
    this.zoom = false,
    this.expectedUid,
    this.localOnly = false,
  });

  final OfflineMediaAsset asset;
  final BoxFit fit;
  final bool zoom;
  final String? expectedUid;
  final bool localOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final media = _resolveMedia(ref, asset,
        expectedUid: expectedUid, localOnly: localOnly);
    return switch (media) {
      _ResolvedLoading() => const _MediaLoading(),
      _ResolvedMessage(:final text, :final icon) =>
        _MediaMessage(text, icon: icon),
      _ResolvedFile() => asset.isPdf
          ? SfPdfViewer.file(media.file, key: ValueKey(media.key))
          : _image(_fileImage(media, fit)),
      _ResolvedUrl() => asset.isPdf
          ? SfPdfViewer.network(media.url, key: ValueKey(media.key))
          : _image(_networkImage(media, fit)),
    };
  }

  Widget _image(Widget image) => zoom
      ? InteractiveViewer(maxScale: 4, child: Center(child: image))
      : image;
}

/// The school map shown in place: pannable and pinch-zoomable inside its
/// card (double-tap zooms), with small glass controls floating over it — an
/// enlarge/shrink toggle and, only while zoomed, "Reset zoom". A PDF map shows
/// one page at a time, fitted to the viewer, with page controls when it has
/// several pages.
///
/// Gestures share the page: on an un-zoomed map a vertical drag scrolls the
/// page (and a sideways drag still swipes between tabs); once zoomed, drags
/// pan the map. Loading, offline and failure states use the same wording as
/// [OfflineMediaPreview].
class OfflineMapViewer extends ConsumerStatefulWidget {
  const OfflineMapViewer({
    super.key,
    required this.asset,
    this.height = 220,
    this.enlarged = false,
    this.onEnlargedChanged,
    this.semanticLabel = 'School map',
  });

  final OfflineMediaAsset asset;

  /// Height while not enlarged.
  final double height;

  /// Shows the map at most of the screen height (in place).
  final bool enlarged;

  /// Shows the enlarge/shrink control when set.
  final ValueChanged<bool>? onEnlargedChanged;
  final String semanticLabel;

  /// Height of an enlarged viewer on this screen.
  static double enlargedHeight(BuildContext context, double height) =>
      math.max(height, MediaQuery.sizeOf(context).height * 0.62);

  @override
  ConsumerState<OfflineMapViewer> createState() => _OfflineMapViewerState();
}

class _OfflineMapViewerState extends ConsumerState<OfflineMapViewer>
    with SingleTickerProviderStateMixin {
  static const double _maxScale = 4;

  final _transform = TransformationController();
  final _pdf = PdfViewerController();
  late final AnimationController _resetAnimation;
  Matrix4Tween? _resetTween;
  bool _zoomed = false;
  int _pageCount = 0;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _transform.addListener(_onTransform);
    _resetAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_animateReset);
  }

  @override
  void didUpdateWidget(OfflineMapViewer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.asset != widget.asset) {
      _resetAnimation.stop();
      _transform.value = Matrix4.identity();
      _zoomed = false;
      _pageCount = 0;
      _page = 1;
    }
  }

  @override
  void dispose() {
    _resetAnimation.dispose();
    _transform.dispose();
    _pdf.dispose();
    super.dispose();
  }

  void _onTransform() {
    final zoomed = _transform.value.getMaxScaleOnAxis() > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  void _animateReset() {
    final tween = _resetTween;
    if (tween != null) _transform.value = tween.evaluate(_resetAnimation);
  }

  bool get _reduceMotion =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  void _resetZoom() {
    if (widget.asset.isPdf) {
      _pdf.zoomLevel = 1;
      setState(() => _zoomed = false);
      return;
    }
    if (_reduceMotion) {
      _transform.value = Matrix4.identity();
      return;
    }
    _resetTween =
        Matrix4Tween(begin: _transform.value.clone(), end: Matrix4.identity());
    _resetAnimation.forward(from: 0);
  }

  void _setPdfZoom(double level) {
    _pdf.zoomLevel = level.clamp(1.0, _maxScale);
    final zoomed = _pdf.zoomLevel > 1.01;
    if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final media = _resolveMedia(ref, widget.asset);
    final pdf = widget.asset.isPdf;
    final Widget content = switch (media) {
      _ResolvedLoading() => const _MediaLoading(),
      _ResolvedMessage(:final text, :final icon) =>
        _MediaMessage(text, icon: icon),
      _ResolvedFile() || _ResolvedUrl() when pdf => _InlinePdf(
          media: media,
          controller: _pdf,
          zoomed: _zoomed,
          maxScale: _maxScale,
          onZoom: _setPdfZoom,
          onLoaded: (count) => setState(() => _pageCount = count),
          onPage: (page) => setState(() => _page = page),
          onZoomChanged: (zoomed) {
            if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
          },
        ),
      _ResolvedFile() => _ZoomableMap(
          controller: _transform,
          zoomed: _zoomed,
          maxScale: _maxScale,
          child: _fileImage(media, BoxFit.contain),
        ),
      _ResolvedUrl() => _ZoomableMap(
          controller: _transform,
          zoomed: _zoomed,
          maxScale: _maxScale,
          child: _networkImage(media, BoxFit.contain),
        ),
    };
    final ready = media is _ResolvedFile || media is _ResolvedUrl;
    final onEnlarged = widget.onEnlargedChanged;
    final height = widget.enlarged
        ? OfflineMapViewer.enlargedHeight(context, widget.height)
        : widget.height;
    final controls = <Widget>[
      if (ready && _zoomed)
        AppGlassIconButton(
          key: const ValueKey('map-reset-zoom'),
          icon: AppIcons.resetZoom,
          semanticLabel: 'Reset zoom',
          tooltip: 'Reset zoom',
          onPressed: _resetZoom,
        ),
      if (ready && onEnlarged != null)
        AppGlassIconButton(
          key: const ValueKey('map-enlarge'),
          icon: widget.enlarged ? AppIcons.shrink : AppIcons.enlarge,
          semanticLabel: widget.enlarged ? 'Shrink map' : 'Enlarge map',
          tooltip: widget.enlarged ? 'Shrink map' : 'Enlarge map',
          onPressed: () => onEnlarged(!widget.enlarged),
        ),
    ];
    return Semantics(
      container: true,
      label: widget.semanticLabel,
      image: ready && !pdf,
      explicitChildNodes: true,
      child: AnimatedContainer(
        key: const ValueKey('map-viewer'),
        duration:
            _reduceMotion ? Duration.zero : const Duration(milliseconds: 220),
        curve: Curves.easeInOut,
        height: height,
        color: colors.surfaceQuiet,
        clipBehavior: Clip.hardEdge,
        child: Stack(
          fit: StackFit.expand,
          children: [
            content,
            if (controls.isNotEmpty)
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < controls.length; i++) ...[
                      if (i > 0) const SizedBox(width: 8),
                      controls[i],
                    ],
                  ],
                ),
              ),
            if (ready && pdf && _pageCount > 1)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: Center(
                  child: _PageControls(
                    page: _page,
                    count: _pageCount,
                    onPrevious: _page > 1 ? _pdf.previousPage : null,
                    onNext: _page < _pageCount ? _pdf.nextPage : null,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Scale recognizer that wins the gesture arena at once while [eager] says
/// so (a zoomed map pans instead of scrolling the page); otherwise it lets a
/// one-finger drag go to the page or tab swipe and only takes pinches.
class _MapScaleRecognizer extends ScaleGestureRecognizer {
  _MapScaleRecognizer({super.debugOwner, required this.eager});

  bool Function() eager;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    if (eager()) resolve(GestureDisposition.accepted);
  }
}

/// Pinch to zoom (1×–[maxScale]), double-tap to zoom in or back out, drag to
/// pan once zoomed; the content always covers the viewer.
class _ZoomableMap extends StatefulWidget {
  const _ZoomableMap({
    required this.controller,
    required this.zoomed,
    required this.maxScale,
    required this.child,
  });

  final TransformationController controller;
  final bool zoomed;
  final double maxScale;
  final Widget child;

  @override
  State<_ZoomableMap> createState() => _ZoomableMapState();
}

class _ZoomableMapState extends State<_ZoomableMap> {
  static const double _doubleTapScale = 2.5;
  static const Duration _doubleTapTimeout = Duration(milliseconds: 300);

  Size _size = Size.zero;
  Matrix4 _start = Matrix4.identity();
  Offset _startFocal = Offset.zero;
  double _startScale = 1;
  double _moved = 0;
  bool _scaled = false;
  DateTime _downAt = DateTime.now();
  DateTime? _lastTap;
  Offset? _lastTapAt;
  Offset _doubleTapAt = Offset.zero;

  TransformationController get _controller => widget.controller;

  /// The transform for [scale] that keeps [scene] under [focal], clamped so
  /// the content still covers the viewer.
  Matrix4 _transformFor(double scale, Offset scene, Offset focal) {
    final w = _size.width;
    final h = _size.height;
    final tx = (focal.dx - scene.dx * scale).clamp(w - w * scale, 0.0);
    final ty = (focal.dy - scene.dy * scale).clamp(h - h * scale, 0.0);
    return Matrix4.diagonal3Values(scale, scale, 1)
      ..setTranslationRaw(tx, ty, 0);
  }

  Offset _toScene(Matrix4 matrix, Offset point) =>
      MatrixUtils.transformPoint(Matrix4.inverted(matrix), point);

  void _zoomAround(Offset focal) {
    final current = _controller.value;
    if (current.getMaxScaleOnAxis() > 1.01) {
      _controller.value = Matrix4.identity();
    } else {
      _controller.value =
          _transformFor(_doubleTapScale, _toScene(current, focal), focal);
    }
  }

  void _onStart(ScaleStartDetails details) {
    _start = _controller.value.clone();
    _startFocal = details.localFocalPoint;
    _startScale = _start.getMaxScaleOnAxis();
    _moved = 0;
    _scaled = details.pointerCount > 1;
    _downAt = DateTime.now();
  }

  void _onUpdate(ScaleUpdateDetails details) {
    _moved = math.max(_moved, (details.localFocalPoint - _startFocal).distance);
    if (details.pointerCount > 1) _scaled = true;
    final scale =
        (_startScale * details.scale).clamp(1.0, widget.maxScale).toDouble();
    _controller.value = _transformFor(
        scale, _toScene(_start, _startFocal), details.localFocalPoint);
  }

  void _onEnd(ScaleEndDetails details) {
    // While zoomed this recognizer also receives taps: detect a double tap.
    final now = DateTime.now();
    final tap = !_scaled &&
        _moved < kTouchSlop &&
        now.difference(_downAt) < const Duration(milliseconds: 250);
    if (!tap) {
      _lastTap = null;
      return;
    }
    final previous = _lastTap;
    if (previous != null &&
        now.difference(previous) < _doubleTapTimeout &&
        (_lastTapAt! - _startFocal).distance < kDoubleTapSlop) {
      _lastTap = null;
      _zoomAround(_startFocal);
    } else {
      _lastTap = now;
      _lastTapAt = _startFocal;
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      _size = constraints.biggest;
      return RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _MapScaleRecognizer:
              GestureRecognizerFactoryWithHandlers<_MapScaleRecognizer>(
            () => _MapScaleRecognizer(
                debugOwner: this, eager: () => widget.zoomed),
            (recognizer) => recognizer
              ..eager = (() => widget.zoomed)
              ..onStart = _onStart
              ..onUpdate = _onUpdate
              ..onEnd = _onEnd,
          ),
          DoubleTapGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<DoubleTapGestureRecognizer>(
            () => DoubleTapGestureRecognizer(debugOwner: this),
            (recognizer) => recognizer
              ..onDoubleTapDown =
                  ((details) => _doubleTapAt = details.localPosition)
              ..onDoubleTap = () => _zoomAround(_doubleTapAt),
          ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) => Transform(
              transform: _controller.value,
              child: child,
            ),
            child: SizedBox.fromSize(size: _size, child: widget.child),
          ),
        ),
      );
    });
  }
}

/// A PDF map, one page at a time and fitted to the viewer. While it is not
/// zoomed a gesture layer covers it: pinches and double taps zoom, and other
/// drags pass to the page; once zoomed the viewer pans itself.
class _InlinePdf extends StatefulWidget {
  const _InlinePdf({
    required this.media,
    required this.controller,
    required this.zoomed,
    required this.maxScale,
    required this.onZoom,
    required this.onLoaded,
    required this.onPage,
    required this.onZoomChanged,
  });

  final _ResolvedMedia media;
  final PdfViewerController controller;
  final bool zoomed;
  final double maxScale;
  final ValueChanged<double> onZoom;
  final ValueChanged<int> onLoaded;
  final ValueChanged<int> onPage;
  final ValueChanged<bool> onZoomChanged;

  @override
  State<_InlinePdf> createState() => _InlinePdfState();
}

class _InlinePdfState extends State<_InlinePdf> {
  double _startZoom = 1;

  @override
  Widget build(BuildContext context) {
    final media = widget.media;
    void loaded(PdfDocumentLoadedDetails _) =>
        widget.onLoaded(widget.controller.pageCount);
    void zoomed(PdfZoomDetails details) =>
        widget.onZoomChanged(details.newZoomLevel > 1.01);
    void paged(PdfPageChangedDetails details) =>
        widget.onPage(details.newPageNumber);
    final viewer = switch (media) {
      _ResolvedFile() => SfPdfViewer.file(
          media.file,
          key: ValueKey(media.key),
          controller: widget.controller,
          pageLayoutMode: PdfPageLayoutMode.single,
          scrollDirection: PdfScrollDirection.horizontal,
          maxZoomLevel: widget.maxScale,
          enableTextSelection: false,
          canShowScrollHead: false,
          canShowScrollStatus: false,
          canShowPaginationDialog: false,
          onDocumentLoaded: loaded,
          onZoomLevelChanged: zoomed,
          onPageChanged: paged,
        ),
      _ResolvedUrl() => SfPdfViewer.network(
          media.url,
          key: ValueKey(media.key),
          controller: widget.controller,
          pageLayoutMode: PdfPageLayoutMode.single,
          scrollDirection: PdfScrollDirection.horizontal,
          maxZoomLevel: widget.maxScale,
          enableTextSelection: false,
          canShowScrollHead: false,
          canShowScrollStatus: false,
          canShowPaginationDialog: false,
          onDocumentLoaded: loaded,
          onZoomLevelChanged: zoomed,
          onPageChanged: paged,
        ),
      _ => const SizedBox.shrink(),
    };
    return Stack(
      fit: StackFit.expand,
      children: [
        viewer,
        if (!widget.zoomed)
          RawGestureDetector(
            behavior: HitTestBehavior.opaque,
            gestures: {
              _MapScaleRecognizer:
                  GestureRecognizerFactoryWithHandlers<_MapScaleRecognizer>(
                () => _MapScaleRecognizer(debugOwner: this, eager: () => false),
                (recognizer) => recognizer
                  ..onStart = ((_) => _startZoom = widget.controller.zoomLevel)
                  ..onUpdate = (details) {
                    if (details.pointerCount > 1) {
                      widget.onZoom(_startZoom * details.scale);
                    }
                  },
              ),
              DoubleTapGestureRecognizer: GestureRecognizerFactoryWithHandlers<
                  DoubleTapGestureRecognizer>(
                () => DoubleTapGestureRecognizer(debugOwner: this),
                (recognizer) =>
                    recognizer..onDoubleTap = () => widget.onZoom(2),
              ),
            },
          ),
      ],
    );
  }
}

/// "‹ Page 2 of 3 ›" over a multi-page PDF map.
class _PageControls extends StatelessWidget {
  const _PageControls({
    required this.page,
    required this.count,
    required this.onPrevious,
    required this.onNext,
  });

  final int page;
  final int count;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return AppGlass(
      borderRadius: BorderRadius.circular(AppTokens.pillRadius),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppPressable(
            onTap: onPrevious,
            semanticLabel: 'Previous page',
            excludeChildSemantics: true,
            child: SizedBox.square(
              dimension: AppTokens.minTouchTarget,
              child: Icon(AppIcons.previousPage,
                  size: 18,
                  color: onPrevious == null ? colors.inactive : colors.ink),
            ),
          ),
          Flexible(
            child: Text(
              'Page $page of $count',
              style: AppTypography.footnote
                  .copyWith(color: colors.ink, fontWeight: FontWeight.w600),
            ),
          ),
          AppPressable(
            onTap: onNext,
            semanticLabel: 'Next page',
            excludeChildSemantics: true,
            child: SizedBox.square(
              dimension: AppTokens.minTouchTarget,
              child: Icon(AppIcons.nextPage,
                  size: 18,
                  color: onNext == null ? colors.inactive : colors.ink),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen viewer: media fills the screen beneath a glass back button and
/// (for visit media) a glass download action; the title and download state
/// sit in a glass caption at the bottom.
class OfflineMediaScreen extends ConsumerWidget {
  const OfflineMediaScreen({
    super.key,
    required this.asset,
    required this.ownerUid,
    required this.title,
    this.localOnly = false,
  });

  final OfflineMediaAsset asset;
  final String ownerUid;
  final String title;
  final bool localOnly;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canView =
        ref.watch(offlineMediaOwnerProvider(asset.schoolId)) == ownerUid;
    final colors = AppPalette.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: colors.canvas,
      appBar: AppNavBar(
        actions: [
          if (canView && asset.visit != null && !localOnly)
            OfflineMediaDownloadButton(asset: asset),
        ],
      ),
      body: Semantics(
        label: title,
        explicitChildNodes: true,
        child: Stack(
          children: [
            Positioned.fill(
              child: Padding(
                padding:
                    EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
                child: OfflineMediaPreview(
                  asset: asset,
                  expectedUid: ownerUid,
                  zoom: true,
                  localOnly: localOnly,
                ),
              ),
            ),
            Positioned(
              left: AppTokens.gutter,
              right: AppTokens.gutter,
              bottom: AppInsets.bottom(context, extra: 12),
              child: AppGlass(
                borderRadius: BorderRadius.circular(AppTokens.cardRadius),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(title,
                          style: AppTypography.headline
                              .copyWith(color: colors.ink)),
                    ),
                    if (canView && asset.visit != null)
                      OfflineMediaDownloadStatus(asset: asset),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class OfflineEarlierMapButton extends ConsumerWidget {
  const OfflineEarlierMapButton({
    super.key,
    required this.visit,
    required this.currentMap,
    this.padding = const EdgeInsets.only(top: 8),
  });

  final DeliveryVisit visit;
  final OfflineMediaAsset? currentMap;

  /// Space around the button (when it shows).
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(visit.schoolId));
    if (uid == null) return const SizedBox.shrink();
    final earlier =
        ref.watch(offlineMediaVisitStateProvider(visit)).valueOrNull?.savedMap;
    if (earlier == null || earlier.asset == currentMap) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: padding,
      child: AppSecondaryButton(
        large: false,
        icon: AppIcons.history,
        onPressed: () => Navigator.of(context).push<void>(
          MaterialPageRoute(
            builder: (_) => OfflineMediaScreen(
              asset: earlier.asset,
              ownerUid: uid,
              title: 'Previously saved map',
              localOnly: true,
            ),
          ),
        ),
        label:
            'Open previously saved map\nChecked ${_checkedAt(context, earlier.checkedAt)}',
      ),
    );
  }
}

class OfflineMediaDownloadButton extends ConsumerWidget {
  const OfflineMediaDownloadButton({
    super.key,
    required this.asset,
    this.compact = true,
  });

  final OfflineMediaAsset asset;

  /// A 44 pt round glass icon button (over media / in the nav area); `false`
  /// gives a labelled grey capsule.
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(offlineMediaOwnerProvider(asset.schoolId));
    if (asset.visit == null || uid == null) return const SizedBox.shrink();
    final cache = ref.watch(offlineMediaWorkerProvider).valueOrNull;
    final state = ref.watch(offlineMediaAssetStateProvider(asset)).valueOrNull;
    final phase = state?.phase;
    final pending = phase == OfflineMediaPhase.queued ||
        phase == OfflineMediaPhase.downloading;
    final ready = phase == OfflineMediaPhase.ready;
    if (ready && asset.kind == OfflineMediaKind.photo) {
      final colors = AppPalette.of(context);
      return Tooltip(
        message: 'Saved for offline',
        child: Semantics(
          label: 'Saved for offline',
          image: true,
          child: SizedBox.square(
            dimension: AppTokens.minTouchTarget,
            child: AppGlass(
              child: Center(
                child: Icon(AppIcons.complete, size: 20, color: colors.ink),
              ),
            ),
          ),
        ),
      );
    }

    final action = pending
        ? 'Cancel download'
        : ready
            ? 'Refresh saved map'
            : phase == OfflineMediaPhase.interrupted ||
                    phase == OfflineMediaPhase.failed ||
                    phase == OfflineMediaPhase.missing ||
                    phase == OfflineMediaPhase.stale
                ? 'Retry download'
                : 'Download for offline';
    final icon = pending
        ? AppIcons.close
        : ready
            ? AppIcons.retry
            : AppIcons.download;
    Future<void> perform() async {
      try {
        if (pending) {
          await cache!.cancelAsset(asset, uid: uid);
        } else {
          await cache!.requestDownload(asset, uid: uid);
        }
      } catch (_) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not update the download')),
        );
      }
    }

    return compact
        ? AppGlassIconButton(
            icon: icon,
            semanticLabel: action,
            tooltip: action,
            onPressed: cache == null ? null : perform,
          )
        : AppSecondaryButton(
            onPressed: cache == null ? null : perform,
            icon: icon,
            label: action,
            large: false,
          );
  }
}

class OfflineMediaDownloadStatus extends ConsumerWidget {
  const OfflineMediaDownloadStatus({super.key, required this.asset});

  final OfflineMediaAsset asset;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (ref.watch(offlineMediaOwnerProvider(asset.schoolId)) == null) {
      return const SizedBox.shrink();
    }
    final value = ref.watch(offlineMediaAssetStateProvider(asset));
    final state = value.valueOrNull;
    if (state == null) {
      return value.hasError
          ? const Padding(
              padding: EdgeInsets.symmetric(vertical: 6),
              child: AppStatusLine(
                text: 'Offline downloads unavailable',
                icon: AppIcons.error,
              ),
            )
          : const SizedBox.shrink();
    }

    final verification = state.verifiedAt;
    final savedMap = asset.kind == OfflineMediaKind.map && verification != null
        ? 'Saved map copy · checked ${_checkedAt(context, verification)}'
        : null;
    final label = switch (state.phase) {
      OfflineMediaPhase.available => null,
      OfflineMediaPhase.ready when asset.kind == OfflineMediaKind.map => null,
      OfflineMediaPhase.ready => 'Saved for offline',
      OfflineMediaPhase.queued => 'Waiting to download',
      OfflineMediaPhase.downloading => 'Downloading',
      OfflineMediaPhase.missing => 'Saved file unavailable. Download it again.',
      OfflineMediaPhase.stale => 'Showing the earlier saved map copy',
      OfflineMediaPhase.interrupted =>
        'Download interrupted. Retry when ready.',
      OfflineMediaPhase.failed => switch (state.issue) {
          OfflineMediaIssue.tooLarge => 'File exceeds the 25 MB download limit',
          OfflineMediaIssue.cacheFull => 'Offline storage is full',
          OfflineMediaIssue.changed =>
            'File changed during the download. Retry.',
          OfflineMediaIssue.invalidFile =>
            'Could not verify the downloaded file',
          OfflineMediaIssue.cancellationStalled =>
            'The transfer could not stop. Close and reopen the app if it does not finish.',
          _ => 'Could not download the file',
        },
    };
    if (label == null && savedMap == null) return const SizedBox.shrink();
    final needsDownload = switch (state.phase) {
      OfflineMediaPhase.missing ||
      OfflineMediaPhase.stale ||
      OfflineMediaPhase.interrupted ||
      OfflineMediaPhase.failed =>
        true,
      _ => false,
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (savedMap != null)
            AppStatusLine(text: savedMap, icon: AppIcons.savedOnDevice),
          if (label != null) ...[
            if (savedMap != null) const SizedBox(height: 4),
            if (needsDownload)
              AppNotice.warning(message: label)
            else
              AppStatusLine(
                text: label,
                icon: state.phase == OfflineMediaPhase.ready
                    ? AppIcons.complete
                    : AppIcons.download,
              ),
          ],
          if (state.phase == OfflineMediaPhase.downloading) ...[
            const SizedBox(height: 8),
            AppProgressBar(
              value: state.progress ?? 0,
              semanticLabel: 'Download progress',
            ),
          ],
        ],
      ),
    );
  }
}

class _MediaLoading extends StatelessWidget {
  const _MediaLoading();

  @override
  Widget build(BuildContext context) => Center(
        child: Semantics(
          label: 'Loading media',
          child: const CircularProgressIndicator(),
        ),
      );
}

/// Neutral placeholder for media that cannot be shown: grey tile, ink glyph,
/// muted message.
class _MediaMessage extends StatelessWidget {
  const _MediaMessage(this.text, {this.icon = AppIcons.gallery});

  final String text;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return LayoutBuilder(builder: (context, constraints) {
      final roomy = constraints.maxHeight >= 120 && constraints.maxWidth >= 140;
      return ColoredBox(
        color: colors.surfaceQuiet,
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (roomy) ...[
                  ExcludeSemantics(child: AppIconTile(icon: icon, size: 48)),
                  const SizedBox(height: 8),
                ],
                Text(
                  text,
                  textAlign: TextAlign.center,
                  style: AppTypography.footnote.copyWith(color: colors.muted),
                ),
              ],
            ),
          ),
        ),
      );
    });
  }
}

String _checkedAt(BuildContext context, DateTime date) {
  return DateTimeUtils.formatDateTime(date.toLocal());
}

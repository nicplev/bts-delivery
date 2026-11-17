import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'design/design.dart';

/// Shared chrome for the PDF viewers: glass back and share buttons over the
/// document, and a wrapping title above it.
class _PdfScaffold extends StatelessWidget {
  const _PdfScaffold({
    required this.title,
    required this.onShare,
    required this.viewer,
  });

  final String title;
  final Future<void> Function(BuildContext context) onShare;
  final Widget viewer;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    return Scaffold(
      extendBodyBehindAppBar: true,
      backgroundColor: colors.canvas,
      appBar: AppNavBar(
        actions: [
          Builder(
            builder: (buttonContext) => AppGlassIconButton(
              icon: AppIcons.share,
              semanticLabel: 'Share PDF',
              onPressed: () => onShare(buttonContext),
            ),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: MediaQuery.paddingOf(context).top),
          Padding(
            padding: const EdgeInsets.fromLTRB(
                AppTokens.gutter + 4, 4, AppTokens.gutter + 4, 12),
            child: Semantics(
              header: true,
              child: Text(title,
                  style: AppTypography.title3.copyWith(color: colors.ink)),
            ),
          ),
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: viewer,
            ),
          ),
        ],
      ),
    );
  }
}

void _showLoadFailure(BuildContext context, PdfDocumentLoadFailedDetails d) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to load PDF: ${d.error}')),
  );
}

void _showShareFailure(BuildContext context, Object error) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text('Failed to share PDF: $error')),
  );
}

class PDFViewerWidget extends StatelessWidget {
  const PDFViewerWidget({
    super.key,
    required this.url,
    this.title,
  });

  final String url;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return _PdfScaffold(
      title: title ?? 'PDF Viewer',
      onShare: (context) async {
        try {
          // Download PDF to temp directory
          final response = await http.get(Uri.parse(url));
          final bytes = response.bodyBytes;
          final temp = await getTemporaryDirectory();
          final file = File('${temp.path}/shared_document.pdf');
          await file.writeAsBytes(bytes);

          // Share the file
          await Share.shareXFiles(
            [XFile(file.path)],
            subject: title ?? 'PDF Document',
          );
        } catch (e) {
          if (context.mounted) _showShareFailure(context, e);
        }
      },
      viewer: SfPdfViewer.network(
        url,
        enableDoubleTapZooming: true,
        enableTextSelection: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: (details) => _showLoadFailure(context, details),
      ),
    );
  }
}

class LocalPDFViewerWidget extends StatelessWidget {
  const LocalPDFViewerWidget({
    super.key,
    required this.filePath,
    this.title,
  });

  final String filePath;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return _PdfScaffold(
      title: title ?? 'PDF Viewer',
      onShare: (context) async {
        try {
          // Share the local file
          await Share.shareXFiles(
            [XFile(filePath)],
            subject: title ?? 'PDF Document',
          );
        } catch (e) {
          if (context.mounted) _showShareFailure(context, e);
        }
      },
      viewer: SfPdfViewer.file(
        File(filePath),
        enableDoubleTapZooming: true,
        enableTextSelection: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: (details) => _showLoadFailure(context, details),
      ),
    );
  }
}

// Helper widget for PDF thumbnail/preview
class PDFThumbnail extends StatelessWidget {
  const PDFThumbnail({
    super.key,
    required this.url,
    this.width = 100,
    this.height = 150,
    this.onTap,
  });

  final String url;
  final double width;
  final double height;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = AppPalette.of(context);
    final tile = SizedBox(
      width: width,
      height: height,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceQuiet,
          borderRadius: BorderRadius.circular(AppTokens.controlRadius),
          border:
              colors.highContrast ? Border.all(color: colors.outline) : null,
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(AppIcons.document, size: 36, color: colors.ink),
            const SizedBox(height: 8),
            Text(
              'PDF',
              style: AppTypography.footnote
                  .copyWith(color: colors.ink, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
    if (onTap == null) {
      return Semantics(label: 'PDF', image: true, child: tile);
    }
    return AppPressable(
      onTap: onTap,
      semanticLabel: 'Open PDF',
      excludeChildSemantics: true,
      child: tile,
    );
  }
}

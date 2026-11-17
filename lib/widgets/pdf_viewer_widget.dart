import 'dart:io';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:share_plus/share_plus.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../app/theme/app_tokens.dart';

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
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'PDF Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
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
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to share PDF: $e'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SfPdfViewer.network(
        url,
        enableDoubleTapZooming: true,
        enableTextSelection: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load PDF: ${details.error}'),
            ),
          );
        },
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
    return Scaffold(
      appBar: AppBar(
        title: Text(title ?? 'PDF Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.share),
            onPressed: () async {
              try {
                // Share the local file
                await Share.shareXFiles(
                  [XFile(filePath)],
                  subject: title ?? 'PDF Document',
                );
              } catch (e) {
                if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Failed to share PDF: $e'),
                    ),
                  );
                }
              }
            },
          ),
        ],
      ),
      body: SfPdfViewer.file(
        File(filePath),
        enableDoubleTapZooming: true,
        enableTextSelection: true,
        canShowScrollHead: true,
        canShowScrollStatus: true,
        onDocumentLoadFailed: (PdfDocumentLoadFailedDetails details) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to load PDF: ${details.error}'),
            ),
          );
        },
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
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: width,
        height: height,
        decoration: BoxDecoration(
          border: Border.all(color: AppPalette.of(context).outline),
          borderRadius: BorderRadius.circular(8),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            fit: StackFit.expand,
            children: [
              // PDF icon placeholder
              Container(
                color: Theme.of(context).colorScheme.errorContainer,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.picture_as_pdf,
                      size: 40,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'PDF',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // Overlay for tap indication
              if (onTap != null)
                Positioned.fill(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: onTap,
                      child: Container(),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

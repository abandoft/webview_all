import 'dart:ui' show Rect, Size;
import 'package:flutter/painting.dart' show EdgeInsets;

/// Native page archive formats. Archives may contain sensitive page data and
/// cannot guarantee that protected or uncached resources are included.
enum WebViewArchiveFormat { mhtml, webArchive }

/// Captures native PNG pixels, optionally crops them, then scales the result.
/// Full-document capture is available only when the engine reports support.
/// It does not scroll the page or combine screenshots.
class WebViewScreenshotOptions {
  const WebViewScreenshotOptions({
    this.region,
    this.scale = 1,
    this.fullDocument = false,
  });
  final bool fullDocument;
  final Rect? region;
  final double scale;
  bool get isDefault => region == null && scale == 1 && !fullDocument;
}

/// PDF paper size and margins, in points (72 points = 1 inch).
///
/// Omit options entirely to retain the engine's existing PDF layout defaults.
class WebViewPdfOptions {
  const WebViewPdfOptions({
    this.paperSize = const Size(595.28, 841.89),
    this.margins = const EdgeInsets.all(28.35),
    this.landscape = false,
  });
  final Size paperSize;
  final EdgeInsets margins;
  final bool landscape;
  bool get isValid {
    final width = landscape ? paperSize.height : paperSize.width;
    final height = landscape ? paperSize.width : paperSize.height;
    return width.isFinite &&
        height.isFinite &&
        width > 0 &&
        height > 0 &&
        width <= 14400 &&
        height <= 14400 &&
        [
          margins.left,
          margins.top,
          margins.right,
          margins.bottom,
        ].every((v) => v.isFinite && v >= 0) &&
        margins.horizontal < width &&
        margins.vertical < height;
  }

  Map<String, Object?> toMap() => {
    'paperWidth': paperSize.width,
    'paperHeight': paperSize.height,
    'marginTop': margins.top,
    'marginBottom': margins.bottom,
    'marginLeft': margins.left,
    'marginRight': margins.right,
    'landscape': landscape,
  };
}

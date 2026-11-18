import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Displays a product image from either a compressed `data:image/...;base64,...`
/// string or an `http(s)://` URL, with a clean placeholder fallback.
///
/// When [enableViewer] is `true` and an image is present, tapping opens
/// [ProductImageViewer].
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.imageData,
    this.size = 44,
    this.borderRadius = 8,
    this.enableViewer = false,
  });

  final String? imageData;
  final double size;
  final double borderRadius;
  final bool enableViewer;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.inventory_2_outlined,
      size: size * 0.45,
    );

    final raw = imageData?.trim();
    final hasImage = raw != null && raw.isNotEmpty;
    final child = _buildImageWidget(raw, fallback);

    final box = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (!enableViewer || !hasImage) return box;

    return GestureDetector(
      onTap: () => ProductImageViewer.open(context, raw),
      child: box,
    );
  }

  static Widget _buildImageWidget(String? raw, Widget fallback) {
    if (raw == null || raw.isEmpty) return fallback;
    if (raw.startsWith('data:image')) {
      final bytes = decodeBase64DataUri(raw);
      if (bytes != null) {
        return Image.memory(
          bytes,
          fit: BoxFit.cover,
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => fallback,
        );
      }
    } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
      return Image.network(
        raw,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => fallback,
      );
    }
    return fallback;
  }

  static Uint8List? decodeBase64DataUri(String uri) {
    final commaIdx = uri.indexOf(',');
    if (commaIdx == -1 || commaIdx + 1 >= uri.length) return null;
    try {
      return base64Decode(uri.substring(commaIdx + 1));
    } catch (_) {
      return null;
    }
  }
}

/// Custom full-screen, theme-aware image viewer with pinch-to-zoom,
/// adaptive system status bar icons, and a close (`X`) button.
class ProductImageViewer extends StatelessWidget {
  const ProductImageViewer({super.key, required this.imageData});

  final String imageData;

  static Future<void> open(BuildContext context, String imageData) {
    return Navigator.of(context).push<void>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => ProductImageViewer(imageData: imageData),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final overlayStyle = (isDark
            ? SystemUiOverlayStyle.light
            : SystemUiOverlayStyle.dark)
        .copyWith(statusBarColor: Colors.transparent);

    final fallback = Icon(
      Icons.broken_image_outlined,
      size: 64,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
    );

    Widget imageWidget = fallback;
    if (imageData.startsWith('data:image')) {
      final bytes = ProductImage.decodeBase64DataUri(imageData);
      if (bytes != null) {
        imageWidget = Image.memory(
          bytes,
          fit: BoxFit.contain,
          errorBuilder: (_, _, _) => fallback,
        );
      }
    } else if (imageData.startsWith('http://') ||
        imageData.startsWith('https://')) {
      imageWidget = Image.network(
        imageData,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => fallback,
      );
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: overlayStyle,
      child: Scaffold(
        backgroundColor: theme.scaffoldBackgroundColor,
        body: SafeArea(
          child: Stack(
            children: [
              Center(
                child: InteractiveViewer(
                  minScale: 0.8,
                  maxScale: 4.0,
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: imageWidget,
                  ),
                ),
              ),
              Positioned(
                top: 8,
                right: 12,
                child: IconButton.filledTonal(
                  tooltip: 'Close',
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

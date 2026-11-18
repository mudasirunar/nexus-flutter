import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Displays a product image from either a compressed `data:image/...;base64,...`
/// string or an `http(s)://` URL, with a clean placeholder fallback.
class ProductImage extends StatelessWidget {
  const ProductImage({
    super.key,
    required this.imageData,
    this.size = 44,
    this.borderRadius = 8,
  });

  final String? imageData;
  final double size;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    final fallback = Icon(
      Icons.inventory_2_outlined,
      size: size * 0.45,
    );

    Widget child = fallback;
    final raw = imageData?.trim();
    if (raw != null && raw.isNotEmpty) {
      if (raw.startsWith('data:image')) {
        final bytes = _decodeBase64DataUri(raw);
        if (bytes != null) {
          child = Image.memory(
            bytes,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => fallback,
          );
        }
      } else if (raw.startsWith('http://') || raw.startsWith('https://')) {
        child = Image.network(
          raw,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => fallback,
        );
      }
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(borderRadius),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  static Uint8List? _decodeBase64DataUri(String uri) {
    final commaIdx = uri.indexOf(',');
    if (commaIdx == -1 || commaIdx + 1 >= uri.length) return null;
    try {
      return base64Decode(uri.substring(commaIdx + 1));
    } catch (_) {
      return null;
    }
  }
}

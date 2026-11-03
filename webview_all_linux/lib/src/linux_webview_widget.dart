import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

import 'linux_webview_controller.dart';
import 'linux_webview_creation_params.dart';

class LinuxWebViewWidget extends PlatformWebViewWidget {
  LinuxWebViewWidget(PlatformWebViewWidgetCreationParams params)
    : super.implementation(
        params is LinuxWebViewWidgetCreationParams
            ? params
            : LinuxWebViewWidgetCreationParams.fromPlatformWebViewWidgetCreationParams(
                params,
              ),
      );

  @override
  Widget build(BuildContext context) {
    final LinuxWebViewController controller =
        params.controller as LinuxWebViewController;
    return _LinuxPlatformWebView(controller: controller, key: params.key);
  }
}

class _LinuxPlatformWebView extends StatefulWidget {
  const _LinuxPlatformWebView({super.key, required this.controller});

  final LinuxWebViewController controller;

  @override
  State<_LinuxPlatformWebView> createState() => _LinuxPlatformWebViewState();
}

class _LinuxViewGeometry {
  const _LinuxViewGeometry({
    required this.frame,
    required this.clip,
    this.roundedClips = const <RRect>[],
  });

  static const _LinuxViewGeometry hidden = _LinuxViewGeometry(
    frame: Rect.zero,
    clip: Rect.zero,
  );

  final Rect frame;
  final Rect clip;
  final List<RRect> roundedClips;

  bool get isVisible =>
      _isUsableRect(frame) && _isUsableRect(clip) && frame.overlaps(clip);

  static bool _isUsableRect(Rect rect) =>
      rect.left.isFinite &&
      rect.top.isFinite &&
      rect.right.isFinite &&
      rect.bottom.isFinite &&
      rect.width > 0 &&
      rect.height > 0;

  @override
  bool operator ==(Object other) =>
      other is _LinuxViewGeometry &&
      other.frame == frame &&
      other.clip == clip &&
      listEquals(other.roundedClips, roundedClips);

  @override
  int get hashCode => Object.hash(frame, clip, Object.hashAll(roundedClips));
}

class _LinuxPlatformWebViewState extends State<_LinuxPlatformWebView>
    with WidgetsBindingObserver {
  _LinuxViewGeometry _lastGeometry = _LinuxViewGeometry.hidden;
  bool _geometryVisible = false;
  bool _applicationVisible = true;
  bool _visibilityCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applicationVisible = _isApplicationVisible(
      WidgetsBinding.instance.lifecycleState,
    );
    _scheduleVisibilityCheck();
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _markGeometryNeedsUpdate();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    final bool applicationVisible = _isApplicationVisible(state);
    if (_applicationVisible == applicationVisible) {
      return;
    }
    _applicationVisible = applicationVisible;
    if (applicationVisible) {
      // Keep the native view hidden until Flutter paints its current geometry.
      // The window may have moved or resized while the app was suspended.
      _geometryVisible = false;
      _markGeometryNeedsUpdate();
      _scheduleVisibilityCheck();
    } else {
      _syncFrame(widget.controller);
    }
  }

  @override
  void didUpdateWidget(_LinuxPlatformWebView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (identical(oldWidget.controller, widget.controller)) {
      return;
    }

    final _LinuxViewGeometry currentGeometry = _lastGeometry;
    _setFrameSafely(
      oldWidget.controller,
      _LinuxViewGeometry.hidden,
      visible: false,
    );
    _setFrameSafely(
      widget.controller,
      _geometryVisible && _applicationVisible
          ? currentGeometry
          : _LinuxViewGeometry.hidden,
      visible: _geometryVisible && _applicationVisible,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setFrameSafely(
      widget.controller,
      _LinuxViewGeometry.hidden,
      visible: false,
    );
    super.dispose();
  }

  void _pushGeometry(_LinuxViewGeometry geometry, {required bool visible}) {
    _lastGeometry = geometry;
    _geometryVisible = visible;
    _syncFrame(widget.controller);
    _scheduleVisibilityCheck();
  }

  void _syncFrame(LinuxWebViewController controller) {
    final bool visible = _geometryVisible && _applicationVisible;
    _setFrameSafely(
      controller,
      visible ? _lastGeometry : _LinuxViewGeometry.hidden,
      visible: visible,
    );
  }

  void _markGeometryNeedsUpdate() {
    if (!mounted) {
      return;
    }
    context.findRenderObject()?.markNeedsPaint();
    // A lifecycle transition does not guarantee another Flutter frame. Make
    // sure the native view is restored without waiting for unrelated UI work.
    WidgetsBinding.instance.ensureVisualUpdate();
  }

  void _scheduleVisibilityCheck() {
    if (_visibilityCheckScheduled || !_applicationVisible) {
      return;
    }
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _visibilityCheckScheduled = false;
      if (!mounted || !_applicationVisible) {
        return;
      }
      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject is _LinuxGeometryRenderBox) {
        renderObject.syncGeometry();
      }
      _scheduleVisibilityCheck();
    });
  }

  static bool _isApplicationVisible(AppLifecycleState? state) {
    return state == null ||
        state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive;
  }

  void _setFrameSafely(
    LinuxWebViewController controller,
    _LinuxViewGeometry geometry, {
    required bool visible,
  }) {
    unawaited(() async {
      try {
        await controller.setFrame(
          geometry.frame,
          clipRect: geometry.clip,
          roundedClips: geometry.roundedClips,
          visible: visible,
        );
      } on StateError catch (error) {
        if (!error.toString().contains('disposed')) {
          debugPrint(
            'webview_all_linux: failed to update the WebView frame: $error',
          );
        }
      } catch (error) {
        debugPrint(
          'webview_all_linux: failed to update the WebView frame: $error',
        );
      }
    }());
  }

  void _handleGeometryChanged(_LinuxViewGeometry geometry) {
    final bool visible = geometry.isVisible;
    if (_geometryVisible != visible || geometry != _lastGeometry) {
      _pushGeometry(
        visible ? geometry : _LinuxViewGeometry.hidden,
        visible: visible,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinuxGeometryObserver(
      onGeometryChanged: _handleGeometryChanged,
      onDetached: () =>
          _pushGeometry(_LinuxViewGeometry.hidden, visible: false),
      child: const SizedBox.expand(),
    );
  }
}

class _LinuxGeometryObserver extends SingleChildRenderObjectWidget {
  const _LinuxGeometryObserver({
    required this.onGeometryChanged,
    required this.onDetached,
    required Widget child,
  }) : super(child: child);

  final ValueChanged<_LinuxViewGeometry> onGeometryChanged;
  final VoidCallback onDetached;

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _LinuxGeometryRenderBox(
      onGeometryChanged: onGeometryChanged,
      onDetached: onDetached,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _LinuxGeometryRenderBox renderObject,
  ) {
    renderObject
      ..onGeometryChanged = onGeometryChanged
      ..onDetached = onDetached;
  }
}

class _LinuxGeometryRenderBox extends RenderProxyBox {
  _LinuxGeometryRenderBox({
    required ValueChanged<_LinuxViewGeometry> onGeometryChanged,
    required VoidCallback onDetached,
  }) : _onGeometryChanged = onGeometryChanged,
       _onDetached = onDetached;

  ValueChanged<_LinuxViewGeometry> _onGeometryChanged;
  VoidCallback _onDetached;
  bool _reportedUnsupportedTransform = false;
  bool _reportedUnsupportedClip = false;

  // Retain a layer for this native-view placeholder so visibility can be checked
  // after compositing. Covered routes and offstage OverlayEntries remain in the
  // render tree, but their layers are detached from the scene.
  @override
  bool get isRepaintBoundary => true;

  bool get isEffectivelyPainted {
    RenderObject child = this;
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      if (!ancestor.paintsChild(child)) {
        return false;
      }
      child = ancestor;
      ancestor = ancestor.parent;
    }
    return true;
  }

  RenderView? get _renderView {
    RenderObject root = this;
    RenderObject? ancestor = parent;
    while (ancestor != null) {
      root = ancestor;
      ancestor = ancestor.parent;
    }
    return root is RenderView ? root : null;
  }

  set onGeometryChanged(ValueChanged<_LinuxViewGeometry> value) {
    _onGeometryChanged = value;
  }

  set onDetached(VoidCallback value) {
    _onDetached = value;
  }

  @override
  void detach() {
    _onDetached();
    super.detach();
  }

  /// Recomputes the on-screen rect of this box and reports it.
  ///
  /// Called after each already-scheduled Flutter frame so the
  /// native overlay keeps tracking composited movement during sliver scrolling
  /// and can detect when a previously clipped child re-enters the viewport.
  void syncGeometry() {
    if (!attached || layer?.attached != true) {
      _onGeometryChanged(_LinuxViewGeometry.hidden);
      return;
    }
    if (!isEffectivelyPainted) {
      _onGeometryChanged(_LinuxViewGeometry.hidden);
      return;
    }
    final RenderView? renderView = _renderView;
    final RenderBox? renderRoot = renderView?.child;
    if (renderView == null || renderRoot == null) {
      _onGeometryChanged(_LinuxViewGeometry.hidden);
      return;
    }
    // Exclude the root DPR transform while inspecting widget transforms. A
    // custom ViewConfiguration can scale the app independently of GTK; convert
    // the resulting geometry into GTK logical pixels after clipping below.
    final Matrix4 transform = getTransformTo(renderRoot);
    final Offset topLeft = MatrixUtils.transformPoint(transform, Offset.zero);
    final Offset topRight = MatrixUtils.transformPoint(
      transform,
      Offset(size.width, 0),
    );
    final Offset bottomLeft = MatrixUtils.transformPoint(
      transform,
      Offset(0, size.height),
    );
    final Offset bottomRight = MatrixUtils.transformPoint(
      transform,
      Offset(size.width, size.height),
    );
    const double epsilon = 0.000001;
    final bool translationOnly =
        (topLeft.dy - topRight.dy).abs() <= epsilon &&
        (topLeft.dx - bottomLeft.dx).abs() <= epsilon &&
        (topRight.dx - bottomRight.dx).abs() <= epsilon &&
        (bottomLeft.dy - bottomRight.dy).abs() <= epsilon &&
        ((topRight.dx - topLeft.dx) - size.width).abs() <= epsilon &&
        ((bottomLeft.dy - topLeft.dy) - size.height).abs() <= epsilon;
    if (!translationOnly) {
      if (!_reportedUnsupportedTransform) {
        debugPrint(
          'webview_all_linux: scaled, rotated, skewed, perspective, and '
          'mirrored WebViewWidget transforms cannot be represented by a '
          'native GTK overlay; the native WebView was hidden.',
        );
        _reportedUnsupportedTransform = true;
      }
      _onGeometryChanged(_LinuxViewGeometry.hidden);
      return;
    }

    final Rect frame = Rect.fromPoints(topLeft, bottomRight);
    Rect clip = frame.intersect(Offset.zero & renderView.size);
    final roundedClips = <RRect>[];
    final pathClips = <Path>[];

    RenderObject child = this;
    RenderObject? ancestor = parent;
    while (ancestor != null && ancestor != renderView) {
      final Rect? localClip = ancestor.describeApproximatePaintClip(child);
      if (localClip != null) {
        final paintClip = _readPaintClip(ancestor, localClip);
        final clipTransform = ancestor.getTransformTo(renderRoot);
        final Rect? transformedClip = _transformAxisAlignedRect(
          clipTransform,
          paintClip.bounds,
        );
        if (transformedClip == null) {
          _reportUnsupportedClip();
          _onGeometryChanged(_LinuxViewGeometry.hidden);
          return;
        }
        clip = clip.intersect(transformedClip);
        if (!_LinuxViewGeometry._isUsableRect(clip)) {
          _onGeometryChanged(_LinuxViewGeometry.hidden);
          return;
        }
        if (paintClip.roundedRect case final roundedRect?) {
          if (!roundedRect.isFinite || roundedRect.hasNaN) {
            _reportUnsupportedClip();
            _onGeometryChanged(_LinuxViewGeometry.hidden);
            return;
          }
          if (!roundedRect.isRect) {
            final transformed = _transformRoundedRect(
              clipTransform,
              roundedRect,
              transformedClip,
            );
            if (transformed == null) {
              _reportUnsupportedClip();
              _onGeometryChanged(_LinuxViewGeometry.hidden);
              return;
            }
            roundedClips.add(transformed);
          }
        } else if (paintClip.path case final path?) {
          pathClips.add(path.transform(clipTransform.storage));
        }
      }
      if (identical(ancestor, renderRoot)) {
        break;
      }
      child = ancestor;
      ancestor = ancestor.parent;
    }

    // Check containment after all ancestor bounds have been intersected. A
    // rectangular outer clip can make a more complex inner clip irrelevant.
    // Approximate bounds alone cannot prove containment of paths with holes.
    for (final path in pathClips) {
      try {
        final outside = Path.combine(
          PathOperation.difference,
          Path()..addRect(clip),
          path,
        );
        if (outside.computeMetrics().isNotEmpty) {
          _reportUnsupportedClip();
          _onGeometryChanged(_LinuxViewGeometry.hidden);
          return;
        }
      } catch (_) {
        _reportUnsupportedClip();
        _onGeometryChanged(_LinuxViewGeometry.hidden);
        return;
      }
    }

    final double scale =
        renderView.configuration.devicePixelRatio /
        renderView.flutterView.devicePixelRatio;
    if (!scale.isFinite || scale <= 0) {
      _onGeometryChanged(_LinuxViewGeometry.hidden);
      return;
    }
    Rect gtkRect(Rect rect) => Rect.fromLTRB(
      rect.left * scale,
      rect.top * scale,
      rect.right * scale,
      rect.bottom * scale,
    );
    _onGeometryChanged(
      _LinuxViewGeometry(
        frame: gtkRect(frame),
        clip: gtkRect(clip),
        roundedClips: <RRect>[
          for (final rounded in roundedClips)
            if (!_containsRect(rounded, clip))
              RRect.fromRectAndCorners(
                gtkRect(rounded.outerRect),
                topLeft: rounded.tlRadius * scale,
                topRight: rounded.trRadius * scale,
                bottomRight: rounded.brRadius * scale,
                bottomLeft: rounded.blRadius * scale,
              ),
        ],
      ),
    );
  }

  _LinuxPaintClip _readPaintClip(RenderObject ancestor, Rect approximate) {
    if (ancestor is RenderClipRect) {
      return _LinuxPaintClip.rect(
        ancestor.clipper?.getClip(ancestor.size) ??
            (Offset.zero & ancestor.size),
      );
    }
    if (ancestor is RenderClipRRect) {
      return _LinuxPaintClip.rounded(
        ancestor.clipper?.getClip(ancestor.size) ??
            ancestor.borderRadius
                .resolve(ancestor.textDirection)
                .toRRect(Offset.zero & ancestor.size),
      );
    }
    if (ancestor is RenderClipOval) {
      final rect =
          ancestor.clipper?.getClip(ancestor.size) ??
          (Offset.zero & ancestor.size);
      return _LinuxPaintClip.rounded(
        RRect.fromRectXY(rect, rect.width / 2, rect.height / 2),
      );
    }
    if (ancestor is RenderPhysicalModel) {
      final rect = Offset.zero & ancestor.size;
      return _LinuxPaintClip.rounded(
        ancestor.clipper?.getClip(ancestor.size) ??
            (ancestor.shape == BoxShape.circle
                ? RRect.fromRectXY(rect, rect.width / 2, rect.height / 2)
                : (ancestor.borderRadius ?? BorderRadius.zero).toRRect(rect)),
      );
    }
    CustomClipper<Path>? pathClipper;
    Size? clipSize;
    if (ancestor is RenderClipPath) {
      pathClipper = ancestor.clipper;
      clipSize = ancestor.size;
    } else if (ancestor is RenderPhysicalShape) {
      pathClipper = ancestor.clipper;
      clipSize = ancestor.size;
    } else if (ancestor is RenderClipRSuperellipse) {
      final shape =
          ancestor.clipper?.getClip(ancestor.size) ??
          ancestor.borderRadius
              .resolve(ancestor.textDirection)
              .toRSuperellipse(Offset.zero & ancestor.size);
      return _LinuxPaintClip.path(Path()..addRSuperellipse(shape));
    }
    if (clipSize != null) {
      final rect = Offset.zero & clipSize;
      if (pathClipper == null) {
        return _LinuxPaintClip.rect(rect);
      }
      // NavigationView and other ShapeBorder-based widgets use ClipPath even
      // for ordinary rectangles and rounded rectangles.
      if (pathClipper.runtimeType == ShapeBorderClipper &&
          pathClipper is ShapeBorderClipper &&
          pathClipper.shape.runtimeType == RoundedRectangleBorder) {
        final shape = pathClipper.shape as RoundedRectangleBorder;
        return _LinuxPaintClip.rounded(
          shape.borderRadius.resolve(pathClipper.textDirection).toRRect(rect),
        );
      }
      return _LinuxPaintClip.path(pathClipper.getClip(clipSize));
    }
    return _LinuxPaintClip.rect(approximate);
  }

  bool _containsRect(RRect shape, Rect rect) =>
      shape.contains(rect.topLeft) &&
      shape.contains(rect.topRight) &&
      shape.contains(rect.bottomLeft) &&
      shape.contains(rect.bottomRight);

  RRect? _transformRoundedRect(Matrix4 matrix, RRect shape, Rect bounds) {
    // Perspective can preserve a rectangular bounding box while changing its
    // corner curves. Only affine, axis-aligned transforms preserve RRects.
    if (matrix.entry(3, 0) != 0 ||
        matrix.entry(3, 1) != 0 ||
        matrix.entry(3, 3) != 1) {
      return null;
    }
    final radii = <Radius>[Radius.zero, Radius.zero, Radius.zero, Radius.zero];
    final corners = <(Offset, Radius)>[
      (shape.outerRect.topLeft, shape.tlRadius),
      (shape.outerRect.topRight, shape.trRadius),
      (shape.outerRect.bottomRight, shape.brRadius),
      (shape.outerRect.bottomLeft, shape.blRadius),
    ];
    for (final (point, radius) in corners) {
      final transformed = MatrixUtils.transformPoint(matrix, point);
      final left = (transformed.dx - bounds.left).abs() < 0.000001;
      final top = (transformed.dy - bounds.top).abs() < 0.000001;
      final index = top ? (left ? 0 : 1) : (left ? 3 : 2);
      radii[index] = Radius.elliptical(
        matrix.entry(0, 0).abs() * radius.x +
            matrix.entry(0, 1).abs() * radius.y,
        matrix.entry(1, 0).abs() * radius.x +
            matrix.entry(1, 1).abs() * radius.y,
      );
    }
    return RRect.fromRectAndCorners(
      bounds,
      topLeft: radii[0],
      topRight: radii[1],
      bottomRight: radii[2],
      bottomLeft: radii[3],
    ).scaleRadii();
  }

  Rect? _transformAxisAlignedRect(Matrix4 transform, Rect rect) {
    final List<Offset> corners = <Offset>[
      MatrixUtils.transformPoint(transform, rect.topLeft),
      MatrixUtils.transformPoint(transform, rect.topRight),
      MatrixUtils.transformPoint(transform, rect.bottomRight),
      MatrixUtils.transformPoint(transform, rect.bottomLeft),
    ];
    if (corners.any(
      (Offset point) => !point.dx.isFinite || !point.dy.isFinite,
    )) {
      return null;
    }

    const double epsilon = 0.000001;
    bool horizontal(Offset first, Offset second) =>
        (first.dy - second.dy).abs() <= epsilon;
    bool vertical(Offset first, Offset second) =>
        (first.dx - second.dx).abs() <= epsilon;

    final bool horizontalFirst =
        horizontal(corners[0], corners[1]) &&
        vertical(corners[1], corners[2]) &&
        horizontal(corners[2], corners[3]) &&
        vertical(corners[3], corners[0]);
    final bool verticalFirst =
        vertical(corners[0], corners[1]) &&
        horizontal(corners[1], corners[2]) &&
        vertical(corners[2], corners[3]) &&
        horizontal(corners[3], corners[0]);
    if (!horizontalFirst && !verticalFirst) {
      return null;
    }

    return MatrixUtils.transformRect(transform, rect);
  }

  void _reportUnsupportedClip() {
    if (_reportedUnsupportedClip) {
      return;
    }
    debugPrint(
      'webview_all_linux: this Flutter clip cannot be represented by the '
      'native GTK overlay. Rectangular, rounded-rectangular and oval clips '
      'are supported; other paths must fully contain the visible WebView. '
      'The native WebView was hidden to avoid drawing or receiving input '
      'outside the clip.',
    );
    _reportedUnsupportedClip = true;
  }
}

class _LinuxPaintClip {
  _LinuxPaintClip.rect(this.bounds) : roundedRect = null, path = null;

  _LinuxPaintClip.rounded(RRect shape)
    : roundedRect = shape.scaleRadii(),
      bounds = shape.outerRect,
      path = null;

  _LinuxPaintClip.path(Path shape)
    : path = shape,
      bounds = shape.getBounds(),
      roundedRect = null;

  final Rect bounds;
  final RRect? roundedRect;
  final Path? path;
}

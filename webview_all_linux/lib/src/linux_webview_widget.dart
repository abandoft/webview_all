import 'dart:async';

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

class _LinuxPlatformWebViewState extends State<_LinuxPlatformWebView>
    with WidgetsBindingObserver {
  Rect _lastRect = Rect.zero;
  bool _attached = false;
  bool _applicationVisible = true;
  bool _visibilityCheckScheduled = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applicationVisible = _isApplicationVisible(
      WidgetsBinding.instance.lifecycleState,
    );
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
      _attached = false;
      _markGeometryNeedsUpdate();
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

    final Rect currentRect = _lastRect;
    _setFrameSafely(oldWidget.controller, Rect.zero, visible: false);
    _setFrameSafely(
      widget.controller,
      _attached && _applicationVisible ? currentRect : Rect.zero,
      visible: _attached && _applicationVisible,
    );
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setFrameSafely(widget.controller, Rect.zero, visible: false);
    super.dispose();
  }

  void _pushRect(Rect rect, {required bool visible}) {
    _lastRect = rect;
    _attached = visible;
    _syncFrame(widget.controller);
    if (visible) {
      _scheduleVisibilityCheck();
    }
  }

  void _syncFrame(LinuxWebViewController controller) {
    final bool visible = _attached && _applicationVisible;
    _setFrameSafely(
      controller,
      visible ? _lastRect : Rect.zero,
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
    if (_visibilityCheckScheduled || !_attached || !_applicationVisible) {
      return;
    }
    _visibilityCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((Duration _) {
      _visibilityCheckScheduled = false;
      if (!mounted || !_attached || !_applicationVisible) {
        return;
      }
      final RenderObject? renderObject = context.findRenderObject();
      if (renderObject is _LinuxGeometryRenderBox &&
          !renderObject.isEffectivelyPainted) {
        _pushRect(Rect.zero, visible: false);
        return;
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
    Rect rect, {
    required bool visible,
  }) {
    unawaited(() async {
      try {
        await controller.setFrame(rect, visible: visible);
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

  void _handleGeometryChanged(Rect rect) {
    final bool visible =
        rect.left.isFinite &&
        rect.top.isFinite &&
        rect.width.isFinite &&
        rect.height.isFinite &&
        rect.width > 0 &&
        rect.height > 0;
    if (_attached != visible || rect != _lastRect) {
      _pushRect(visible ? rect : Rect.zero, visible: visible);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LinuxGeometryObserver(
      onGeometryChanged: _handleGeometryChanged,
      onDetached: () => _pushRect(Rect.zero, visible: false),
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

  final ValueChanged<Rect> onGeometryChanged;
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
    required ValueChanged<Rect> onGeometryChanged,
    required VoidCallback onDetached,
  }) : _onGeometryChanged = onGeometryChanged,
       _onDetached = onDetached;

  ValueChanged<Rect> _onGeometryChanged;
  VoidCallback _onDetached;
  bool _reportedUnsupportedTransform = false;

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

  set onGeometryChanged(ValueChanged<Rect> value) {
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

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    if (!attached) {
      return;
    }
    if (!isEffectivelyPainted) {
      _onGeometryChanged(Rect.zero);
      return;
    }
    final RenderView? renderView = _renderView;
    final RenderBox? renderRoot = renderView?.child;
    if (renderView == null || renderRoot == null) {
      _onGeometryChanged(Rect.zero);
      return;
    }
    // GTK and RenderView layout both use logical pixels. Targeting the
    // RenderView child deliberately excludes RenderView's root DPR transform.
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
      _onGeometryChanged(Rect.zero);
      return;
    }

    final Rect rect = Rect.fromPoints(topLeft, bottomRight);
    final Rect viewport = Offset.zero & renderView.size;
    _onGeometryChanged(rect.overlaps(viewport) ? rect : Rect.zero);
  }
}

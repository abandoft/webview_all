import 'dart:async';
import 'dart:math' as math;

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    _pushRect(_lastRect, visible: _attached);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setFrameSafely(Rect.zero, visible: false);
    super.dispose();
  }

  void _pushRect(Rect rect, {required bool visible}) {
    _lastRect = rect;
    _attached = visible;
    _setFrameSafely(rect, visible: visible);
  }

  void _setFrameSafely(Rect rect, {required bool visible}) {
    unawaited(() async {
      try {
        await widget.controller.setFrame(rect, visible: visible);
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
    final Matrix4 transform = getTransformTo(null);
    final Offset topLeft = MatrixUtils.transformPoint(transform, Offset.zero);
    final Offset bottomRight = MatrixUtils.transformPoint(
      transform,
      Offset(size.width, size.height),
    );
    final Rect rect = Rect.fromLTRB(
      math.min(topLeft.dx, bottomRight.dx),
      math.min(topLeft.dy, bottomRight.dy),
      math.max(topLeft.dx, bottomRight.dx),
      math.max(topLeft.dy, bottomRight.dy),
    );
    _onGeometryChanged(rect);
  }
}

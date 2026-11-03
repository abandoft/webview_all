import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_all_linux/webview_all_linux.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final (name, wrap) in <(String, Widget Function(Widget))>[
    ('default ClipPath', (child) => ClipPath(child: child)),
    (
      'rectangular ShapeBorderClipper',
      (child) => ClipPath(
        clipper: const ShapeBorderClipper(shape: RoundedRectangleBorder()),
        child: child,
      ),
    ),
    ('zero-radius ClipRRect', (child) => ClipRRect(child: child)),
    (
      'zero-radius ClipRSuperellipse',
      (child) => ClipRSuperellipse(child: child),
    ),
    (
      'disabled path clipping',
      (child) => ClipPath(
        clipBehavior: Clip.none,
        clipper: _PathClipper(_holedPath),
        child: child,
      ),
    ),
  ]) {
    testWidgets('keeps $name visible', (tester) async {
      final harness = _ClipHarness(tester);
      await harness.pump(wrap);
      expect(harness.frame['visible'], isTrue);
      expect(harness.frame['roundedClips'], isEmpty);
    });
  }

  testWidgets('clips to the actual rectangle of a custom path', (tester) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipPath(
        clipper: _PathClipper(
          (_) => Path()..addRect(const Rect.fromLTWH(10, 20, 60, 40)),
        ),
        child: child,
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['clipX'], 10);
    expect(harness.frame['clipY'], 20);
    expect(harness.frame['clipWidth'], 60);
    expect(harness.frame['clipHeight'], 40);
    expect(harness.frame['roundedClips'], isEmpty);
  });

  testWidgets('supports the default NavigationView content shape', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipPath(
        clipper: const ShapeBorderClipper(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.only(topLeft: Radius.circular(8)),
          ),
        ),
        child: child,
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['width'], 100);
    expect(harness.frame['height'], 80);
    expect(harness.frame['roundedClips'], <List<double>>[
      <double>[0, 0, 100, 80, 8, 8, 0, 0, 0, 0, 0, 0],
    ]);
  });

  testWidgets('preserves RTL corner placement', (tester) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipPath(
        clipper: const ShapeBorderClipper(
          textDirection: TextDirection.rtl,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadiusDirectional.only(
              topStart: Radius.circular(8),
            ),
          ),
        ),
        child: child,
      ),
    );
    expect(harness.frame['roundedClips'], <List<double>>[
      <double>[0, 0, 100, 80, 0, 0, 8, 8, 0, 0, 0, 0],
    ]);
  });

  testWidgets('keeps a WebView fully inside a rounded ancestor unmasked', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Padding(padding: const EdgeInsets.all(20), child: child),
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['x'], 20);
    expect(harness.frame['y'], 20);
    expect(harness.frame['roundedClips'], isEmpty);
  });

  testWidgets('keeps a WebView fully inside an arbitrary path visible', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipPath(
        clipper: _PathClipper((size) => Path()..addOval(Offset.zero & size)),
        child: Padding(padding: const EdgeInsets.all(60), child: child),
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['roundedClips'], isEmpty);
  });

  testWidgets('intersects nested rounded clips without resizing the page', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(30)),
        child: ClipPath(
          clipper: const ShapeBorderClipper(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.only(bottomRight: Radius.circular(20)),
            ),
          ),
          child: child,
        ),
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['width'], 100);
    expect(harness.frame['height'], 80);
    expect(harness.frame['roundedClips'], hasLength(2));
  });

  testWidgets('checks path containment after intersecting outer clips', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipRect(
        clipper: const _RectClipper(Rect.fromLTWH(10, 10, 20, 20)),
        child: ClipPath(
          clipper: _PathClipper(
            (size) => Path()
              ..lineTo(size.width, 0)
              ..lineTo(0, size.height)
              ..close(),
          ),
          child: child,
        ),
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['clipX'], 10);
    expect(harness.frame['clipY'], 10);
    expect(harness.frame['clipWidth'], 20);
    expect(harness.frame['clipHeight'], 20);
  });

  testWidgets(
    'rotates ancestor corner radii while keeping the WebView upright',
    (tester) async {
      final harness = _ClipHarness(tester);
      await harness.pump(
        (child) => Transform.rotate(
          angle: math.pi / 2,
          child: ClipRRect(
            borderRadius: const BorderRadius.only(
              topLeft: Radius.elliptical(12, 6),
            ),
            child: Transform.rotate(angle: -math.pi / 2, child: child),
          ),
        ),
      );
      expect(harness.frame['visible'], isTrue);
      final fields = (harness.frame['roundedClips'] as List).single as List;
      expect(fields[4], 0);
      expect(fields[5], 0);
      expect(fields[6], closeTo(6, .000001));
      expect(fields[7], closeTo(12, .000001));
      expect(fields.sublist(8), <double>[0, 0, 0, 0]);
    },
  );

  testWidgets('tracks a clipper animation and clears the native mask', (
    tester,
  ) async {
    final radius = ValueNotifier<double>(8);
    addTearDown(radius.dispose);
    final harness = _ClipHarness(tester);
    final widget = ClipRRect(
      clipper: _AnimatedRoundedClipper(radius),
      child: harness.child,
    );
    await harness.pump((_) => widget);
    expect((harness.frame['roundedClips'] as List).single, <double>[
      0,
      0,
      100,
      80,
      8,
      8,
      8,
      8,
      8,
      8,
      8,
      8,
    ]);
    radius.value = 20;
    await tester.pump();
    expect((harness.frame['roundedClips'] as List).single, <double>[
      0,
      0,
      100,
      80,
      20,
      20,
      20,
      20,
      20,
      20,
      20,
      20,
    ]);
    radius.value = 0;
    await tester.pump();
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['roundedClips'], isEmpty);
  });

  testWidgets('scales ancestor clips into GTK logical pixels', (tester) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => Transform.scale(
        scale: 2,
        alignment: Alignment.topLeft,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Transform.scale(
            scale: .5,
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['width'], 100);
    expect(harness.frame['roundedClips'], <List<double>>[
      <double>[0, 0, 200, 160, 16, 16, 16, 16, 16, 16, 16, 16],
    ]);
  });

  testWidgets('supports oval and physical rounded clips', (tester) async {
    final harness = _ClipHarness(tester);
    await harness.pump((child) => ClipOval(child: child));
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['roundedClips'], <List<double>>[
      <double>[0, 0, 100, 80, 50, 40, 50, 40, 50, 40, 50, 40],
    ]);
    await harness.pump(
      (child) => PhysicalModel(
        color: Colors.white,
        clipBehavior: Clip.antiAlias,
        borderRadius: BorderRadius.circular(12),
        child: child,
      ),
    );
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['roundedClips'], <List<double>>[
      <double>[0, 0, 100, 80, 12, 12, 12, 12, 12, 12, 12, 12],
    ]);
  });

  testWidgets('rejects path holes and resumes after unsupported clipping', (
    tester,
  ) async {
    final harness = _ClipHarness(tester);
    await harness.pump(
      (child) => ClipPath(clipper: _PathClipper(_holedPath), child: child),
    );
    expect(harness.frame['visible'], isFalse);
    await harness.pump((child) => ClipRect(child: child));
    expect(harness.frame['visible'], isTrue);
    expect(harness.frame['roundedClips'], isEmpty);
  });

  testWidgets(
    'does not treat a custom border subclass as a rounded rectangle',
    (tester) async {
      final harness = _ClipHarness(tester);
      await harness.pump(
        (child) => ClipPath(
          clipper: const ShapeBorderClipper(shape: _HoledBorder()),
          child: child,
        ),
      );
      expect(harness.frame['visible'], isFalse);
    },
  );
}

Path _holedPath(Size size) => Path()
  ..fillType = PathFillType.evenOdd
  ..addRect(Offset.zero & size)
  ..addRect(
    Rect.fromCenter(center: size.center(Offset.zero), width: 20, height: 20),
  );

class _PathClipper extends CustomClipper<Path> {
  _PathClipper(this.build);

  final Path Function(Size) build;

  @override
  Path getClip(Size size) => build(size);

  @override
  bool shouldReclip(covariant _PathClipper oldClipper) => true;
}

class _RectClipper extends CustomClipper<Rect> {
  const _RectClipper(this.rect);

  final Rect rect;

  @override
  Rect getClip(Size size) => rect;

  @override
  bool shouldReclip(covariant _RectClipper oldClipper) =>
      oldClipper.rect != rect;
}

class _HoledBorder extends RoundedRectangleBorder {
  const _HoledBorder();

  @override
  Path getOuterPath(Rect rect, {TextDirection? textDirection}) =>
      _holedPath(rect.size).shift(rect.topLeft);
}

class _AnimatedRoundedClipper extends CustomClipper<RRect> {
  _AnimatedRoundedClipper(this.radius) : super(reclip: radius);

  final ValueNotifier<double> radius;

  @override
  RRect getClip(Size size) => RRect.fromRectAndRadius(
    Offset.zero & size,
    Radius.circular(radius.value),
  );

  @override
  bool shouldReclip(covariant _AnimatedRoundedClipper oldClipper) =>
      oldClipper.radius != radius;
}

int _nextId = 0;

class _ClipHarness {
  _ClipHarness(this.tester) {
    final id = ++_nextId;
    const prefix = 'com.abandoft.webview_all_linux';
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel(prefix), (
      call,
    ) async {
      return call.method == 'createWebView' ? id : null;
    });
    messenger.setMockMethodCallHandler(MethodChannel('$prefix/$id'), (
      call,
    ) async {
      calls.add(call);
      return null;
    });
    messenger.setMockMethodCallHandler(
      MethodChannel('$prefix/$id/events'),
      (_) async => null,
    );
    controller = LinuxWebViewController(
      const PlatformWebViewControllerCreationParams(),
    );
    final widget = LinuxWebViewWidget(
      PlatformWebViewWidgetCreationParams(controller: controller),
    );
    child = SizedBox(
      width: 100,
      height: 80,
      child: Builder(builder: widget.build),
    );
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = controller.dispose();
      await tester.pump();
      await disposal;
      for (final channel in <String>[
        prefix,
        '$prefix/$id',
        '$prefix/$id/events',
      ]) {
        messenger.setMockMethodCallHandler(MethodChannel(channel), null);
      }
    });
  }

  final WidgetTester tester;
  final calls = <MethodCall>[];
  late final LinuxWebViewController controller;
  late final Widget child;
  bool _mounted = false;

  Map<Object?, Object?> get frame =>
      calls.lastWhere((call) => call.method == 'setFrame').arguments
          as Map<Object?, Object?>;

  Future<void> pump(Widget Function(Widget) wrap) async {
    // Start visible so rejection also exercises hiding an existing native view.
    if (!_mounted) {
      _mounted = true;
      await pump((child) => child);
    }
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Align(alignment: Alignment.topLeft, child: wrap(child)),
      ),
    );
    await tester.pump();
  }
}

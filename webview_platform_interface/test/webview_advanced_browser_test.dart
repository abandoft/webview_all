import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/painting.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:webview_platform_interface/webview_platform_interface.dart';

class _Controller extends PlatformWebViewController
    with WebViewNetworkControllerMixin {
  _Controller()
    : super.implementation(
        const PlatformWebViewControllerCreationParams(
          customSchemes: ['appfixture'],
        ),
      );
  final active = <String, String>{};
  var accept = true;
  var configuredRules = <Map<String, Object?>>[];
  @override
  Future<WebViewNetworkCapabilities> getNetworkCapabilities() async =>
      const WebViewNetworkCapabilities(
        contentRules: true,
        httpInterception: true,
        customSchemes: true,
        streamingResponses: true,
      );
  @override
  Future<bool> configureContentRules(List<Map<String, Object?>> rules) async {
    configuredRules = rules;
    return true;
  }

  @override
  Future<bool> configureNetworkBridge(Map<String, Object?> args) async {
    final kind = args['kind']! as String, channel = args['channel']! as String;
    if (args['enabled'] == true) {
      if (!accept) return false;
      active[kind] = channel;
    } else if (active[kind] == channel) {
      active.remove(kind);
    }
    return true;
  }

  WebViewResourceBridge bridge(String kind) =>
      networkBridgeForChannel(active[kind]!)!;
  Future<Uint8List?> screenshot(
    WebViewScreenshotOptions options,
    Future<Uint8List?> Function() raw,
  ) => captureScreenshot(options, raw);
}

class _Data extends PlatformWebViewDataManager {
  _Data()
    : super.implementation(const PlatformWebViewDataManagerCreationParams());
  bool fail = false;
  int calls = 0;
  @override
  Future<WebViewDataCapabilities> getCapabilities() async {
    if (fail) throw StateError('store unavailable');
    return WebViewDataCapabilities(
      scopedClearingGroups: {
        WebViewDataScope.site: [WebViewDataType.values.toSet()],
        WebViewDataScope.domain: [
          {WebViewDataType.localStorage},
        ],
      },
    );
  }

  @override
  Future<WebViewDataClearingResult> clearWebsiteDataFor(
    WebViewDataTarget target, {
    required Set<WebViewDataType> dataTypes,
  }) => clearScopedData(target, dataTypes, (_) async {
    calls++;
  });
}

Future<Map<Object?, Object?>> open(
  WebViewResourceBridge bridge,
  String id,
  String uri, {
  String method = 'GET',
  Uint8List? body,
  bool available = false,
}) async =>
    (await bridge.handleCall(
          MethodCall('open', {
            'id': id,
            'uri': uri,
            'method': method,
            'headers': <String, String>{},
            'body': body,
            'bodyAvailable': available,
          }),
        ))!
        as Map<Object?, Object?>;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'unsupported full-document capture never falls back to the viewport',
    () async {
      var calls = 0;
      expect(
        await _Controller().screenshot(
          const WebViewScreenshotOptions(fullDocument: true),
          () async {
            calls++;
            return Uint8List(1);
          },
        ),
        isNull,
      );
      expect(calls, 0);
    },
  );
  test(
    'native rule conditions validate whole sets without widening support',
    () async {
      final controller = _Controller();
      expect(
        await controller.setContentRules([WebViewContentRule(urlPattern: '*')]),
        isTrue,
      );
      for (final rule in [
        WebViewContentRule(urlPattern: '*', ifDomains: ['example.com']),
        WebViewContentRule(
          urlPattern: '*',
          ifTopUrls: ['https://example.com/*'],
        ),
        WebViewContentRule(
          urlPattern: '*',
          loadTypes: {WebViewContentRuleLoadType.thirdParty},
        ),
        WebViewContentRule(
          urlPattern: '*',
          action: WebViewContentRuleAction.hideElements,
          selector: '.ad',
        ),
        WebViewContentRule(
          urlPattern: '*',
          action: WebViewContentRuleAction.upgradeToHttps,
        ),
      ]) {
        expect(rule.isValid, isTrue);
        expect(await controller.setContentRules([rule]), isFalse);
        expect(controller.configuredRules.single['action'], 'block');
      }
      for (final rule in [
        WebViewContentRule(urlPattern: '*', ifDomains: ['Example.com']),
        WebViewContentRule(urlPattern: '*', ifDomains: ['*.example.com']),
        WebViewContentRule(
          urlPattern: '*',
          ifDomains: ['example.com'],
          unlessDomains: ['other.com'],
        ),
        WebViewContentRule(
          urlPattern: '*',
          ifDomains: ['example.com'],
          ifTopUrls: ['*'],
        ),
        WebViewContentRule(
          urlPattern: '*',
          action: WebViewContentRuleAction.hideElements,
        ),
        WebViewContentRule(urlPattern: '*', selector: '.unexpected'),
      ]) {
        expect(rule.isValid, isFalse);
      }
      expect(
        WebViewContentRule(
          urlPattern: '*',
          ifDomains: ['*example.com'],
        ).toMap()['ifDomains'],
        ['*example.com'],
      );
      await controller.disposeNetworkBridges();
    },
  );

  test(
    'screenshots crop and scale native PNG pixels without including overlays',
    () async {
      final recorder = ui.PictureRecorder();
      ui.Canvas(
        recorder,
      ).drawPaint(ui.Paint()..color = const ui.Color(0xffff0000));
      final picture = recorder.endRecording();
      final image = await picture.toImage(30, 20);
      final data = (await image.toByteData(format: ui.ImageByteFormat.png))!;
      final png = data.buffer.asUint8List(
        data.offsetInBytes,
        data.lengthInBytes,
      );
      image.dispose();
      picture.dispose();
      final controller = _Controller();
      final cropped = (await controller.screenshot(
        const WebViewScreenshotOptions(
          region: ui.Rect.fromLTWH(5, 5, 10, 8),
          scale: 2,
        ),
        () async => png,
      ))!;
      final codec = await ui.instantiateImageCodec(cropped);
      final output = (await codec.getNextFrame()).image;
      expect(output.width, 20);
      expect(output.height, 16);
      final rgba = (await output.toByteData())!;
      expect(rgba.getUint8(0), 255);
      expect(rgba.getUint8(1), 0);
      output.dispose();
      codec.dispose();
      expect(
        await controller.screenshot(
          const WebViewScreenshotOptions(region: ui.Rect.fromLTWH(29, 0, 3, 2)),
          () async => png,
        ),
        isNull,
      );
      var captures = 0;
      expect(
        await controller.screenshot(
          const WebViewScreenshotOptions(scale: -1),
          () async {
            captures++;
            return png;
          },
        ),
        isNull,
      );
      expect(captures, 0);
    },
  );

  test('PDF validation includes oriented dimensions and printable margins', () {
    expect(const WebViewPdfOptions().isValid, isTrue);
    expect(
      const WebViewPdfOptions(
        paperSize: ui.Size(100, 200),
        landscape: true,
        margins: EdgeInsets.symmetric(horizontal: 60, vertical: 10),
      ).isValid,
      isTrue,
    );
    expect(
      const WebViewPdfOptions(
        paperSize: ui.Size(100, 200),
        margins: EdgeInsets.symmetric(horizontal: 60, vertical: 10),
      ).isValid,
      isFalse,
    );
    expect(
      const WebViewPdfOptions(paperSize: ui.Size(double.nan, 100)).isValid,
      isFalse,
    );
  });

  test(
    'navigation snapshot disposal is idempotent and contains release errors',
    () async {
      var releases = 0;
      final state = WebViewNavigationState(
        platform: 'fixture',
        identifier: 'opaque',
        onDispose: () async {
          releases++;
          throw StateError('engine detached');
        },
      );
      expect(state.canPersist, isFalse);
      await Future.wait([state.dispose(), state.dispose()]);
      expect(releases, 1);
      expect(state.isDisposed, isTrue);
    },
  );

  test(
    'print panel presentation is not reported as successful printing',
    () async {
      final job = WebViewPrintJob(initialState: WebViewPrintState.presented);
      expect(job.canQueryState, isFalse);
      expect(job.canCancel, isFalse);
      expect(await job.getState(), WebViewPrintState.presented);
      expect(await job.cancel(), isFalse);
      await job.dispose();
      expect(await job.getState(), WebViewPrintState.unknown);
    },
  );

  test(
    'releasing a print handle does not cancel the OS job and joins disposal',
    () async {
      final release = Completer<void>();
      var cancels = 0, releases = 0;
      final job = WebViewPrintJob(
        initialState: WebViewPrintState.queued,
        readState: () async => WebViewPrintState.completed,
        cancel: () async {
          cancels++;
          return true;
        },
        release: () {
          releases++;
          return release.future;
        },
      );
      expect(await job.getState(), WebViewPrintState.completed);
      final first = job.dispose(), second = job.dispose();
      expect(identical(first, second), isTrue);
      expect(releases, 1);
      expect(cancels, 0);
      release.complete();
      await first;
    },
  );

  test(
    'origin removal never broadens to a domain or site and respects atomic groups',
    () async {
      final data = _Data();
      final origin = WebViewDataTarget.origin(
        Uri.parse('https://one.example.test:8443'),
      );
      final unsupported = await data.clearWebsiteDataFor(
        origin,
        dataTypes: WebViewDataType.values.toSet(),
      );
      expect(unsupported.unsupportedDataTypes, WebViewDataType.values.toSet());
      expect(data.calls, 0);
      const site = WebViewDataTarget(
        scope: WebViewDataScope.site,
        value: 'example.test',
      );
      expect(
        (await data.clearWebsiteDataFor(
          site,
          dataTypes: {WebViewDataType.cookies},
        )).isComplete,
        isFalse,
      );
      expect(data.calls, 0);
      expect(
        (await data.clearWebsiteDataFor(
          site,
          dataTypes: WebViewDataType.values.toSet(),
        )).isComplete,
        isTrue,
      );
      expect(data.calls, 1);
      const ipv6Record = WebViewDataTarget(
        scope: WebViewDataScope.domain,
        value: '::1',
      );
      expect(
        (await data.clearWebsiteDataFor(
          ipv6Record,
          dataTypes: {WebViewDataType.localStorage},
        )).isComplete,
        isTrue,
      );
      data.fail = true;
      expect(
        (await data.clearWebsiteDataFor(
          site,
          dataTypes: {WebViewDataType.cookies},
        )).failures,
        isNotEmpty,
      );
    },
  );

  test(
    'native request decisions retain POST metadata and enforce URL selection',
    () async {
      final controller = _Controller();
      var calls = 0;
      expect(
        await controller.setRequestDelegate(
          WebViewRequestDelegate(
            urlPatterns: ['https://example.test/api/*'],
            onRequest: (request) {
              calls++;
              expect(request.method, 'POST');
              expect(request.bodyAvailable, isFalse);
              expect(request.body, isNull);
              return const WebViewRequestDecision.allow();
            },
          ),
        ),
        isTrue,
      );
      final bridge = controller.bridge('http');
      expect(
        (await open(
          bridge,
          'post',
          'https://example.test/api/send',
          method: 'POST',
        ))['passThrough'],
        isTrue,
      );
      expect(
        (await open(
          bridge,
          'forged',
          'https://other.test/api/send',
        ))['statusCode'],
        403,
      );
      expect(calls, 1);
      await controller.disposeNetworkBridges();
    },
  );

  test(
    'scheme responses do not bypass the declared schemes and keep POST bytes',
    () async {
      final controller = _Controller();
      await controller.setCustomSchemeDelegate(
        WebViewResourceDelegate(
          onRequest: (request) {
            expect(request.uri.scheme, 'appfixture');
            expect(request.bodyAvailable, isTrue);
            expect(request.body, [1, 2, 3]);
            return WebViewResourceResponse.bytes(
              request.body!,
              mimeType: 'application/octet-stream',
            );
          },
        ),
      );
      final bridge = controller.bridge('schemes');
      final response = await open(
        bridge,
        'custom',
        'appfixture://host/send',
        method: 'POST',
        body: Uint8List.fromList([1, 2, 3]),
        available: true,
      );
      expect(response['statusCode'], 200);
      expect(
        await bridge.handleCall(const MethodCall('read', {'id': 'custom'})),
        [1, 2, 3],
      );
      expect(
        (await open(bridge, 'wrong', 'undeclared://host/send'))['statusCode'],
        403,
      );
      await controller.disposeNetworkBridges();
    },
  );

  test(
    'failed delegate replacement retains the previous native endpoint',
    () async {
      final controller = _Controller();
      WebViewRequestDelegate handler() => WebViewRequestDelegate(
        urlPatterns: ['https://example.test/*'],
        onRequest: (_) => const WebViewRequestDecision.allow(),
      );
      await controller.setRequestDelegate(handler());
      final first = controller.bridge('http');
      controller.accept = false;
      expect(await controller.setRequestDelegate(handler()), isFalse);
      expect(identical(controller.bridge('http'), first), isTrue);
      expect(
        (await open(
          first,
          'still-active',
          'https://example.test/',
        ))['passThrough'],
        isTrue,
      );
      await controller.disposeNetworkBridges();
    },
  );

  test(
    'pending native requests are cancelled during controller disposal',
    () async {
      final controller = _Controller();
      final reply = Completer<WebViewRequestDecision>();
      final started = Completer<void>();
      await controller.setRequestDelegate(
        WebViewRequestDelegate(
          urlPatterns: ['https://example.test/*'],
          onRequest: (_) {
            started.complete();
            return reply.future;
          },
        ),
      );
      final request = open(
        controller.bridge('http'),
        'pending',
        'https://example.test/',
      );
      await started.future;
      await controller.disposeNetworkBridges();
      expect((await request)['statusCode'], 404);
      reply.complete(const WebViewRequestDecision.allow());
      expect(await controller.setContentRules([]), isFalse);
    },
  );

  test(
    'unsupported resource types retain rules and wildcard matching is bounded',
    () async {
      final controller = _Controller();
      expect(
        await controller.setContentRules([
          WebViewContentRule(urlPattern: '*ads*'),
        ]),
        isTrue,
      );
      final first = controller.configuredRules;
      expect(
        await controller.setContentRules([
          WebViewContentRule(
            urlPattern: '*',
            resourceTypes: {WebViewNetworkResourceType.image},
          ),
        ]),
        isFalse,
      );
      expect(identical(controller.configuredRules, first), isTrue);
      expect(webViewUrlPatternMatches('a*aa', 'aaa'), isTrue);
      expect(webViewUrlPatternMatches('a*aa', 'aa'), isFalse);
      expect(webViewUrlPatternMatches('*A*B*', 'xxaxbxx'), isTrue);
      expect(isValidWebViewUrlPattern(List.filled(34, '*').join()), isFalse);
      await controller.disposeNetworkBridges();
    },
  );
}

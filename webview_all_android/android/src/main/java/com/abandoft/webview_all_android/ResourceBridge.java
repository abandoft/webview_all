package com.abandoft.webview_all_android;

import android.net.Uri;
import android.os.Handler;
import android.os.Looper;
import android.webkit.WebResourceRequest;
import android.webkit.WebResourceResponse;
import android.webkit.WebView;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.IOException;
import java.io.InputStream;
import java.util.Collections;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.WeakHashMap;
import java.util.concurrent.CountDownLatch;
import java.util.concurrent.TimeUnit;
import java.util.concurrent.atomic.AtomicReference;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/** Engine-scoped configuration and bounded, pull-based resource delivery. */
final class ResourceBridge {
  static final class Registration {
    private final MethodChannel channel;
    private final Map<WebViewProxyApi.WebViewPlatformView, ResourceBridge> bridges =
        new WeakHashMap<>();

    Registration(ProxyApiRegistrar registrar, BinaryMessenger messenger) {
      channel = new MethodChannel(messenger, "com.abandoft.webview_all/resources");
      channel.setMethodCallHandler(
          (call, result) -> {
            if (!call.method.equals("configure") || !(call.arguments instanceof Map)) {
              result.notImplemented();
              return;
            }
            Map<?, ?> args = (Map<?, ?>) call.arguments;
            Object identifier = args.get("webViewId");
            Object object =
                identifier instanceof Number
                    ? registrar.getInstanceManager().getInstance(((Number) identifier).longValue())
                    : null;
            if (!(object instanceof WebViewProxyApi.WebViewPlatformView)
                || !(args.get("channel") instanceof String)
                || !(args.get("host") instanceof String)
                || !(args.get("enabled") instanceof Boolean)) {
              result.error(
                  "invalid_resource_configuration",
                  "Unknown WebView or resource configuration.",
                  null);
              return;
            }
            WebViewProxyApi.WebViewPlatformView view = (WebViewProxyApi.WebViewPlatformView) object;
            ResourceBridge bridge = bridges.get(view);
            if (bridge == null) {
              bridge = new ResourceBridge();
              bridges.put(view, bridge);
              view.resourceBridge = bridge;
            }
            bridge.configure(
                messenger,
                (String) args.get("channel"),
                (String) args.get("host"),
                (Boolean) args.get("enabled"));
            result.success(null);
          });
    }

    void close() {
      channel.setMethodCallHandler(null);
      for (ResourceBridge bridge : bridges.values()) bridge.close();
      bridges.clear();
    }
  }

  private final Handler main = new Handler(Looper.getMainLooper());
  private volatile MethodChannel channel;
  private volatile String host = "";
  private volatile boolean enabled;
  private volatile int generation;

  private void configure(BinaryMessenger messenger, String name, String host, boolean enabled) {
    generation++;
    channel = new MethodChannel(messenger, name);
    this.host = host;
    this.enabled = enabled;
  }

  static WebResourceResponse intercept(WebView view, WebResourceRequest request) {
    if (!(view instanceof WebViewProxyApi.WebViewPlatformView)) return null;
    ResourceBridge bridge = ((WebViewProxyApi.WebViewPlatformView) view).resourceBridge;
    return bridge == null ? null : bridge.intercept(request);
  }

  private WebResourceResponse intercept(WebResourceRequest request) {
    Uri uri = request.getUrl();
    if (!"https".equals(uri.getScheme())
        || !host.equals(uri.getHost())
        || uri.getPort() != -1
        || uri.getUserInfo() != null) return null;
    if (!enabled) return empty(404);
    final MethodChannel target = channel;
    final int expectedGeneration = generation;
    final String id = UUID.randomUUID().toString();
    final Map<String, Object> args = new HashMap<>();
    args.put("id", id);
    args.put("uri", uri.toString());
    args.put("method", request.getMethod());
    args.put("headers", request.getRequestHeaders());
    try {
      Object value = invoke(target, "open", args);
      if (!(value instanceof Map) || generation != expectedGeneration || !enabled) {
        cancel(target, id);
        return empty(404);
      }
      Map<?, ?> response = (Map<?, ?>) value;
      int status = ((Number) response.get("statusCode")).intValue();
      String mimeType = (String) response.get("mimeType");
      Map<String, String> headers = new HashMap<>();
      Object responseHeaders = response.get("headers");
      if (responseHeaders instanceof Map) {
        for (Map.Entry<?, ?> entry : ((Map<?, ?>) responseHeaders).entrySet()) {
          if (entry.getKey() instanceof String && entry.getValue() instanceof String) {
            headers.put((String) entry.getKey(), (String) entry.getValue());
          }
        }
      }
      long length = ((Number) response.get("contentLength")).longValue();
      if (status == 200
          && length != 0
          && !"HEAD".equals(request.getMethod())
          && hasHeader(request.getRequestHeaders(), "range")
          && hasHeader(request.getRequestHeaders(), "if-range")) {
        cancel(target, id);
        android.util.Log.w(
            "webview_all",
            "Android WebView cannot ignore Range for a conditional resource response. Retry without"
                + " Range or If-Range.");
        return empty(501);
      }
      long representationLength = length;
      long rangeOffset = 0;
      final String contentRange = headers.get("content-range");
      if (status == 206 && contentRange != null) {
        final Matcher range = Pattern.compile("bytes (\\d+)-(\\d+)/(\\d+)").matcher(contentRange);
        if (range.matches()) {
          rangeOffset = Long.parseLong(range.group(1));
          representationLength = Long.parseLong(range.group(3));
        }
      }
      boolean emptyBody = "HEAD".equals(request.getMethod()) || length == 0;
      if (!emptyBody && representationLength > Integer.MAX_VALUE) {
        cancel(target, id);
        android.util.Log.w(
            "webview_all",
            "Android WebView cannot represent a resource length above 2147483647 bytes. Use a"
                + " stream without contentLength for sequential reads.");
        return empty(501);
      }
      // A null body avoids Chromium adding a synthetic Content-Length: 0 to
      // HEAD responses. For real bodies it computes a length from available()
      // and appends our response headers afterwards, so do not add it twice.
      InputStream stream =
          emptyBody
              ? null
              : new ResourceInputStream(
                  target, id, expectedGeneration, representationLength, length, rangeOffset);
      if (!emptyBody && representationLength >= 0 && representationLength <= Integer.MAX_VALUE) {
        headers.remove("content-length");
      }
      if (emptyBody) cancel(target, id);
      String encoding = mimeType.startsWith("text/") || mimeType.contains("json") ? "utf-8" : null;
      String contentType = headers.get("content-type");
      if (contentType != null) {
        Matcher charset =
            Pattern.compile("(?:^|;)\\s*charset\\s*=\\s*\"?([^;\"\\s]+)", Pattern.CASE_INSENSITIVE)
                .matcher(contentType);
        if (charset.find()) encoding = charset.group(1);
      }
      if (!emptyBody) headers.remove("content-type");
      return new WebResourceResponse(mimeType, encoding, status, "Resource", headers, stream);
    } catch (Exception exception) {
      cancel(target, id);
      android.util.Log.w("webview_all", "Application resource request failed.", exception);
      return empty(500);
    }
  }

  private static WebResourceResponse empty(int status) {
    Map<String, String> headers = new HashMap<>();
    headers.put("Content-Length", "0");
    headers.put("Cache-Control", "no-store");
    return new WebResourceResponse("text/plain", "utf-8", status, "Resource", headers, null);
  }

  private static boolean hasHeader(Map<String, String> headers, String name) {
    if (headers == null) return false;
    for (String key : headers.keySet()) if (name.equalsIgnoreCase(key)) return true;
    return false;
  }

  private Object invoke(MethodChannel target, String method, Object arguments) throws IOException {
    if (Looper.myLooper() == Looper.getMainLooper()) {
      throw new IOException("A resource read must not block the platform thread.");
    }
    CountDownLatch latch = new CountDownLatch(1);
    AtomicReference<Object> value = new AtomicReference<>();
    AtomicReference<String> error = new AtomicReference<>();
    main.post(
        () ->
            target.invokeMethod(
                method,
                arguments,
                new MethodChannel.Result() {
                  @Override
                  public void success(Object result) {
                    value.set(result);
                    latch.countDown();
                  }

                  @Override
                  public void error(String code, String message, Object details) {
                    error.set(code);
                    latch.countDown();
                  }

                  @Override
                  public void notImplemented() {
                    error.set("not_implemented");
                    latch.countDown();
                  }
                }));
    try {
      if (!latch.await(30, TimeUnit.SECONDS)) throw new IOException("Resource callback timed out.");
    } catch (InterruptedException exception) {
      Thread.currentThread().interrupt();
      throw new IOException(exception);
    }
    if (error.get() != null) throw new IOException(error.get());
    return value.get();
  }

  private void cancel(MethodChannel target, String id) {
    if (target != null)
      main.post(() -> target.invokeMethod("cancel", Collections.singletonMap("id", id)));
  }

  void close() {
    enabled = false;
    generation++;
    final MethodChannel target = channel;
    channel = null;
    if (target != null) main.post(() -> target.invokeMethod("closed", null));
  }

  private final class ResourceInputStream extends InputStream {
    private final MethodChannel target;
    private final String id;
    private final int expectedGeneration;
    private byte[] chunk;
    private int offset;
    private volatile boolean closed;
    private final long representationLength;
    private long remaining;
    private long rangeOffset;
    private boolean responseStarted;

    ResourceInputStream(
        MethodChannel target,
        String id,
        int expectedGeneration,
        long representationLength,
        long length,
        long rangeOffset) {
      this.target = target;
      this.id = id;
      this.expectedGeneration = expectedGeneration;
      this.representationLength = representationLength;
      this.remaining = length;
      this.rangeOffset = rangeOffset;
    }

    @Override
    public int available() {
      if (closed) return 0;
      // Chromium queries the full representation length before applying Range.
      // Metadata queries must remain stable until it seeks or starts reading.
      if (!responseStarted) {
        return representationLength >= 0 && representationLength <= Integer.MAX_VALUE
            ? (int) representationLength
            : 0;
      }
      return remaining < 0 ? 0 : (int) Math.min(remaining, Integer.MAX_VALUE);
    }

    @Override
    public long skip(long count) throws IOException {
      if (closed) return 0;
      // Chromium seeks to the original Range start before reading. Dart has
      // already selected that range; acknowledge the seek without consuming
      // those bytes a second time.
      if (rangeOffset > 0 && count > 0) {
        long skipped = Math.min(count, rangeOffset);
        rangeOffset -= skipped;
        if (rangeOffset == 0) responseStarted = true;
        return skipped;
      }
      return super.skip(count);
    }

    @Override
    public int read() throws IOException {
      byte[] value = new byte[1];
      return read(value, 0, 1) == -1 ? -1 : value[0] & 0xff;
    }

    @Override
    public int read(byte[] buffer, int start, int count) throws IOException {
      if (start < 0 || count < 0 || start > buffer.length - count)
        throw new IndexOutOfBoundsException();
      if (count == 0) return 0;
      if (closed) return -1;
      responseStarted = true;
      if (remaining == 0) {
        close();
        return -1;
      }
      if (!enabled || generation != expectedGeneration) {
        close();
        throw new IOException("The resource handler was removed.");
      }
      try {
        // Keep a local reference because close() can run on another thread.
        byte[] payload = chunk;
        if (payload == null || offset == payload.length) {
          Map<String, Object> args = new HashMap<>();
          args.put("id", id);
          args.put("length", Math.min(count, 65536));
          Object value = invoke(target, "read", args);
          if (value == null) {
            close();
            return -1;
          }
          if (!(value instanceof byte[]) || ((byte[]) value).length == 0) {
            throw new IOException("Invalid resource chunk.");
          }
          payload = (byte[]) value;
          chunk = payload;
          offset = 0;
        }
        if (closed) return -1;
        int length = Math.min(count, payload.length - offset);
        System.arraycopy(payload, offset, buffer, start, length);
        offset += length;
        if (remaining >= 0) remaining -= length;
        return length;
      } catch (IOException exception) {
        close();
        throw exception;
      }
    }

    @Override
    public void close() {
      if (closed) return;
      closed = true;
      chunk = null;
      cancel(target, id);
    }
  }
}

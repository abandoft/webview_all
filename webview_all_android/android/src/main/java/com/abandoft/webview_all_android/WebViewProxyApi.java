// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import android.annotation.SuppressLint;
import android.content.Context;
import android.hardware.display.DisplayManager;
import android.os.Build;
import android.view.MotionEvent;
import android.view.View;
import android.view.ViewParent;
import android.webkit.DownloadListener;
import android.webkit.WebChromeClient;
import android.webkit.WebSettings;
import android.webkit.WebView;
import android.webkit.WebViewClient;
import androidx.annotation.NonNull;
import androidx.annotation.Nullable;
import androidx.webkit.ScriptHandler;
import androidx.webkit.WebMessageCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import io.flutter.embedding.android.FlutterView;
import io.flutter.plugin.platform.PlatformView;
import java.util.Collections;
import java.util.HashMap;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.UUID;
import java.util.WeakHashMap;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * Host api implementation for {@link WebView}.
 *
 * <p>Handles creating {@link WebView}s that intercommunicate with a paired Dart object.
 */
public class WebViewProxyApi extends PigeonApiWebView {
  private final Map<WebView, Map<String, DocumentStartScript>> documentStartScripts =
      new WeakHashMap<>();
  private final Map<WebView, Map<String, JavaScriptChannelRegistration>> javaScriptChannels =
      new WeakHashMap<>();

  private static final class DocumentStartScript {
    final String source;
    ScriptHandler handler;

    DocumentStartScript(String source, ScriptHandler handler) {
      this.source = source;
      this.handler = handler;
    }
  }

  private static final class JavaScriptChannelRegistration {
    @Nullable final String listenerName;
    @Nullable final ScriptHandler wrapperScript;

    JavaScriptChannelRegistration(
        @Nullable String listenerName, @Nullable ScriptHandler wrapperScript) {
      this.listenerName = listenerName;
      this.wrapperScript = wrapperScript;
    }

    void remove(WebView webView, String publicName) {
      if (wrapperScript != null) {
        wrapperScript.remove();
      }
      if (listenerName != null) {
        WebViewCompat.removeWebMessageListener(webView, listenerName);
      } else {
        webView.removeJavascriptInterface(publicName);
      }
    }
  }

  /** Implementation of {@link WebView} that can be used as a Flutter {@link PlatformView}s. */
  @SuppressLint("ViewConstructor")
  public static class WebViewPlatformView extends WebView implements PlatformView {
    private final WebViewProxyApi api;

    private boolean destroyed;
    boolean limitedIncognito;

    private WebViewClient currentWebViewClient;

    private WebChromeClientProxyApi.SecureWebChromeClient currentWebChromeClient;

    WebViewPlatformView(@NonNull WebViewProxyApi api) {
      super(api.getPigeonRegistrar().getContext());
      this.api = api;
      currentWebViewClient = new WebViewClient();
      currentWebChromeClient = new WebChromeClientProxyApi.SecureWebChromeClient();

      setWebViewClient(currentWebViewClient);
      setWebChromeClient(currentWebChromeClient);
    }

    @Nullable
    @Override
    public View getView() {
      return this;
    }

    @Override
    public boolean onTouchEvent(@NonNull MotionEvent event) {
      // Canvas apps can consume the DOM touch event before Chromium requests native focus.
      // Acquire it before dispatch so their programmatically focused inputs can reach the IME.
      if (event.getActionMasked() == MotionEvent.ACTION_DOWN && !hasFocus()) {
        requestFocus();
      }
      return super.onTouchEvent(event);
    }

    @Override
    public void dispose() {}

    @Override
    public void destroy() {
      if (destroyed) {
        return;
      }
      destroyed = true;
      api.removeAllDocumentStartJavaScripts(this);
      api.removeAllJavaScriptChannels(this);
      try {
        if (limitedIncognito) {
          clearHistory();
          clearFormData();
        }
      } finally {
        super.destroy();
      }
    }

    // TODO(bparrishMines): This should be removed once https://github.com/flutter/engine/pull/40771
    // makes it to stable.
    // Temporary fix for https://github.com/flutter/flutter/issues/92165. The FlutterView is setting
    // setImportantForAutofill(IMPORTANT_FOR_AUTOFILL_YES_EXCLUDE_DESCENDANTS) which prevents this
    // view from automatically being traversed for autofill.
    @Override
    protected void onAttachedToWindow() {
      super.onAttachedToWindow();
      if (api.getPigeonRegistrar().sdkIsAtLeast(Build.VERSION_CODES.O)) {
        final FlutterView flutterView = tryFindFlutterView();
        if (flutterView != null) {
          flutterView.setImportantForAutofill(IMPORTANT_FOR_AUTOFILL_YES);
        }
      }
    }

    // Attempt to traverse the parents of this view until a FlutterView is found.
    private FlutterView tryFindFlutterView() {
      ViewParent currentView = this;

      while (currentView.getParent() != null) {
        currentView = currentView.getParent();
        if (currentView instanceof FlutterView) {
          return (FlutterView) currentView;
        }
      }

      return null;
    }

    @Override
    public void setWebViewClient(@NonNull WebViewClient webViewClient) {
      super.setWebViewClient(webViewClient);
      currentWebViewClient = webViewClient;
      currentWebChromeClient.setWebViewClient(webViewClient);
    }

    @Override
    public void setWebChromeClient(@Nullable WebChromeClient client) {
      super.setWebChromeClient(client);
      if (!(client instanceof WebChromeClientProxyApi.SecureWebChromeClient)) {
        throw new AssertionError("Client must be a SecureWebChromeClient.");
      }
      currentWebChromeClient = (WebChromeClientProxyApi.SecureWebChromeClient) client;
      currentWebChromeClient.setWebViewClient(currentWebViewClient);
    }

    // When running unit tests, the parent `WebView` class is replaced by a stub that returns null
    // for every method. This is overridden so that this returns the current WebChromeClient during
    // unit tests. This should only remain overridden as long as `setWebChromeClient` is overridden.
    @Nullable
    @Override
    public WebChromeClient getWebChromeClient() {
      return currentWebChromeClient;
    }

    @Override
    protected void onScrollChanged(int left, int top, int oldLeft, int oldTop) {
      super.onScrollChanged(left, top, oldLeft, oldTop);
      api.getPigeonRegistrar()
          .runOnMainThread(
              () ->
                  api.onScrollChanged(
                      this, (long) left, (long) top, (long) oldLeft, (long) oldTop, reply -> null));
    }
  }

  public WebViewProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public WebView pigeon_defaultConstructor() {
    DisplayListenerProxy displayListenerProxy = new DisplayListenerProxy();
    DisplayManager displayManager =
        (DisplayManager)
            getPigeonRegistrar().getContext().getSystemService(Context.DISPLAY_SERVICE);
    displayListenerProxy.onPreWebViewInitialization(displayManager);

    final WebView webView = new WebViewPlatformView(this);
    displayListenerProxy.onPostWebViewInitialization(displayManager);

    return webView;
  }

  @NonNull
  @Override
  public WebSettings settings(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getSettings();
  }

  @Override
  public void loadData(
      @NonNull WebView pigeon_instance,
      @NonNull String data,
      @Nullable String mimeType,
      @Nullable String encoding) {
    pigeon_instance.loadData(data, mimeType, encoding);
  }

  @Override
  public void loadDataWithBaseUrl(
      @NonNull WebView pigeon_instance,
      @Nullable String baseUrl,
      @NonNull String data,
      @Nullable String mimeType,
      @Nullable String encoding,
      @Nullable String historyUrl) {
    pigeon_instance.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl);
  }

  @Override
  public void loadUrl(
      @NonNull WebView pigeon_instance, @NonNull String url, @NonNull Map<String, String> headers) {
    pigeon_instance.loadUrl(url, headers);
  }

  @Override
  public void postUrl(@NonNull WebView pigeon_instance, @NonNull String url, @NonNull byte[] data) {
    pigeon_instance.postUrl(url, data);
  }

  @Nullable
  @Override
  public String getUrl(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getUrl();
  }

  @Override
  public boolean canGoBack(@NonNull WebView pigeon_instance) {
    return pigeon_instance.canGoBack();
  }

  @Override
  public boolean canGoForward(@NonNull WebView pigeon_instance) {
    return pigeon_instance.canGoForward();
  }

  @Override
  public void goBack(@NonNull WebView pigeon_instance) {
    pigeon_instance.goBack();
  }

  @Override
  public void goForward(@NonNull WebView pigeon_instance) {
    pigeon_instance.goForward();
  }

  @Override
  public void reload(@NonNull WebView pigeon_instance) {
    pigeon_instance.reload();
  }

  @Override
  public void clearCache(@NonNull WebView pigeon_instance, boolean includeDiskFiles) {
    pigeon_instance.clearCache(includeDiskFiles);
  }

  @Override
  public void evaluateJavascript(
      @NonNull WebView pigeon_instance,
      @NonNull String javascriptString,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    pigeon_instance.evaluateJavascript(
        javascriptString, result -> ResultCompat.success(result, callback));
  }

  @Override
  public boolean isDocumentStartJavaScriptSupported(@NonNull WebView pigeon_instance) {
    return WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT);
  }

  @Override
  public void addDocumentStartJavaScript(
      @NonNull WebView pigeon_instance, @NonNull String identifier, @NonNull String source) {
    if (!isDocumentStartJavaScriptSupported(pigeon_instance)) {
      throw new UnsupportedOperationException(
          "The installed Android System WebView does not support document-start scripts.");
    }

    final ScriptHandler handler =
        WebViewCompat.addDocumentStartJavaScript(
            pigeon_instance, source, Collections.singleton("*"));
    final Map<String, DocumentStartScript> scripts =
        documentStartScripts.computeIfAbsent(pigeon_instance, ignored -> new LinkedHashMap<>());
    final DocumentStartScript previous = scripts.remove(identifier);
    if (previous != null) {
      previous.handler.remove();
    }
    scripts.put(identifier, new DocumentStartScript(source, handler));
  }

  @Override
  public void removeDocumentStartJavaScript(
      @NonNull WebView pigeon_instance, @NonNull String identifier) {
    final Map<String, DocumentStartScript> scripts = documentStartScripts.get(pigeon_instance);
    if (scripts == null) {
      return;
    }
    final DocumentStartScript script = scripts.remove(identifier);
    if (script != null) {
      script.handler.remove();
    }
    if (scripts.isEmpty()) {
      documentStartScripts.remove(pigeon_instance);
    }
  }

  @Override
  public void removeAllDocumentStartJavaScripts(@NonNull WebView pigeon_instance) {
    final Map<String, DocumentStartScript> scripts = documentStartScripts.remove(pigeon_instance);
    if (scripts == null) {
      return;
    }
    for (DocumentStartScript script : scripts.values()) {
      script.handler.remove();
    }
  }

  // AndroidX runs document-start scripts in registration order. Move user scripts after a newly
  // installed channel wrapper so they can post messages even when registered before the channel.
  private void moveDocumentStartScriptsAfterChannelWrappers(@NonNull WebView webView) {
    final Map<String, DocumentStartScript> scripts = documentStartScripts.get(webView);
    if (scripts == null) {
      return;
    }
    final Map<DocumentStartScript, ScriptHandler> replacements = new LinkedHashMap<>();
    try {
      for (DocumentStartScript script : scripts.values()) {
        replacements.put(
            script,
            WebViewCompat.addDocumentStartJavaScript(
                webView, script.source, Collections.singleton("*")));
      }
    } catch (RuntimeException exception) {
      for (ScriptHandler handler : replacements.values()) {
        handler.remove();
      }
      throw exception;
    }
    for (Map.Entry<DocumentStartScript, ScriptHandler> replacement : replacements.entrySet()) {
      replacement.getKey().handler.remove();
      replacement.getKey().handler = replacement.getValue();
    }
  }

  @Nullable
  @Override
  public String getTitle(@NonNull WebView pigeon_instance) {
    return pigeon_instance.getTitle();
  }

  @Override
  public void setWebContentsDebuggingEnabled(boolean enabled) {
    WebView.setWebContentsDebuggingEnabled(enabled);
  }

  @Override
  public void setWebViewClient(@NonNull WebView pigeon_instance, @Nullable WebViewClient client) {
    pigeon_instance.setWebViewClient(client);
  }

  @SuppressLint("JavascriptInterface")
  @Override
  public void addJavaScriptChannel(
      @NonNull WebView pigeon_instance, @NonNull JavaScriptChannel channel) {
    final String name = channel.javaScriptChannelName;
    final Map<String, JavaScriptChannelRegistration> channels =
        javaScriptChannels.computeIfAbsent(pigeon_instance, ignored -> new HashMap<>());
    for (JavaScriptChannelRegistration registration : channels.values()) {
      if (name.equals(registration.listenerName)) {
        throw new IllegalArgumentException(
            "The JavaScript channel name is already in use internally.");
      }
    }
    final boolean hasSenderMetadata =
        WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
            && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT);
    final JavaScriptChannelRegistration previous = channels.remove(name);
    if (previous != null) {
      previous.remove(pigeon_instance, name);
    }
    if (hasSenderMetadata) {
      // A literal window property (accessed using brackets), rather than an app channel identifier.
      // Keep this name unique even for apps that use non-identifier channel names themselves.
      String listenerName;
      do {
        listenerName = "webview_all.internal." + UUID.randomUUID();
      } while (name.equals(listenerName) || isJavaScriptChannelNameInUse(channels, listenerName));
      final String privateName = listenerName;
      WebViewCompat.addWebMessageListener(
          pigeon_instance,
          privateName,
          Collections.singleton("*"),
          (view, message, sourceOrigin, isMainFrame, replyProxy) -> {
            // Public calls have already been converted to strings by the wrapper. Also handle
            // direct calls to the internal object without letting an ArrayBuffer throw in getData.
            final String text =
                message.getType() == WebMessageCompat.TYPE_ARRAY_BUFFER
                    ? "[object ArrayBuffer]"
                    : message.getData();
            channel.postMessageWithSenderMetadata(
                text == null ? "null" : text, sourceOrigin.toString(), isMainFrame);
          });
      ScriptHandler wrapper = null;
      try {
        // AndroidX guarantees listener objects are injected before document-start scripts.
        wrapper =
            WebViewCompat.addDocumentStartJavaScript(
                pigeon_instance,
                javaScriptChannelWrapper(name, privateName),
                Collections.singleton("*"));
        moveDocumentStartScriptsAfterChannelWrappers(pigeon_instance);
        channels.put(name, new JavaScriptChannelRegistration(privateName, wrapper));
      } catch (RuntimeException exception) {
        if (wrapper != null) {
          wrapper.remove();
        }
        WebViewCompat.removeWebMessageListener(pigeon_instance, privateName);
        throw exception;
      }
    } else {
      pigeon_instance.addJavascriptInterface(channel, name);
      channels.put(name, new JavaScriptChannelRegistration(null, null));
    }
  }

  private static boolean isJavaScriptChannelNameInUse(
      Map<String, JavaScriptChannelRegistration> channels, String name) {
    if (channels.containsKey(name)) {
      return true;
    }
    for (JavaScriptChannelRegistration registration : channels.values()) {
      if (name.equals(registration.listenerName)) {
        return true;
      }
    }
    return false;
  }

  static String javaScriptChannelWrapper(String publicName, String privateName) {
    // Channel names can shadow window.String or window.Object. Resolve intrinsics through literals
    // so installing another channel never depends on those mutable global bindings.
    return "(function(){var bridge=window["
        + quoteJavaScriptString(privateName)
        + "],string=''.constructor;({}).constructor.defineProperty(window,"
        + quoteJavaScriptString(publicName)
        + ",{configurable:true,enumerable:true,writable:true,value:{postMessage:function(value){"
        + "bridge.postMessage(string(value));}}});})();";
  }

  private static String quoteJavaScriptString(String value) {
    final StringBuilder result = new StringBuilder("\"");
    final String hex = "0123456789abcdef";
    for (int index = 0; index < value.length(); index++) {
      final char character = value.charAt(index);
      if (character == '"' || character == '\\') {
        result.append('\\').append(character);
      } else if (character < 0x20 || character == 0x2028 || character == 0x2029) {
        result
            .append("\\u")
            .append(hex.charAt((character >> 12) & 0xf))
            .append(hex.charAt((character >> 8) & 0xf))
            .append(hex.charAt((character >> 4) & 0xf))
            .append(hex.charAt(character & 0xf));
      } else {
        result.append(character);
      }
    }
    return result.append('"').toString();
  }

  @Override
  public void removeJavaScriptChannel(@NonNull WebView pigeon_instance, @NonNull String channel) {
    final Map<String, JavaScriptChannelRegistration> channels =
        javaScriptChannels.get(pigeon_instance);
    final JavaScriptChannelRegistration registration =
        channels == null ? null : channels.remove(channel);
    if (registration != null) {
      registration.remove(pigeon_instance, channel);
    } else {
      pigeon_instance.removeJavascriptInterface(channel);
    }
    if (channels != null && channels.isEmpty()) {
      javaScriptChannels.remove(pigeon_instance);
    }
  }

  void removeAllJavaScriptChannels(@NonNull WebView webView) {
    final Map<String, JavaScriptChannelRegistration> channels = javaScriptChannels.remove(webView);
    if (channels == null) {
      return;
    }
    for (Map.Entry<String, JavaScriptChannelRegistration> channel : channels.entrySet()) {
      channel.getValue().remove(webView, channel.getKey());
    }
  }

  @Override
  public void setDownloadListener(
      @NonNull WebView pigeon_instance, @Nullable DownloadListener listener) {
    pigeon_instance.setDownloadListener(listener);
  }

  @Override
  public void setWebChromeClient(
      @NonNull WebView pigeon_instance,
      @Nullable WebChromeClientProxyApi.WebChromeClientImpl client) {
    pigeon_instance.setWebChromeClient(client);
  }

  @Override
  public void setBackgroundColor(@NonNull WebView pigeon_instance, long color) {
    pigeon_instance.setBackgroundColor((int) color);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @SuppressWarnings("deprecation")
  @Override
  public void enableLimitedIncognito(@NonNull WebView pigeon_instance) {
    WebSettings settings = pigeon_instance.getSettings();
    settings.setCacheMode(WebSettings.LOAD_NO_CACHE);
    settings.setSavePassword(false);
    settings.setSaveFormData(false);
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
      pigeon_instance.setImportantForAutofill(View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS);
    }
    pigeon_instance.clearHistory();
    pigeon_instance.clearFormData();
    if (pigeon_instance instanceof WebViewPlatformView) {
      ((WebViewPlatformView) pigeon_instance).limitedIncognito = true;
    }
  }

  @Override
  public void destroy(@NonNull WebView pigeon_instance) {
    pigeon_instance.destroy();
  }
}

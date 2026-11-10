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
import androidx.webkit.JavaScriptExecutionWorld;
import androidx.webkit.JavaScriptReplyProxy;
import androidx.webkit.JavaScriptExecutionException;
import androidx.webkit.WebViewOutcomeReceiver;
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
import java.util.ArrayList;
import java.util.List;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * Host api implementation for {@link WebView}.
 *
 * <p>Handles creating {@link WebView}s that intercommunicate with a paired Dart object.
 */
public class WebViewProxyApi extends PigeonApiWebView {
  private static final Map<WebView, FindState> findStates = new WeakHashMap<>();

  private static final class FindState {
    String text;
    int count;
    boolean initialBackward;
    Function1<? super Result<? extends Map<String, ? extends Object>>, Unit> pending;
  }

  static void resetFindState(WebView view) {
    FindState state = findStates.remove(view);
    view.setFindListener(null);
    if (state != null && state.pending != null) {
      ResultCompat.success(null, state.pending);
      state.pending = null;
    }
  }

  @Override
  public void stopLoading(@NonNull WebView view) {
    view.stopLoading();
  }

  @NonNull
  @Override
  public Map<String, Object> getNavigationHistory(@NonNull WebView view) {
    android.webkit.WebBackForwardList history = view.copyBackForwardList();
    List<Object> items = new ArrayList<>();
    for (int index = 0; index < history.getSize(); index++) {
      android.webkit.WebHistoryItem item = history.getItemAtIndex(index);
      Map<String, Object> data = new HashMap<>();
      data.put("url", item.getUrl());
      data.put("title", item.getTitle());
      data.put("originalUrl", item.getOriginalUrl());
      items.add(data);
    }
    Map<String, Object> result = new HashMap<>();
    result.put("items", items);
    result.put("currentIndex", (long) history.getCurrentIndex());
    return result;
  }

  @Override
  public boolean goToHistoryIndex(@NonNull WebView view, long index) {
    android.webkit.WebBackForwardList history = view.copyBackForwardList();
    if (index < 0 || index >= history.getSize())
      return false;
    view.goBackOrForward((int) index - history.getCurrentIndex());
    return true;
  }

  @Override
  public void findText(@NonNull WebView view, @NonNull String text, boolean forward,
      @NonNull Function1<? super Result<? extends Map<String, ? extends Object>>, Unit> callback) {
    FindState state = findStates.get(view);
    if (state == null) {
      state = new FindState();
      findStates.put(view, state);
      final FindState registered = state;
      final java.lang.ref.WeakReference<WebView> weakView = new java.lang.ref.WeakReference<>(view);
      view.setFindListener((active, count, done) -> {
        if (!done || registered.pending == null)
          return;
        registered.count = count;
        final WebView target = weakView.get();
        if (registered.initialBackward && count > 1 && target != null) {
          registered.initialBackward = false;
          target.findNext(false);
          return;
        }
        Map<String, Object> result = new HashMap<>();
        result.put("matchFound", count > 0);
        result.put("matchCount", (long) count);
        result.put("activeMatchIndex", count > 0 ? (long) active : null);
        Function1<? super Result<? extends Map<String, ? extends Object>>, Unit> pending =
            registered.pending;
        registered.pending = null;
        ResultCompat.success(result, pending);
      });
    }
    if (state.pending != null)
      ResultCompat.success(null, state.pending);
    state.pending = callback;
    if (text.equals(state.text) && state.count > 0) {
      state.initialBackward = false;
      view.findNext(forward);
    } else {
      state.text = text;
      state.initialBackward = !forward;
      view.findAllAsync(text);
    }
  }

  @Override
  public void clearFindMatches(@NonNull WebView view) {
    resetFindState(view);
    view.clearMatches();
  }

  private final Map<WebView, Map<String, DocumentStartScript>> documentStartScripts =
      new WeakHashMap<>();
  private final Map<WebView, Map<String, JavaScriptChannelRegistration>> javaScriptChannels =
      new WeakHashMap<>();

  private static final class WorldRegistration {
    final String listener;
    final ScriptHandler bootstrap;
    @Nullable JavaScriptReplyProxy frame;
    WorldRegistration(String listener, ScriptHandler bootstrap) {
      this.listener = listener;
      this.bootstrap = bootstrap;
    }
  }
  private final Map<WebView, Map<String, WorldRegistration>> isolatedWorlds = new WeakHashMap<>();

  private static final class DocumentStartScript {
    final String source;
    ScriptHandler handler;
    boolean documentEnd;
    @Nullable String worldName;

    DocumentStartScript(String source, ScriptHandler handler) {
      this.source = source;
      this.handler = handler;
    }
  }

  private static final class JavaScriptChannelRegistration {
    @Nullable final String listenerName;
    @Nullable final ScriptHandler wrapperScript;
    @Nullable String worldName;

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
        if (worldName == null)
          WebViewCompat.removeWebMessageListener(webView, listenerName);
        else
          WebViewCompat.removeWebMessageListener(webView,
              WebViewCompat.getExecutionWorld(webView, "webview_all." + worldName), listenerName);
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
    volatile ResourceBridge resourceBridge;
    volatile ResourceBridge networkBridge, schemeBridge;
    volatile List<NetworkControl.Rule> contentRules = Collections.emptyList();
    List<String> declaredCustomSchemes = Collections.emptyList();
    boolean limitedIncognito;

    private WebViewClient currentWebViewClient;

    private WebChromeClientProxyApi.SecureWebChromeClient currentWebChromeClient;

    WebViewPlatformView(@NonNull WebViewProxyApi api) {
      super(api.getPigeonRegistrar().getContext());
      this.api = api;
      currentWebViewClient =
          new WebViewClient() {
            @Override
            @androidx.annotation.RequiresApi(26)
            public boolean onRenderProcessGone(WebView view, android.webkit.RenderProcessGoneDetail detail) {
              return BrowserOperations.rendererGone(view, detail);
            }
            @Override
            public android.webkit.WebResourceResponse shouldInterceptRequest(
                WebView view, android.webkit.WebResourceRequest request) {
              return ResourceBridge.intercept(view, request);
            }
          };
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
      BrowserProfiles.unregister(this);
      try {
        BrowserOperations.cancel(this);
        if (resourceBridge != null) resourceBridge.close();
        if (networkBridge != null) networkBridge.close();
        if (schemeBridge != null) schemeBridge.close();
        api.removeAllDocumentStartJavaScripts(this);
        api.removeAllJavaScriptChannels(this);
        if (limitedIncognito) { clearHistory(); clearFormData(); }
      } catch (RuntimeException error) {
        android.util.Log.w("webview_all", "WebView cleanup failed: " + error);
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
  public WebView pigeon_defaultConstructor(@Nullable String profileName, @Nullable List<String> customSchemes) {
    DisplayListenerProxy displayListenerProxy = new DisplayListenerProxy();
    DisplayManager displayManager =
        (DisplayManager)
            getPigeonRegistrar().getContext().getSystemService(Context.DISPLAY_SERVICE);
    displayListenerProxy.onPreWebViewInitialization(displayManager);

    final WebView webView = new WebViewPlatformView(this);
    if (customSchemes != null) {
      boolean valid = customSchemes.size() <= 16;
      for (String scheme : customSchemes) valid &= scheme.matches("[a-z][a-z0-9+.-]{0,31}") &&
          !java.util.Arrays.asList("http", "https", "file", "data", "about", "javascript", "blob", "ws", "wss", "content", "intent", "webview-all-resource").contains(scheme);
      if (!valid) {
        webView.destroy(); throw new IllegalArgumentException("Invalid or engine-owned custom scheme.");
      }
      ((WebViewPlatformView) webView).declaredCustomSchemes = Collections.unmodifiableList(new ArrayList<>(customSchemes));
    }
    if (profileName != null) {
      if (!profileName.matches("[A-Za-z0-9_-]{1,64}") ||
          !WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
        webView.destroy();
        throw new UnsupportedOperationException("Named profiles require MULTI_PROFILE support and a 1-64 character ASCII name.");
      }
      try {
        WebViewCompat.setProfile(webView, "webview_all_" + profileName);
        BrowserProfiles.register(webView, profileName);
      } catch (RuntimeException error) {
        webView.destroy(); throw error;
      }
    }
    displayListenerProxy.onPostWebViewInitialization(displayManager);

    return webView;
  }
  public WebView pigeon_defaultConstructor() { return pigeon_defaultConstructor(null, null); }

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
    BrowserOperations.markNavigation(pigeon_instance);
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
    BrowserOperations.markNavigation(pigeon_instance);
    pigeon_instance.loadDataWithBaseURL(baseUrl, data, mimeType, encoding, historyUrl);
  }

  @Override
  public void loadUrl(
      @NonNull WebView pigeon_instance, @NonNull String url, @NonNull Map<String, String> headers) {
    BrowserOperations.markNavigation(pigeon_instance);
    pigeon_instance.loadUrl(url, headers);
  }

  @Override
  public void postUrl(@NonNull WebView pigeon_instance, @NonNull String url, @NonNull byte[] data) {
    BrowserOperations.markNavigation(pigeon_instance);
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
    BrowserOperations.markNavigation(pigeon_instance);
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
  public boolean isJavaScriptWorldSupported(@NonNull WebView view) {
    return WebViewFeature.isFeatureSupported(WebViewFeature.JS_INJECTION_IN_FRAME_AND_WORLD);
  }

  @Override
  public boolean isJavaScriptMessageMetadataSupported(@NonNull WebView view) {
    return WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)
        && WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT);
  }

  private WorldRegistration ensureWorld(WebView view, String name) {
    if (!isJavaScriptWorldSupported(view))
      throw new UnsupportedOperationException("Isolated JavaScript worlds are unavailable.");
    Map<String, WorldRegistration> worlds =
        isolatedWorlds.computeIfAbsent(view, ignored -> new HashMap<>());
    WorldRegistration existing = worlds.get(name);
    if (existing != null)
      return existing;
    String listener = "webview_all.world." + UUID.randomUUID();
    JavaScriptExecutionWorld world = WebViewCompat.getExecutionWorld(view, "webview_all." + name);
    WebViewCompat.addWebMessageListener(view, listener, Collections.singleton("*"), world,
        (target, message, origin, mainFrame, reply) -> {
          WorldRegistration registration = worlds.get(name);
          if (mainFrame && registration != null)
            registration.frame = reply;
        });
    ScriptHandler bootstrap;
    try {
      bootstrap = WebViewCompat.addJavaScriptOnEvent(view,
          "if (globalThis.top === globalThis) globalThis[" + quoteJavaScriptString(listener)
              + "].postMessage('ready');",
          WebViewCompat.INJECTION_EVENT_DOCUMENT_START, Collections.singleton("*"), world);
    } catch (RuntimeException error) {
      WebViewCompat.removeWebMessageListener(view, world, listener);
      throw error;
    }
    WorldRegistration registration = new WorldRegistration(listener, bootstrap);
    worlds.put(name, registration);
    return registration;
  }

  private ScriptHandler registerUserScript(
      WebView view, String source, boolean documentEnd, @Nullable String name) {
    if (isJavaScriptWorldSupported(view)) {
      if (name != null)
        ensureWorld(view, name);
      JavaScriptExecutionWorld world = WebViewCompat.getExecutionWorld(
          view, name == null ? JavaScriptExecutionWorld.PAGE_WORLD_NAME : "webview_all." + name);
      return WebViewCompat.addJavaScriptOnEvent(view, source,
          documentEnd ? WebViewCompat.INJECTION_EVENT_DOCUMENT_END
                      : WebViewCompat.INJECTION_EVENT_DOCUMENT_START,
          Collections.singleton("*"), world);
    }
    if (name != null || !isDocumentStartJavaScriptSupported(view))
      throw new UnsupportedOperationException(
          "The requested user-script capability is unavailable.");
    String script = documentEnd ? "document.addEventListener('DOMContentLoaded', function() {\n"
            + source + "\n}, {once: true});"
                                : source;
    return WebViewCompat.addDocumentStartJavaScript(view, script, Collections.singleton("*"));
  }

  @Override
  public void addUserJavaScript(@NonNull WebView view, @NonNull String identifier,
      @NonNull String source, boolean documentEnd, @Nullable String worldName) {
    ScriptHandler handler = registerUserScript(view, source, documentEnd, worldName);
    DocumentStartScript script = new DocumentStartScript(source, handler);
    script.documentEnd = documentEnd;
    script.worldName = worldName;
    DocumentStartScript previous =
        documentStartScripts.computeIfAbsent(view, ignored -> new LinkedHashMap<>())
            .put(identifier, script);
    if (previous != null)
      previous.handler.remove();
  }

  @Override
  public void evaluateJavaScriptInWorld(@NonNull WebView view, @NonNull String source,
      @NonNull String worldName, @NonNull Function1<? super Result<String>, Unit> callback) {
    WorldRegistration world = ensureWorld(view, worldName);
    if (world.frame == null) {
      ResultCompat.failure(new AndroidWebKitError("javascript-world-unavailable",
                               "Register the isolated world before loading a document and wait for "
                               + "the document to become ready.",
                               null),
          callback);
      return;
    }
    world.frame.executeJavaScript(
        source, new WebViewOutcomeReceiver<String, JavaScriptExecutionException>() {
          @Override
          public void onResult(@NonNull String result) {
            ResultCompat.success(result, callback);
          }
          @Override
          public void onError(@NonNull JavaScriptExecutionException error) {
            if (error.getErrorType() == JavaScriptExecutionException.ERROR_FRAME_DESTROYED) {
              ResultCompat.failure(new AndroidWebKitError("javascript-world-unavailable",
                                       "The original JavaScript document was destroyed.", null),
                  callback);
            } else
              ResultCompat.failure(error, callback);
          }
        });
  }

  @Override
  public void addJavaScriptChannelInWorld(
      @NonNull WebView view, @NonNull JavaScriptChannel channel, @NonNull String worldName) {
    WorldRegistration state = ensureWorld(view, worldName);
    JavaScriptExecutionWorld world =
        WebViewCompat.getExecutionWorld(view, "webview_all." + worldName);
    String listener = "webview_all.internal." + UUID.randomUUID();
    WebViewCompat.addWebMessageListener(view, listener, Collections.singleton("*"), world,
        (target, message, origin, mainFrame, reply) -> {
          if (mainFrame)
            state.frame = reply;
          String text = message.getType() == WebMessageCompat.TYPE_ARRAY_BUFFER
              ? "[object ArrayBuffer]"
              : message.getData();
          channel.postMessageWithSenderMetadata(
              text == null ? "null" : text, origin.toString(), mainFrame);
        });
    try {
      ScriptHandler wrapper = WebViewCompat.addJavaScriptOnEvent(view,
          javaScriptChannelWrapper(channel.javaScriptChannelName, listener),
          WebViewCompat.INJECTION_EVENT_DOCUMENT_START, Collections.singleton("*"), world);
      JavaScriptChannelRegistration registration =
          new JavaScriptChannelRegistration(listener, wrapper);
      registration.worldName = worldName;
      JavaScriptChannelRegistration previous =
          javaScriptChannels.computeIfAbsent(view, ignored -> new HashMap<>())
              .put(channel.javaScriptChannelName, registration);
      if (previous != null)
        previous.remove(view, channel.javaScriptChannelName);
      moveDocumentStartScriptsAfterChannelWrappers(view);
    } catch (RuntimeException error) {
      WebViewCompat.removeWebMessageListener(view, world, listener);
      throw error;
    }
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
        replacements.put(script,
            script.worldName == null && !script.documentEnd
                ? WebViewCompat.addDocumentStartJavaScript(
                      webView, script.source, Collections.singleton("*"))
                : registerUserScript(webView, script.source, script.documentEnd, script.worldName));
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
    Map<String, WorldRegistration> worlds = isolatedWorlds.remove(webView);
    if (worlds != null) {
      for (Map.Entry<String, WorldRegistration> entry : worlds.entrySet()) {
        entry.getValue().bootstrap.remove();
        WebViewCompat.removeWebMessageListener(webView,
            WebViewCompat.getExecutionWorld(webView, "webview_all." + entry.getKey()),
            entry.getValue().listener);
      }
    }
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
    resetFindState(pigeon_instance);
    pigeon_instance.destroy();
  }
}

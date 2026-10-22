// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNotEquals;
import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.times;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import android.net.Uri;
import android.webkit.WebView;
import androidx.webkit.JavaScriptReplyProxy;
import androidx.webkit.ScriptHandler;
import androidx.webkit.WebMessageCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

public class JavaScriptChannelSenderTest {
  private static void supportModernBridge(MockedStatic<WebViewFeature> features) {
    features
        .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
        .thenReturn(true);
    features
        .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
        .thenReturn(true);
  }

  private static JavaScriptChannel channel(String name) {
    return new JavaScriptChannel(name, mock(JavaScriptChannelProxyApi.class));
  }

  @Test
  public void nativeListenerReportsFrameAndOriginWithoutReadingThePayload() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final JavaScriptChannelProxyApi channelApi = mock(JavaScriptChannelProxyApi.class);
      when(channelApi.getPigeonRegistrar()).thenReturn(new TestProxyApiRegistrar());
      final JavaScriptChannel channel = new JavaScriptChannel("Bridge", channelApi);
      final ScriptHandler wrapper = mock(ScriptHandler.class);
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenReturn(wrapper);

      api.addJavaScriptChannel(view, channel);
      final ArgumentCaptor<String> privateName = ArgumentCaptor.forClass(String.class);
      final ArgumentCaptor<WebViewCompat.WebMessageListener> listener =
          ArgumentCaptor.forClass(WebViewCompat.WebMessageListener.class);
      compat.verify(
          () ->
              WebViewCompat.addWebMessageListener(
                  eq(view),
                  privateName.capture(),
                  eq(Collections.singleton("*")),
                  listener.capture()));
      assertTrue(privateName.getValue().startsWith("webview_all.internal."));
      final ArgumentCaptor<String> source = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () ->
              WebViewCompat.addDocumentStartJavaScript(
                  eq(view), source.capture(), eq(Collections.singleton("*"))));
      assertEquals(
          WebViewProxyApi.javaScriptChannelWrapper("Bridge", privateName.getValue()),
          source.getValue());
      verify(view, never()).addJavascriptInterface(any(), any());
      final Uri origin = mock(Uri.class);
      when(origin.toString()).thenReturn("https://sender.example:8443");
      final String payload = "{\"sourceOrigin\":\"https://forged.example\",\"isMainFrame\":true}";

      listener
          .getValue()
          .onPostMessage(
              view, new WebMessageCompat(payload), origin, false, mock(JavaScriptReplyProxy.class));

      verify(channelApi)
          .postMessage(
              eq(channel), eq(payload), eq("https://sender.example:8443"), eq(false), any());

      // The browser serializes opaque origins as "null"; retain that distinction
      // from the unknown sender metadata of the legacy bridge.
      when(origin.toString()).thenReturn("null");
      listener
          .getValue()
          .onPostMessage(
              view, new WebMessageCompat("opaque"), origin, true, mock(JavaScriptReplyProxy.class));
      verify(channelApi).postMessage(eq(channel), eq("opaque"), eq("null"), eq(true), any());

      // Page code can discover the internal object. A direct ArrayBuffer call must not throw
      // an IllegalStateException in WebMessageCompat.getData().
      listener
          .getValue()
          .onPostMessage(
              view,
              new WebMessageCompat(new byte[] {1, 2}),
              origin,
              true,
              mock(JavaScriptReplyProxy.class));
      verify(channelApi)
          .postMessage(eq(channel), eq("[object ArrayBuffer]"), eq("null"), eq(true), any());
    }
  }

  @Test
  public void eitherMissingFeatureKeepsTheLegacyChannelAvailable() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final JavaScriptChannel first = channel("First");
      final JavaScriptChannel second = channel("Second");
      features
          .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
          .thenReturn(true);
      api.addJavaScriptChannel(view, first);
      verify(view).addJavascriptInterface(first, "First");

      features
          .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
          .thenReturn(false);
      features
          .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT))
          .thenReturn(true);
      api.addJavaScriptChannel(view, second);
      verify(view).addJavascriptInterface(second, "Second");
      compat.verifyNoInteractions();
    }
  }

  @Test
  public void wrapperEscapesNamesAndConvertsAllPublicMessagesBeforePosting() {
    assertEquals(
        "(function(){var bridge=window[\"private.\\\"\\\\\\u0000\"],string=''.constructor;"
            + "({}).constructor.defineProperty(window,\"public.\\\"\\\\\\u000a\\u2028\\u2029\","
            + "{configurable:true,enumerable:true,writable:true,value:{postMessage:function(value){"
            + "bridge.postMessage(string(value));}}});})();",
        WebViewProxyApi.javaScriptChannelWrapper("public.\"\\\n\u2028\u2029", "private.\"\\\0"));
  }

  @Test
  public void builtinGlobalNamesUseIndependentNativeBindingsAndWrappers() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final List<ScriptHandler> wrappers = new ArrayList<>();
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenAnswer(
              invocation -> {
                final ScriptHandler wrapper = mock(ScriptHandler.class);
                wrappers.add(wrapper);
                return wrapper;
              });
      final List<String> publicNames = Arrays.asList("String", "Object", "Bridge");
      for (String publicName : publicNames) {
        api.addJavaScriptChannel(view, channel(publicName));
      }

      final ArgumentCaptor<String> privateNames = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addWebMessageListener(eq(view), privateNames.capture(), any(), any()),
          times(3));
      final ArgumentCaptor<String> sources = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addDocumentStartJavaScript(eq(view), sources.capture(), any()),
          times(3));
      assertEquals(3, new java.util.HashSet<>(privateNames.getAllValues()).size());
      for (int index = 0; index < publicNames.size(); index++) {
        assertEquals(
            WebViewProxyApi.javaScriptChannelWrapper(
                publicNames.get(index), privateNames.getAllValues().get(index)),
            sources.getAllValues().get(index));
        api.removeJavaScriptChannel(view, publicNames.get(index));
        final String privateName = privateNames.getAllValues().get(index);
        compat.verify(() -> WebViewCompat.removeWebMessageListener(view, privateName));
        verify(wrappers.get(index)).remove();
      }
      verify(view, never()).addJavascriptInterface(any(), any());
    }
  }

  @Test
  public void replacementAndRemovalUseTheBackendChosenAtRegistration() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final JavaScriptChannel first = channel("Bridge");
      final JavaScriptChannel second = channel("Bridge");
      final ScriptHandler firstWrapper = mock(ScriptHandler.class);
      final ScriptHandler secondWrapper = mock(ScriptHandler.class);
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenReturn(firstWrapper, secondWrapper);

      api.addJavaScriptChannel(view, first);
      api.addJavaScriptChannel(view, second);
      final ArgumentCaptor<String> names = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addWebMessageListener(eq(view), names.capture(), any(), any()),
          times(2));
      assertNotEquals(names.getAllValues().get(0), names.getAllValues().get(1));
      compat.verify(
          () -> WebViewCompat.removeWebMessageListener(view, names.getAllValues().get(0)));
      verify(firstWrapper).remove();
      features
          .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER))
          .thenReturn(false);
      api.removeJavaScriptChannel(view, "Bridge");
      compat.verify(
          () -> WebViewCompat.removeWebMessageListener(view, names.getAllValues().get(1)));
      verify(secondWrapper).remove();
      verify(view, never()).removeJavascriptInterface("Bridge");

      api.addJavaScriptChannel(view, first);
      verify(view).addJavascriptInterface(first, "Bridge");
      supportModernBridge(features);
      api.removeJavaScriptChannel(view, "Bridge");
      verify(view).removeJavascriptInterface("Bridge");
    }
  }

  @Test
  public void wrappersPrecedeExistingUserScriptsWithoutRemovingThem() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final List<String> sources = new ArrayList<>();
      final List<ScriptHandler> handlers = new ArrayList<>();
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenAnswer(
              invocation -> {
                sources.add(invocation.getArgument(1));
                final ScriptHandler handler = mock(ScriptHandler.class);
                handlers.add(handler);
                return handler;
              });
      api.addDocumentStartJavaScript(view, "first", "first();");
      api.addDocumentStartJavaScript(view, "second", "second();");
      api.addJavaScriptChannel(view, channel("Bridge"));

      assertEquals(5, sources.size());
      assertEquals(Arrays.asList("first();", "second();"), sources.subList(0, 2));
      assertTrue(sources.get(2).startsWith("(function(){var bridge=window["));
      assertEquals(Arrays.asList("first();", "second();"), sources.subList(3, 5));
      verify(handlers.get(0)).remove();
      verify(handlers.get(1)).remove();
      api.removeDocumentStartJavaScript(view, "first");
      verify(handlers.get(3)).remove();
      api.removeAllDocumentStartJavaScripts(view);
      verify(handlers.get(4)).remove();
      verify(handlers.get(2), never()).remove();
      api.removeJavaScriptChannel(view, "Bridge");
      verify(handlers.get(2)).remove();
    }
  }

  @Test
  public void registrationFailureKeepsOriginalUserScriptsAndCleansNewBridge() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      final List<ScriptHandler> handlers = new ArrayList<>();
      final AtomicInteger scriptCount = new AtomicInteger();
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenAnswer(
              invocation -> {
                if (scriptCount.incrementAndGet() == 5) {
                  throw new IllegalStateException("script registration failed");
                }
                final ScriptHandler handler = mock(ScriptHandler.class);
                handlers.add(handler);
                return handler;
              });
      api.addDocumentStartJavaScript(view, "first", "first();");
      api.addDocumentStartJavaScript(view, "second", "second();");

      assertThrows(
          IllegalStateException.class, () -> api.addJavaScriptChannel(view, channel("Bridge")));

      verify(handlers.get(0), never()).remove();
      verify(handlers.get(1), never()).remove();
      verify(handlers.get(2)).remove(); // wrapper
      verify(handlers.get(3)).remove(); // temporary replacement of first user script
      final ArgumentCaptor<String> name = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addWebMessageListener(eq(view), name.capture(), any(), any()));
      compat.verify(() -> WebViewCompat.removeWebMessageListener(view, name.getValue()));
      verify(view, never()).addJavascriptInterface(any(), any());
      api.removeAllDocumentStartJavaScripts(view);
      verify(handlers.get(0)).remove();
      verify(handlers.get(1)).remove();
    }
  }

  @Test
  public void publicNamesCannotOverwriteExistingPrivateBindings() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebView view = mock(WebView.class);
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenReturn(mock(ScriptHandler.class));
      api.addJavaScriptChannel(view, channel("Bridge"));
      final ArgumentCaptor<String> name = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addWebMessageListener(eq(view), name.capture(), any(), any()));
      assertThrows(
          IllegalArgumentException.class,
          () -> api.addJavaScriptChannel(view, channel(name.getValue())));
      compat.verify(() -> WebViewCompat.removeWebMessageListener(any(), any()), never());
    }
  }

  @Test
  public void destroyingTheViewRemovesModernListenersAndWrappersExactlyOnce() {
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      supportModernBridge(features);
      final WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      final WebViewProxyApi.WebViewPlatformView view = new WebViewProxyApi.WebViewPlatformView(api);
      final ScriptHandler wrapper = mock(ScriptHandler.class);
      compat
          .when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), any()))
          .thenReturn(wrapper);
      api.addJavaScriptChannel(view, channel("Bridge"));
      final ArgumentCaptor<String> name = ArgumentCaptor.forClass(String.class);
      compat.verify(
          () -> WebViewCompat.addWebMessageListener(eq(view), name.capture(), any(), any()));

      view.destroy();
      view.destroy();

      compat.verify(() -> WebViewCompat.removeWebMessageListener(view, name.getValue()));
      verify(wrapper).remove();
    }
  }
}

package com.abandoft.webview_all_android;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.ArgumentMatchers.anySet;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.times;

import android.net.Uri;
import android.webkit.WebView;
import androidx.webkit.JavaScriptExecutionException;
import androidx.webkit.JavaScriptExecutionWorld;
import androidx.webkit.JavaScriptReplyProxy;
import androidx.webkit.ScriptHandler;
import androidx.webkit.WebMessageCompat;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import androidx.webkit.WebViewOutcomeReceiver;
import java.util.concurrent.atomic.AtomicReference;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

public class JavaScriptWorldTest {
  @Test
  @SuppressWarnings({"rawtypes", "unchecked"})
  public void isolatedEvaluationUsesOnlyTheMainDocumentReplyProxy() {
    WebView view = mock(WebView.class);
    JavaScriptExecutionWorld world = mock(JavaScriptExecutionWorld.class);
    AtomicReference<WebViewCompat.WebMessageListener> listener = new AtomicReference<>();
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      features.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.JS_INJECTION_IN_FRAME_AND_WORLD)).thenReturn(true);
      compat.when(() -> WebViewCompat.getExecutionWorld(view, "webview_all.app")).thenReturn(world);
      compat.when(() -> WebViewCompat.addWebMessageListener(eq(view), anyString(), anySet(), eq(world), any()))
          .thenAnswer(call -> { listener.set(call.getArgument(4)); return null; });
      compat.when(() -> WebViewCompat.addJavaScriptOnEvent(eq(view), anyString(), anyInt(), anySet(), eq(world)))
          .thenReturn(mock(ScriptHandler.class));
      WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      api.addUserJavaScript(view, "end", "globalThis.ready = true;", true, "app");
      compat.verify(() -> WebViewCompat.addJavaScriptOnEvent(eq(view), eq("globalThis.ready = true;"),
          eq(WebViewCompat.INJECTION_EVENT_DOCUMENT_END), anySet(), eq(world)));

      AtomicReference<ResultCompat<String>> result = new AtomicReference<>();
      JavaScriptReplyProxy child = mock(JavaScriptReplyProxy.class);
      listener.get().onPostMessage(view, mock(WebMessageCompat.class), mock(Uri.class), false, child);
      api.evaluateJavaScriptInWorld(view, "42", "app", ResultCompat.asCompatCallback(reply -> { result.set(reply); return null; }));
      assertTrue(result.get().isFailure());

      JavaScriptReplyProxy main = mock(JavaScriptReplyProxy.class);
      listener.get().onPostMessage(view, mock(WebMessageCompat.class), mock(Uri.class), true, main);
      api.evaluateJavaScriptInWorld(view, "42", "app", ResultCompat.asCompatCallback(reply -> { result.set(reply); return null; }));
      ArgumentCaptor<WebViewOutcomeReceiver> receiver = ArgumentCaptor.forClass(WebViewOutcomeReceiver.class);
      verify(main).executeJavaScript(eq("42"), receiver.capture());
      receiver.getValue().onResult("42");
      assertEquals("42", result.get().getOrNull());
      api.evaluateJavaScriptInWorld(view, "42", "app", ResultCompat.asCompatCallback(reply -> { result.set(reply); return null; }));
      verify(main, times(2)).executeJavaScript(eq("42"), receiver.capture());
      receiver.getValue().onError(new JavaScriptExecutionException(JavaScriptExecutionException.ERROR_FRAME_DESTROYED, "closed"));
      assertTrue(result.get().isFailure());
    }
  }

  @Test
  public void olderWebViewsRegisterRemovableDomReadyListenersAtDocumentStart() {
    WebView view = mock(WebView.class);
    ScriptHandler script = mock(ScriptHandler.class);
    try (MockedStatic<WebViewFeature> features = mockStatic(WebViewFeature.class);
        MockedStatic<WebViewCompat> compat = mockStatic(WebViewCompat.class)) {
      features.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)).thenReturn(true);
      compat.when(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), anyString(), anySet())).thenReturn(script);
      WebViewProxyApi api = new WebViewProxyApi(new TestProxyApiRegistrar());
      api.addUserJavaScript(view, "end", "globalThis.ready = true;", true, null);
      ArgumentCaptor<String> source = ArgumentCaptor.forClass(String.class);
      compat.verify(() -> WebViewCompat.addDocumentStartJavaScript(eq(view), source.capture(), anySet()));
      assertTrue(source.getValue().contains("DOMContentLoaded"));
      assertTrue(source.getValue().contains("globalThis.ready = true;"));
      api.removeDocumentStartJavaScript(view, "end");
      verify(script).remove();
    }
  }
}

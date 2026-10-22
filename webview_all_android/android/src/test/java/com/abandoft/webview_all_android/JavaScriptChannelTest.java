// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.ArgumentMatchers.isNull;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

import org.junit.Test;

public class JavaScriptChannelTest {
  @Test
  public void postMessage() {
    final JavaScriptChannelProxyApi mockApi = mock(JavaScriptChannelProxyApi.class);
    when(mockApi.getPigeonRegistrar()).thenReturn(new TestProxyApiRegistrar());

    final JavaScriptChannel instance = new JavaScriptChannel("channel", mockApi);
    final String message = "myString";
    instance.postMessage(message);

    verify(mockApi).postMessage(eq(instance), eq(message), isNull(), isNull(), any());
  }

  @Test
  public void postMessageWithSenderMetadata() {
    final JavaScriptChannelProxyApi mockApi = mock(JavaScriptChannelProxyApi.class);
    when(mockApi.getPigeonRegistrar()).thenReturn(new TestProxyApiRegistrar());
    final JavaScriptChannel instance = new JavaScriptChannel("channel", mockApi);

    instance.postMessageWithSenderMetadata("hello", "https://sender.example", false);

    verify(mockApi)
        .postMessage(eq(instance), eq("hello"), eq("https://sender.example"), eq(false), any());
  }

  @Test
  public void legacyEntryPointCannotSupplySenderMetadata() throws NoSuchMethodException {
    final java.lang.reflect.Method method =
        JavaScriptChannel.class.getDeclaredMethod(
            "postMessageWithSenderMetadata", String.class, String.class, Boolean.class);
    org.junit.Assert.assertFalse(
        method.isAnnotationPresent(android.webkit.JavascriptInterface.class));
  }
}

// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import static org.junit.Assert.assertThrows;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;
import static org.mockito.Mockito.mock;
import static org.mockito.Mockito.mockStatic;
import static org.mockito.Mockito.when;

import android.content.pm.ApplicationInfo;
import android.webkit.WebSettings;
import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;
import org.junit.Test;
import org.mockito.MockedStatic;

public class WebSettingsCompatTest {
  @Test
  public void algorithmicDarkeningChecksTargetSdkAndRuntimeSupport() {
    final TestProxyApiRegistrar registrar = new TestProxyApiRegistrar();
    final ApplicationInfo app = new ApplicationInfo();
    when(registrar.getContext().getApplicationInfo()).thenReturn(app);
    final PigeonApiWebSettingsCompat api = registrar.getPigeonApiWebSettingsCompat();
    final WebSettings settings = mock(WebSettings.class);
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
        MockedStatic<WebSettingsCompat> compat = mockStatic(WebSettingsCompat.class)) {
      app.targetSdkVersion = 32;
      assertFalse(api.setAlgorithmicDarkeningAllowed(settings, true));
      feature.verifyNoInteractions();
      compat.verifyNoInteractions();
      app.targetSdkVersion = 37;
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING))
          .thenReturn(false);
      assertFalse(api.setAlgorithmicDarkeningAllowed(settings, true));
      compat.verifyNoInteractions();
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING))
          .thenReturn(true);
      assertTrue(api.setAlgorithmicDarkeningAllowed(settings, true));
      assertTrue(api.setAlgorithmicDarkeningAllowed(settings, false));
      compat.verify(() -> WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, true));
      compat.verify(() -> WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, false));
      compat.when(() -> WebSettingsCompat.setAlgorithmicDarkeningAllowed(settings, true))
          .thenThrow(new UnsupportedOperationException("WebView changed"));
      assertFalse(api.setAlgorithmicDarkeningAllowed(settings, true));
    }
  }

  @Test
  public void setPaymentRequestEnabled() {
    final PigeonApiWebSettingsCompat api =
        new TestProxyApiRegistrar().getPigeonApiWebSettingsCompat();

    final WebSettings webSettings = mock(WebSettings.class);

    try (MockedStatic<WebSettingsCompat> mockedStatic = mockStatic(WebSettingsCompat.class)) {
      try (MockedStatic<WebViewFeature> mockedWebViewFeature = mockStatic(WebViewFeature.class)) {
        mockedWebViewFeature
            .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.PAYMENT_REQUEST))
            .thenReturn(true);
        api.setPaymentRequestEnabled(webSettings, true);
        mockedStatic.verify(() -> WebSettingsCompat.setPaymentRequestEnabled(webSettings, true));
      } catch (Exception e) {
        fail(e.toString());
      }
    } catch (Exception e) {
      fail(e.toString());
    }
  }

  @Test
  public void setWebAuthenticationSupport() {
    final PigeonApiWebSettingsCompat api =
        new TestProxyApiRegistrar().getPigeonApiWebSettingsCompat();
    final WebSettings webSettings = mock(WebSettings.class);

    try (MockedStatic<WebSettingsCompat> mockedStatic = mockStatic(WebSettingsCompat.class)) {
      try (MockedStatic<WebViewFeature> mockedWebViewFeature = mockStatic(WebViewFeature.class)) {
        mockedWebViewFeature
            .when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.WEB_AUTHENTICATION))
            .thenReturn(true);

        for (int support = 0; support <= 2; support++) {
          api.setWebAuthenticationSupport(webSettings, support);
          final int expectedSupport = support;
          mockedStatic.verify(
              () -> WebSettingsCompat.setWebAuthenticationSupport(webSettings, expectedSupport));
        }
      } catch (Exception exception) {
        fail(exception.toString());
      }
    } catch (Exception exception) {
      fail(exception.toString());
    }
  }

  @Test
  public void setWebAuthenticationSupportRejectsValuesOutsideIntRange() {
    final PigeonApiWebSettingsCompat api =
        new TestProxyApiRegistrar().getPigeonApiWebSettingsCompat();
    final WebSettings webSettings = mock(WebSettings.class);

    assertThrows(
        ArithmeticException.class,
        () ->
            api.setWebAuthenticationSupport(
                webSettings, (long) Integer.MAX_VALUE + 1L));
  }
}

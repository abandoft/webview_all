// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import android.annotation.SuppressLint;
import android.os.Build;
import android.util.Log;
import android.webkit.WebSettings;
import androidx.annotation.NonNull;
import androidx.webkit.WebSettingsCompat;
import androidx.webkit.WebViewFeature;

/**
 * Proxy API implementation for {@link WebSettingsCompat}.
 *
 * <p>This class may handle instantiating and adding native object instances that are attached to a
 * Dart instance or handle method calls on the associated native class or an instance of the class.
 */
public class WebSettingsCompatProxyApi extends PigeonApiWebSettingsCompat {
  public WebSettingsCompatProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @Override
  public boolean setAlgorithmicDarkeningAllowed(@NonNull WebSettings webSettings, boolean allowed) {
    final int targetSdk =
        ((ProxyApiRegistrar) getPigeonRegistrar())
            .getContext()
            .getApplicationInfo()
            .targetSdkVersion;
    if (targetSdk < Build.VERSION_CODES.TIRAMISU) {
      Log.w(
          "webview_all_android",
          "Algorithmic darkening requires target SDK >= 33; current target is " + targetSdk);
      return false;
    }
    try {
      if (!WebViewFeature.isFeatureSupported(WebViewFeature.ALGORITHMIC_DARKENING)) {
        Log.w(
            "webview_all_android",
            "The installed WebView does not support ALGORITHMIC_DARKENING; its current policy was retained.");
        return false;
      }
      WebSettingsCompat.setAlgorithmicDarkeningAllowed(webSettings, allowed);
      return true;
    } catch (RuntimeException exception) {
      Log.w(
          "webview_all_android",
          "Algorithmic darkening could not be applied; its current policy was retained.",
          exception);
      return false;
    }
  }

  /**
   * This method should only be called if {@link WebViewFeatureProxyApi#isFeatureSupported(String)}
   * with PAYMENT_REQUEST returns true.
   */
  @SuppressLint("RequiresFeature")
  @Override
  public void setPaymentRequestEnabled(@NonNull WebSettings webSettings, boolean enabled) {
    WebSettingsCompat.setPaymentRequestEnabled(webSettings, enabled);
  }

  /**
   * This method should only be called if {@link WebViewFeatureProxyApi#isFeatureSupported(String)}
   * with WEB_AUTHENTICATION returns true.
   */
  @SuppressLint("RequiresFeature")
  @Override
  public void setWebAuthenticationSupport(@NonNull WebSettings webSettings, long support) {
    WebSettingsCompat.setWebAuthenticationSupport(webSettings, Math.toIntExact(support));
  }
}

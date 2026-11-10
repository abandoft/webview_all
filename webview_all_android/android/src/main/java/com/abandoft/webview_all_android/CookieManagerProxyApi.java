// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import android.webkit.CookieManager;
import android.webkit.WebView;
import androidx.annotation.NonNull;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * Host API implementation for `CookieManager`.
 *
 * <p>This class may handle instantiating and adding native object instances that are attached to a
 * Dart instance or handle method calls on the associated native class or an instance of the class.
 */
public class CookieManagerProxyApi extends PigeonApiCookieManager {
  @Override public CookieManager forProfile(@NonNull String name) {
    if (!name.matches("[A-Za-z0-9_-]{1,64}") || !androidx.webkit.WebViewFeature.isFeatureSupported(androidx.webkit.WebViewFeature.MULTI_PROFILE))
      throw new UnsupportedOperationException("Named-profile cookies are unavailable.");
    return androidx.webkit.ProfileStore.getInstance().getOrCreateProfile("webview_all_" + name).getCookieManager();
  }
  public CookieManagerProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public ProxyApiRegistrar getPigeonRegistrar() {
    return (ProxyApiRegistrar) super.getPigeonRegistrar();
  }

  @NonNull
  @Override
  public CookieManager instance() {
    return CookieManager.getInstance();
  }

  @Override
  public void setCookie(
      @NonNull CookieManager pigeon_instance, @NonNull String url, @NonNull String value) {
    pigeon_instance.setCookie(url, value);
  }

  @Override
  public void removeAllCookies(
      @NonNull CookieManager pigeon_instance,
      @NonNull Function1<? super Result<Boolean>, Unit> callback) {
    pigeon_instance.removeAllCookies(aBoolean -> ResultCompat.success(aBoolean, callback));
  }

  @Override
  public void setAcceptThirdPartyCookies(
      @NonNull CookieManager pigeon_instance, @NonNull WebView webView, boolean accept) {
    pigeon_instance.setAcceptThirdPartyCookies(webView, accept);
  }

  @Override
  public @NonNull String getCookies(@NonNull CookieManager pigeon_instance, @NonNull String url) {
    return pigeon_instance.getCookie(url);
  }

  @Override
  public boolean supportsCookieInfo(@NonNull CookieManager manager) {
    return androidx.webkit.WebViewFeature.isFeatureSupported(
        androidx.webkit.WebViewFeature.GET_COOKIE_INFO);
  }

  @Override
  public java.util.List<String> getCookieInfo(
      @NonNull CookieManager manager, @NonNull String url) {
    if (!supportsCookieInfo(manager)) return null;
    return androidx.webkit.CookieManagerCompat.getCookieInfo(manager, url);
  }
}

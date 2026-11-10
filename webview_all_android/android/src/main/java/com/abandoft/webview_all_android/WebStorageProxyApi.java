// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

package com.abandoft.webview_all_android;

import android.webkit.WebStorage;
import androidx.annotation.NonNull;
import androidx.webkit.WebStorageCompat;
import androidx.webkit.WebViewFeature;
import kotlin.Result;
import kotlin.Unit;
import kotlin.jvm.functions.Function1;

/**
 * Host api implementation for {@link WebStorage}.
 *
 * <p>Handles creating {@link WebStorage}s that intercommunicate with a paired Dart object.
 */
public class WebStorageProxyApi extends PigeonApiWebStorage {
  @Override public WebStorage forProfile(@NonNull String name) {
    if (!name.matches("[A-Za-z0-9_-]{1,64}") || !androidx.webkit.WebViewFeature.isFeatureSupported(androidx.webkit.WebViewFeature.MULTI_PROFILE))
      throw new UnsupportedOperationException("Named-profile website data is unavailable.");
    return androidx.webkit.ProfileStore.getInstance().getOrCreateProfile("webview_all_" + name).getWebStorage();
  }
  /** Creates a host API that handles creating {@link WebStorage} and invoke its methods. */
  public WebStorageProxyApi(@NonNull ProxyApiRegistrar pigeonRegistrar) {
    super(pigeonRegistrar);
  }

  @NonNull
  @Override
  public WebStorage instance() {
    return WebStorage.getInstance();
  }

  @Override
  public void deleteAllData(@NonNull WebStorage pigeon_instance) {
    pigeon_instance.deleteAllData();
  }
  @Override public void deleteBrowsingDataForSite(@NonNull WebStorage storage, @NonNull String site,
      @NonNull Function1<? super Result<String>, Unit> callback) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
      ResultCompat.success(null, callback); return;
    }
    try {
      String[] normalized = new String[1];
      normalized[0] = WebStorageCompat.deleteBrowsingDataForSite(storage, site,
          () -> new android.os.Handler(android.os.Looper.getMainLooper()).post(
              () -> ResultCompat.success(normalized[0], callback)));
    } catch (RuntimeException error) { ResultCompat.failure(error, callback); }
  }

  @Override
  public void deleteBrowsingData(
      @NonNull WebStorage pigeon_instance,
      @NonNull Function1<? super Result<Boolean>, Unit> callback) {
    if (!WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA)) {
      ResultCompat.success(false, callback);
      return;
    }
    WebStorageCompat.deleteBrowsingData(
        pigeon_instance, () -> ResultCompat.success(true, callback));
  }
}

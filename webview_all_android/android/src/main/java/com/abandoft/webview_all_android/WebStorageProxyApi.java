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

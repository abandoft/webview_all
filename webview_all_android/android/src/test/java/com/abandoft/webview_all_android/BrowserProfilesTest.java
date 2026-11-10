package com.abandoft.webview_all_android;
import static org.junit.Assert.*;
import static org.mockito.Mockito.*;
import android.webkit.WebView;
import androidx.webkit.ProfileStore;
import androidx.webkit.WebViewFeature;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.Arrays;
import java.util.Collections;
import java.util.Map;
import org.junit.Test;
import org.mockito.ArgumentCaptor;
import org.mockito.MockedStatic;

public class BrowserProfilesTest {
  private Object invoke(String method, String name) {
    MethodChannel.Result result = mock(MethodChannel.Result.class);
    assertTrue(BrowserProfiles.handle(new MethodCall(method, Collections.singletonMap("name", name)), result));
    ArgumentCaptor<Object> value = ArgumentCaptor.forClass(Object.class);
    verify(result).success(value.capture()); return value.getValue();
  }
  @Test public void unsupportedProviderNeverCallsProfileStore() {
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
         MockedStatic<ProfileStore> profiles = mockStatic(ProfileStore.class)) {
      Map<?, ?> outcome = (Map<?, ?>) invoke("requestProfileDeletion", "a");
      assertEquals("unsupported", outcome.get("status")); profiles.verifyNoInteractions();
    }
  }
  @Test public void activeProfileIsBusyWithoutLoadingIt() {
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
         MockedStatic<ProfileStore> profiles = mockStatic(ProfileStore.class)) {
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)).thenReturn(true);
      ProfileStore store = mock(ProfileStore.class); profiles.when(ProfileStore::getInstance).thenReturn(store);
      WebView view = mock(WebView.class); BrowserProfiles.register(view, "a");
      try { assertEquals("busy", ((Map<?, ?>) invoke("requestProfileDeletion", "a")).get("status")); }
      finally { BrowserProfiles.unregister(view); }
      verifyNoInteractions(store);
    }
  }
  @Test public void loadedButClosedProfileRequiresRestart() {
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
         MockedStatic<ProfileStore> profiles = mockStatic(ProfileStore.class)) {
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)).thenReturn(true);
      ProfileStore store = mock(ProfileStore.class); profiles.when(ProfileStore::getInstance).thenReturn(store);
      when(store.getAllProfileNames()).thenReturn(Collections.singletonList("webview_all_a"));
      when(store.deleteProfile("webview_all_a")).thenThrow(new IllegalStateException());
      assertEquals("requiresRestart", ((Map<?, ?>) invoke("requestProfileDeletion", "a")).get("status"));
      verify(store, never()).getOrCreateProfile(anyString()); verify(store, never()).getProfile(anyString());
    }
  }
  @Test public void acceptedDeletionRemainsPending() {
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
         MockedStatic<ProfileStore> profiles = mockStatic(ProfileStore.class)) {
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)).thenReturn(true);
      ProfileStore store = mock(ProfileStore.class); profiles.when(ProfileStore::getInstance).thenReturn(store);
      when(store.getAllProfileNames()).thenReturn(Collections.singletonList("webview_all_a"));
      when(store.deleteProfile("webview_all_a")).thenReturn(true);
      assertEquals("pending", ((Map<?, ?>) invoke("requestProfileDeletion", "a")).get("status"));
      verify(store).deleteProfile("webview_all_a");
    }
  }
  @Test public void listingExcludesDefaultAndForeignStores() {
    try (MockedStatic<WebViewFeature> feature = mockStatic(WebViewFeature.class);
         MockedStatic<ProfileStore> profiles = mockStatic(ProfileStore.class)) {
      feature.when(() -> WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)).thenReturn(true);
      ProfileStore store = mock(ProfileStore.class); profiles.when(ProfileStore::getInstance).thenReturn(store);
      when(store.getAllProfileNames()).thenReturn(Arrays.asList("Default", "foreign", "webview_all_a", "webview_all_../default"));
      java.util.List<?> rows = (java.util.List<?>) invoke("listProfiles", null);
      assertEquals(1, rows.size()); assertEquals("a", ((Map<?, ?>) rows.get(0)).get("name"));
    }
  }
}

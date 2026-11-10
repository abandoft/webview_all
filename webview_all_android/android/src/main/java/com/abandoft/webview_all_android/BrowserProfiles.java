package com.abandoft.webview_all_android;

import android.webkit.WebView;
import androidx.webkit.ProfileStore;
import androidx.webkit.WebViewFeature;
import io.flutter.plugin.common.MethodCall;
import io.flutter.plugin.common.MethodChannel;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.WeakHashMap;

/** Only manages persistent profiles created in this plugin's namespace. */
final class BrowserProfiles {
  private static final String PREFIX = "webview_all_";
  private static final Map<WebView, String> active = new WeakHashMap<>();
  static void register(WebView view, String name) { active.put(view, name); }
  static void unregister(WebView view) { active.remove(view); }
  private static Map<String, Object> outcome(String status, String description) {
    Map<String, Object> value = new HashMap<>();
    value.put("status", status); value.put("description", description); return value;
  }
  static boolean handle(MethodCall call, MethodChannel.Result result) {
    if (!call.method.equals("profileManagementCapabilities") && !call.method.equals("listProfiles") &&
        !call.method.equals("requestProfileDeletion")) return false;
    try {
      boolean supported = WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE);
      if (call.method.equals("profileManagementCapabilities")) {
        Map<String, Object> value = new HashMap<>();
        value.put("listing", supported); value.put("deletion", supported);
        value.put("limitation", "Only plugin-owned named profiles are managed. Android cannot delete profiles loaded during this process, even after their views close; restart before deleting. Disk deletion is asynchronous.");
        result.success(value); return true;
      }
      if (!supported) {
        result.success(call.method.equals("listProfiles") ? null : outcome("unsupported", "MULTI_PROFILE is unavailable in this System WebView.")); return true;
      }
      ProfileStore store = ProfileStore.getInstance();
      if (call.method.equals("listProfiles")) {
        List<Map<String, Object>> rows = new ArrayList<>();
        for (String name : store.getAllProfileNames()) {
          if (name.startsWith(PREFIX) && name.substring(PREFIX.length()).matches("[A-Za-z0-9_-]{1,64}")) {
            Map<String, Object> row = new HashMap<>();
            row.put("name", name.substring(PREFIX.length())); rows.add(row);
          }
        }
        result.success(rows); return true;
      }
      String name = call.argument("name");
      if (name == null || !name.matches("[A-Za-z0-9_-]{1,64}")) {
        result.success(outcome("failed", "Invalid named profile; no data was deleted.")); return true;
      }
      if (active.containsValue(name)) {
        result.success(outcome("busy", "Close all views in this profile before requesting deletion.")); return true;
      }
      // Do not load a profile to check existence: loading prevents deletion in this process.
      if (!store.getAllProfileNames().contains(PREFIX + name)) {
        result.success(outcome("notFound", "The named profile does not exist.")); return true;
      }
      try {
        result.success(store.deleteProfile(PREFIX + name)
            ? outcome("pending", "Android accepted deletion; remaining files are removed asynchronously.")
            : outcome("notFound", "The named profile does not exist."));
      } catch (IllegalStateException error) {
        result.success(outcome("requiresRestart", "Android has loaded this profile in the current process. Restart the app and request deletion before reopening the profile."));
      }
    } catch (RuntimeException error) { result.error("profile_management_failed", error.toString(), null); }
    return true;
  }
}

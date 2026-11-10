package com.abandoft.webview_all_android;

import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Locale;
import java.util.Map;

/** Static URL policies execute in the engine request callback, without Dart. */
final class NetworkControl {
  static final class Rule {
    final String pattern;
    final boolean caseSensitive, block;
    Rule(Map<?, ?> value) {
      Object raw = value.get("urlPattern");
      if (!(raw instanceof String) || !validPattern((String) raw) ||
          !(value.get("resourceTypes") instanceof List) || !((List<?>) value.get("resourceTypes")).isEmpty())
        throw new IllegalArgumentException("Android content rules support URL patterns, without native resource-type filtering.");
      pattern = (String) raw;
      caseSensitive = Boolean.TRUE.equals(value.get("caseSensitive"));
      block = "block".equals(value.get("action"));
      if (!block && !"allow".equals(value.get("action"))) throw new IllegalArgumentException("Unknown content-rule action.");
    }
  }
  static boolean validPattern(String pattern) {
    if (pattern.isEmpty() || pattern.length() > 2048) return false;
    int stars = 0;
    for (char c : pattern.toCharArray()) { if (c < 32 || c > 126) return false; if (c == '*' && ++stars > 32) return false; }
    return true;
  }
  static boolean matches(String pattern, String url, boolean sensitive) {
    if (!sensitive) { pattern = pattern.toLowerCase(Locale.ROOT); url = url.toLowerCase(Locale.ROOT); }
    String[] parts = pattern.split("\\*", -1);
    if (parts.length == 1) return pattern.equals(url);
    if (!url.startsWith(parts[0]) || !url.endsWith(parts[parts.length - 1])) return false;
    int cursor = parts[0].length(), end = url.length() - parts[parts.length - 1].length();
    if (cursor > end) return false;
    for (int i = 1; i < parts.length - 1; i++) {
      int found = url.indexOf(parts[i], cursor);
      if (found < 0 || found + parts[i].length() > end) return false;
      cursor = found + parts[i].length();
    }
    return true;
  }
  static boolean configure(WebView view, Object raw) {
    if (!(view instanceof WebViewProxyApi.WebViewPlatformView) || !(raw instanceof List) || ((List<?>) raw).size() > 256) return false;
    List<Rule> rules = new ArrayList<>();
    for (Object value : (List<?>) raw) {
      if (!(value instanceof Map)) throw new IllegalArgumentException("Invalid content rule.");
      rules.add(new Rule((Map<?, ?>) value));
    }
    ((WebViewProxyApi.WebViewPlatformView) view).contentRules = Collections.unmodifiableList(rules);
    return true;
  }
  static boolean blocks(WebView view, WebResourceRequest request) {
    if (!(view instanceof WebViewProxyApi.WebViewPlatformView)) return false;
    boolean blocked = false;
    for (Rule rule : ((WebViewProxyApi.WebViewPlatformView) view).contentRules)
      if (matches(rule.pattern, request.getUrl().toString(), rule.caseSensitive)) blocked = rule.block;
    return blocked;
  }
}

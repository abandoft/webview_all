import 'dart:async';
import 'package:flutter/foundation.dart';
import 'webview_resource.dart';

enum WebViewContentRuleAction { block, allow, hideElements, upgradeToHttps }

enum WebViewContentRuleCondition { domain, topUrl, loadType }

enum WebViewContentRuleLoadType { firstParty, thirdParty }

enum WebViewNetworkResourceType {
  document,
  image,
  styleSheet,
  script,
  font,
  media,
  raw,
  svgDocument,
  popup,
  ping,
  other,
}

/// Native resource rules. URL patterns use '*' for any sequence of characters;
/// the last matching block/allow rule wins. Native cosmetic/HTTPS actions may
/// accumulate. Empty resourceTypes matches every resource. Domain and top-URL
/// conditions refer to the top document, not the requested resource.
@immutable
class WebViewContentRule {
  WebViewContentRule({
    required this.urlPattern,
    this.action = WebViewContentRuleAction.block,
    this.caseSensitive = false,
    Set<WebViewNetworkResourceType> resourceTypes = const {},
    Iterable<String> ifDomains = const [],
    Iterable<String> unlessDomains = const [],
    Iterable<String> ifTopUrls = const [],
    Iterable<String> unlessTopUrls = const [],
    Set<WebViewContentRuleLoadType> loadTypes = const {},
    this.selector,
  }) : resourceTypes = Set.unmodifiable(resourceTypes),
       ifDomains = List.unmodifiable(ifDomains),
       unlessDomains = List.unmodifiable(unlessDomains),
       ifTopUrls = List.unmodifiable(ifTopUrls),
       unlessTopUrls = List.unmodifiable(unlessTopUrls),
       loadTypes = Set.unmodifiable(loadTypes);
  final String urlPattern;
  final WebViewContentRuleAction action;
  final bool caseSensitive;
  final Set<WebViewNetworkResourceType> resourceTypes;

  /// Lowercase ASCII domains; a leading '*' includes their subdomains.
  /// Supply at most one nonempty domain or top-URL condition list per rule.
  final List<String> ifDomains, unlessDomains, ifTopUrls, unlessTopUrls;
  final Set<WebViewContentRuleLoadType> loadTypes;

  /// CSS selector for hideElements. Native CSS syntax rules apply.
  final String? selector;
  Set<WebViewContentRuleCondition> get conditions => {
    if (ifDomains.isNotEmpty || unlessDomains.isNotEmpty)
      WebViewContentRuleCondition.domain,
    if (ifTopUrls.isNotEmpty || unlessTopUrls.isNotEmpty)
      WebViewContentRuleCondition.topUrl,
    if (loadTypes.isNotEmpty) WebViewContentRuleCondition.loadType,
  };
  bool get isValid =>
      isValidWebViewUrlPattern(urlPattern) &&
      [
            ifDomains,
            unlessDomains,
            ifTopUrls,
            unlessTopUrls,
          ].where((v) => v.isNotEmpty).length <=
          1 &&
      [
        ifDomains,
        unlessDomains,
      ].every((v) => v.length <= 32 && v.every(_validRuleDomain)) &&
      [
        ifTopUrls,
        unlessTopUrls,
      ].every((v) => v.length <= 32 && v.every(isValidWebViewUrlPattern)) &&
      (action == WebViewContentRuleAction.hideElements
          ? selector != null &&
                selector!.trim().isNotEmpty &&
                selector!.length <= 4096 &&
                !selector!.contains('\u0000')
          : selector == null);
  static bool _validRuleDomain(String value) {
    final domain = value.startsWith('*') ? value.substring(1) : value;
    return domain.isNotEmpty &&
        domain.length <= 253 &&
        domain
            .split('.')
            .every(
              (label) => RegExp(
                r'^[a-z0-9](?:[a-z0-9-]{0,61}[a-z0-9])?$',
              ).hasMatch(label),
            );
  }

  Map<String, Object?> toMap() => {
    'urlPattern': urlPattern,
    'urlFilter': webViewUrlPatternToRegex(urlPattern),
    'action': action.name,
    'caseSensitive': caseSensitive,
    'resourceTypes': resourceTypes.map((v) => v.name).toList(),
    'ifDomains': ifDomains,
    'unlessDomains': unlessDomains,
    'ifTopUrls': ifTopUrls.map(webViewUrlPatternToRegex).toList(),
    'unlessTopUrls': unlessTopUrls.map(webViewUrlPatternToRegex).toList(),
    'loadTypes': loadTypes
        .map(
          (v) => v == WebViewContentRuleLoadType.firstParty
              ? 'first-party'
              : 'third-party',
        )
        .toList(),
    if (selector != null) 'selector': selector,
  };
}

bool isValidWebViewUrlPattern(String pattern) =>
    pattern.isNotEmpty &&
    pattern.length <= 2048 &&
    pattern.split('*').length <= 33 &&
    !RegExp(r'[^\x20-\x7e]').hasMatch(pattern);
String webViewUrlPatternToRegex(String pattern) =>
    '^${pattern.split('*').map(RegExp.escape).join('.*')}\$';
bool webViewUrlPatternMatches(
  String pattern,
  String value, {
  bool caseSensitive = false,
}) {
  final text = caseSensitive ? value : value.toLowerCase();
  final parts = (caseSensitive ? pattern : pattern.toLowerCase()).split('*');
  if (parts.length == 1) return text == parts.single;
  if (!text.startsWith(parts.first) || !text.endsWith(parts.last)) return false;
  var cursor = parts.first.length;
  final end = text.length - parts.last.length;
  if (cursor > end) return false;
  for (final part in parts.skip(1).take(parts.length - 2)) {
    final index = text.indexOf(part, cursor);
    if (index < 0 || index + part.length > end) return false;
    cursor = index + part.length;
  }
  return true;
}

/// Network capabilities describe native interception, not JavaScript hooks.
@immutable
class WebViewNetworkCapabilities {
  const WebViewNetworkCapabilities({
    this.contentRules = false,
    this.ruleActions = const {
      WebViewContentRuleAction.block,
      WebViewContentRuleAction.allow,
    },
    this.ruleConditions = const {},
    this.resourceTypes = const {},
    this.httpInterception = false,
    this.requestBodies = false,
    this.customSchemes = false,
    this.customSchemeFetch = false,
    this.customSchemeRequestBodies = false,
    this.streamingResponses = false,
    this.limitation,
  });
  final bool contentRules;
  final Set<WebViewContentRuleAction> ruleActions;
  final Set<WebViewContentRuleCondition> ruleConditions;
  final Set<WebViewNetworkResourceType> resourceTypes;
  bool get ruleResourceTypes => resourceTypes.isNotEmpty;
  final bool httpInterception;
  final bool requestBodies;
  final bool customSchemes;

  /// The engine permits fetch/XHR to registered schemes, subject to CORS/CSP.
  /// Android accepts navigation/subresources but rejects these fetch URLs.
  final bool customSchemeFetch;
  final bool customSchemeRequestBodies;
  final bool streamingResponses;
  final String? limitation;
}

enum WebViewRequestDecisionKind { allow, block, respond }

@immutable
class WebViewRequestDecision {
  const WebViewRequestDecision.allow()
    : kind = WebViewRequestDecisionKind.allow,
      response = null;
  const WebViewRequestDecision.block()
    : kind = WebViewRequestDecisionKind.block,
      response = null;
  const WebViewRequestDecision.respond(WebViewResourceResponse response)
    : kind = WebViewRequestDecisionKind.respond,
      response = response;
  final WebViewRequestDecisionKind kind;
  final WebViewResourceResponse? response;
}

/// Handles only selected native HTTP(S) requests. Allow retains the engine's
/// original request, cookies and body; responses reuse the resource transport.
/// It does not intercept every redirect, service worker, WebSocket or download.
@immutable
class WebViewRequestDelegate {
  WebViewRequestDelegate({
    required Iterable<String> urlPatterns,
    this.caseSensitive = false,
    required this.onRequest,
  }) : urlPatterns = List.unmodifiable(urlPatterns);
  final List<String> urlPatterns;
  final bool caseSensitive;
  final FutureOr<WebViewRequestDecision> Function(
    WebViewResourceRequest request,
  )
  onRequest;
}

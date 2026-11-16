import 'dart:convert';

import 'package:webview_all/webview_all.dart';

/// Example: rewrite selected URL-encoded XHR form fields in a trusted page.
///
/// Register before loading [pageOrigin]. Only its main document is affected.
/// [endpoint] matches origin and path, ignoring query parameters. This does not
/// intercept fetch, HTML form navigation, workers or arbitrary network traffic.
/// Unsupported bodies retain their original values and produce a console warning.
/// Reinject with empty [fields] to disable rewriting for [endpoint].
WebViewUserScript formRequestFieldsScript({
  required Uri pageOrigin,
  required Uri endpoint,
  required Map<String, String> fields,
}) {
  for (final uri in [pageOrigin, endpoint]) {
    if (!uri.isAbsolute ||
        !const {'http', 'https'}.contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      throw ArgumentError.value(uri, 'uri', 'Use an absolute HTTP(S) URL.');
    }
  }
  return WebViewUserScript(
    source:
        '''
(() => {
  const pageOrigin = new URL(${jsonEncode(pageOrigin.origin)}).origin;
  if (location.origin !== pageOrigin) return;
  const endpoint = new URL(${jsonEncode(endpoint.toString())});
  const fields = JSON.parse(${jsonEncode(jsonEncode(fields))});
  const proto = globalThis.XMLHttpRequest?.prototype;
  if (!proto) {
    console.warn('Form request example: XMLHttpRequest is unavailable.');
    return;
  }
  const slot = Symbol.for('webview_all.example.formRequestFields');
  const key = endpoint.origin + endpoint.pathname;
  let state = proto[slot];
  if (Object.keys(fields).length === 0) {
    state?.rules.delete(key);
    return;
  }
  if (!state) {
    if (!Object.isExtensible(proto) || ['open', 'send', 'setRequestHeader'].some(
      name => typeof proto[name] !== 'function' ||
        Object.getOwnPropertyDescriptor(proto, name)?.writable === false)) {
      console.warn('Form request example: XHR hooks are unavailable.');
      return;
    }
    const requests = new WeakMap();
    const rules = new Map();
    const open = proto.open, send = proto.send, header = proto.setRequestHeader;
    let warned = false;
    proto.open = function(method, url) {
      let target;
      if ((typeof url === 'string' || url instanceof URL) &&
          typeof method === 'string') {
        try {
          const uri = new URL(typeof url === 'string' ? url : url.href, document.baseURI);
          target = {key: uri.origin + uri.pathname,
            method: method.toUpperCase(), contentType: ''};
        } catch (_) {}
      }
      requests.set(this, target);
      try { return Reflect.apply(open, this, arguments); }
      catch (error) { requests.delete(this); throw error; }
    };
    proto.setRequestHeader = function(name, value) {
      const result = Reflect.apply(header, this, arguments);
      const target = requests.get(this);
      if (target && typeof name === 'string' && typeof value === 'string' &&
          name.toLowerCase() === 'content-type') {
        target.contentType += (target.contentType ? ', ' : '') + value;
      }
      return result;
    };
    proto.send = function(body) {
      const target = requests.get(this);
      const values = target && rules.get(target.key);
      if (!values || target.method === 'GET' || target.method === 'HEAD') {
        return Reflect.apply(send, this, arguments);
      }
      const isParams = body instanceof URLSearchParams;
      const isForm = typeof body === 'string' &&
        target.contentType.split(';')[0].trim().toLowerCase() ===
          'application/x-www-form-urlencoded';
      if (!isParams && !isForm) {
        if (!warned) {
          console.warn('Form request example: only URLSearchParams or ' +
            'URL-encoded text bodies can be rewritten. The body was retained.');
          warned = true;
        }
        return Reflect.apply(send, this, arguments);
      }
      const form = new URLSearchParams(body.toString());
      for (const [name, value] of Object.entries(values)) form.set(name, value);
      const args = Array.from(arguments);
      args[0] = isParams ? form : form.toString();
      return Reflect.apply(send, this, args);
    };
    state = {rules};
    Object.defineProperty(proto, slot, {value: state});
  }
  // Reinjection updates the rule instead of stacking XHR wrappers.
  state.rules.set(key, fields);
})();
''',
  );
}

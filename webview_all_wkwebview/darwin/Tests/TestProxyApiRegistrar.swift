// Copyright 2013 The Flutter Authors
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import Security
import XCTest

@testable import webview_all_wkwebview

func createTestCertificate() -> SecCertificate {
  let base64 =
    "MIIDOTCCAiGgAwIBAgIUcuDBtQwriSXMi+ZdmunbgWwc8QAwDQYJKoZIhvcNAQELBQAwRTELMAkG"
    + "A1UEBhMCVVMxETAPBgNVBAgMCE5ldy1Zb3JrMRIwEAYDVQQHDAlNYW5oYXR0YW4xDzANBgNVBAoM"
    + "Bkdvb2dsZTAeFw0yNTA0MDUxNzIzMTNaFw0zODEyMTMxNzIzMTNaMEUxCzAJBgNVBAYTAlVTMREw"
    + "DwYDVQQIDAhOZXctWW9yazESMBAGA1UEBwwJTWFuaGF0dGFuMQ8wDQYDVQQKDAZHb29nbGUwggEi"
    + "MA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQDMLHeeYNhcH6ClnSXKnuG1znSWVcGgrSW6o9H4"
    + "djLhUZBW0q8OLGzhONrtoGEUTrkv89H9iVIA8/4V92545qdHU861vsczqRaj7mwCwsgodtrz0Q69"
    + "wJt/IYGCJqY+FUyZ9tJnwdwGvNNX+VCIV5k+UiKbca5FiFXk90yCwcRTeZfZrVzPTNHme+WjtIL"
    + "/SVGA4ejKqcniuy5rORS0cqCtEH9kKj7xj7IvKQIK+MUoUZdt7YWn2qCZ+ZDuTOlwAWQmIZB348"
    + "F4jHEaCZSngrtEyjE3pQu2r/9f8uUodRL2XwM2viNrvI79SVOq/b9NzDHl1lhIB3o+zCnFhV+tB"
    + "qBpAgMBAAGjITAfMB0GA1UdDgQWBBQaYJVKDrQI3LAHnqBrtJKYLTJkDjANBgkqhkiG9w0BAQsF"
    + "AAOCAQEAmxpnb7iK8JRyXB9vHKgigYEeDEWFoO/dmjSbdh0chMeiGHGZy+cTvYDhUDxFObwMSk+"
    + "BHHKvKVdG5h3pk5bYGQaMYsomjWl213VPeXQhfyeYbCJ8YW5YjEgRWejRndIkb7evM6X8BLPQ3OX"
    + "y6sqMUUOEFye0PDJvoGvyEBg6iwORxi5sPKg/y0gojpzdVGDDYKwW5h4/avSYZ0dCWmO5dgepGh"
    + "QXIxXHjoO+6WMulX0of+6OyS5/lH0ehi13VLe0/usb85680BF2sG7jrU2/X1/i/+ZqJSNjtFC4S"
    + "woJilTrc5g6d3OQkWZXzA40oyGjBUJtKlndNKPzupf0VfMgkw=="
  guard
    let data = Data(base64Encoded: base64) as CFData?,
    let certificate = SecCertificateCreateWithData(nil, data)
  else {
    fatalError("The embedded test certificate is invalid.")
  }
  return certificate
}

class TestProxyApiRegistrar: ProxyAPIRegistrar {
  init() {
    super.init(
      binaryMessenger: TestBinaryMessenger(),
      assetManager: FlutterAssetManager(bundle: TestBundle()))
  }

  override func dispatchOnMainThread(
    execute work: @escaping (@escaping (String, PigeonError) -> Void) -> Void
  ) {
    work { _, _ in }
  }
}

class TestBundle: Bundle, @unchecked Sendable {
  override func url(forResource name: String?, withExtension ext: String?) -> URL? {
    return URL(string: "assets/www/index.html")!
  }
}

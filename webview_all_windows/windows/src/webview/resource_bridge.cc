#include "webview/resource_bridge.h"

#include <flutter/method_channel.h>
#include <flutter/method_result_functions.h>
#include <flutter/standard_method_codec.h>
#include <shlwapi.h>
#include <wil/com.h>
#include <wil/resource.h>
#include <wrl.h>

#include <algorithm>
#include <atomic>
#include <cstring>
#include <functional>
#include <limits>
#include <map>
#include <mutex>
#include <vector>

#include "util/string_converter.h"

namespace webview_all_windows {
namespace {
using flutter::EncodableMap;
using flutter::EncodableValue;

thread_local std::map<UINT_PTR, std::function<void()>> request_timeouts;

UINT_PTR StartTimeout(std::function<void()> callback) {
  const UINT_PTR timer =
      SetTimer(nullptr, 0, 30000, [](HWND, UINT, UINT_PTR id, DWORD) {
        const auto entry = request_timeouts.find(id);
        if (entry == request_timeouts.end()) return;
        auto expired = std::move(entry->second);
        request_timeouts.erase(entry);
        KillTimer(nullptr, id);
        expired();
      });
  if (timer) request_timeouts[timer] = std::move(callback);
  return timer;
}

const EncodableValue* Get(const EncodableMap& map, const char* key) {
  const auto entry = map.find(EncodableValue(key));
  return entry == map.end() ? nullptr : &entry->second;
}
int64_t Number(const EncodableValue* value, int64_t fallback = 0) {
  if (!value) return fallback;
  if (const auto* number = std::get_if<int64_t>(value)) return *number;
  if (const auto* number = std::get_if<int32_t>(value)) return *number;
  return fallback;
}

// A file-backed view of one response range. All data already exists on disk;
// reads do not copy the complete file into Dart or native memory.
class ResourceFileStream final : public IStream {
 public:
  ResourceFileStream(wil::com_ptr<IStream> source, uint64_t offset,
                     uint64_t length, std::shared_ptr<std::atomic<bool>> alive)
      : source_(std::move(source)),
        offset_(offset),
        length_(length),
        alive_(std::move(alive)) {
    CoCreateFreeThreadedMarshaler(static_cast<IStream*>(this),
                                  marshaler_.put());
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void** value) override {
    if (!value) return E_POINTER;
    *value = nullptr;
    if (iid == __uuidof(IMarshal) && marshaler_)
      return marshaler_->QueryInterface(iid, value);
    if (iid != __uuidof(IUnknown) && iid != __uuidof(ISequentialStream) &&
        iid != __uuidof(IStream))
      return E_NOINTERFACE;
    *value = static_cast<IStream*>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --references_;
    if (!count) delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE Read(void* buffer, ULONG count,
                                 ULONG* read) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (read) *read = 0;
    if (!alive_->load()) return STG_E_REVERTED;
    if (!buffer && count) return STG_E_INVALIDPOINTER;
    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset_ + position_);
    HRESULT hr = source_->Seek(position, STREAM_SEEK_SET, nullptr);
    if (FAILED(hr)) return hr;
    const ULONG available =
        static_cast<ULONG>(std::min<uint64_t>(count, length_ - position_));
    ULONG received = 0;
    hr = source_->Read(buffer, available, &received);
    position_ += received;
    if (read) *read = received;
    if (FAILED(hr)) return hr;
    return received == count ? S_OK : S_FALSE;
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER move, DWORD origin,
                                 ULARGE_INTEGER* position) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (origin > STREAM_SEEK_END) return STG_E_INVALIDFUNCTION;
    const int64_t base =
        origin == STREAM_SEEK_SET
            ? 0
            : static_cast<int64_t>(origin == STREAM_SEEK_CUR ? position_
                                                             : length_);
    if ((move.QuadPart < 0 && move.QuadPart < -base) ||
        (move.QuadPart > 0 && static_cast<uint64_t>(move.QuadPart) >
                                  length_ - static_cast<uint64_t>(base)))
      return STG_E_INVALIDFUNCTION;
    position_ = static_cast<uint64_t>(base + move.QuadPart);
    if (position) position->QuadPart = position_;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Stat(STATSTG* stat, DWORD) override {
    if (!stat) return E_POINTER;
    memset(stat, 0, sizeof(*stat));
    stat->type = STGTY_STREAM;
    stat->cbSize.QuadPart = length_;
    stat->grfMode = STGM_READ;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Clone(IStream** stream) override {
    if (!stream) return E_POINTER;
    *stream = nullptr;
    std::lock_guard<std::mutex> lock(mutex_);
    wil::com_ptr<IStream> copy;
    const HRESULT hr = source_->Clone(copy.put());
    if (FAILED(hr)) return hr;
    auto* result =
        new ResourceFileStream(std::move(copy), offset_, length_, alive_);
    result->position_ = position_;
    *stream = result;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Write(const void*, ULONG, ULONG*) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE CopyTo(IStream* target, ULARGE_INTEGER count,
                                   ULARGE_INTEGER* read,
                                   ULARGE_INTEGER* written) override {
    if (!target) return STG_E_INVALIDPOINTER;
    if (read) read->QuadPart = 0;
    if (written) written->QuadPart = 0;
    std::vector<uint8_t> buffer(65536);
    uint64_t remaining = count.QuadPart;
    while (remaining) {
      const ULONG requested =
          static_cast<ULONG>(std::min<uint64_t>(remaining, buffer.size()));
      ULONG received = 0, sent = 0;
      HRESULT hr = Read(buffer.data(), requested, &received);
      if (FAILED(hr)) return hr;
      if (!received) return S_FALSE;
      if (read) read->QuadPart += received;
      hr = target->Write(buffer.data(), received, &sent);
      if (written) written->QuadPart += sent;
      if (FAILED(hr)) return hr;
      if (sent != received) return STG_E_MEDIUMFULL;
      remaining -= received;
    }
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Commit(DWORD) override { return S_OK; }
  HRESULT STDMETHODCALLTYPE Revert() override { return STG_E_ACCESSDENIED; }
  HRESULT STDMETHODCALLTYPE LockRegion(ULARGE_INTEGER, ULARGE_INTEGER,
                                       DWORD) override {
    return STG_E_INVALIDFUNCTION;
  }
  HRESULT STDMETHODCALLTYPE UnlockRegion(ULARGE_INTEGER, ULARGE_INTEGER,
                                         DWORD) override {
    return STG_E_INVALIDFUNCTION;
  }

 private:
  std::atomic<ULONG> references_{1};
  wil::com_ptr<IStream> source_;
  wil::com_ptr<IUnknown> marshaler_;
  uint64_t offset_, length_, position_ = 0;
  std::shared_ptr<std::atomic<bool>> alive_;
  std::mutex mutex_;
};
}  // namespace

struct ResourceBridgeWindows::State {
  struct Pending {
    wil::com_ptr<ICoreWebView2WebResourceRequestedEventArgs> args;
    wil::com_ptr<ICoreWebView2Deferral> deferral;
    UINT_PTR timer = 0;
    ~Pending() {
      if (timer) {
        KillTimer(nullptr, timer);
        request_timeouts.erase(timer);
      }
      if (deferral) deferral->Complete();
    }
  };
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  wil::com_ptr<ICoreWebView2Environment> environment;
  std::string channel_name, host, kind = "resource";
  std::vector<std::string> selectors;
  bool enabled = false, case_sensitive = false, notify_closed = true;
  int64_t next_id = 0;
  std::shared_ptr<std::atomic<bool>> alive =
      std::make_shared<std::atomic<bool>>(true);
  std::map<std::string, std::shared_ptr<Pending>> pending;

  static bool Matches(std::string pattern, std::string url, bool sensitive) {
    if (!sensitive) {
      auto lower = [](unsigned char c) -> char {
        return static_cast<char>(c >= 'A' && c <= 'Z' ? c + ('a' - 'A') : c);
      };
      std::transform(pattern.begin(), pattern.end(), pattern.begin(), lower);
      std::transform(url.begin(), url.end(), url.begin(), lower);
    }
    std::vector<std::string> parts;
    size_t start = 0, found;
    while ((found = pattern.find('*', start)) != std::string::npos) {
      parts.push_back(pattern.substr(start, found - start));
      start = found + 1;
    }
    parts.push_back(pattern.substr(start));
    if (parts.size() == 1) return pattern == url;
    if (url.rfind(parts.front(), 0) != 0 || url.size() < parts.back().size() ||
        url.compare(url.size() - parts.back().size(), parts.back().size(),
                    parts.back()))
      return false;
    size_t cursor = parts.front().size(),
           end = url.size() - parts.back().size();
    if (cursor > end) return false;
    for (size_t i = 1; i + 1 < parts.size(); ++i) {
      auto index = url.find(parts[i], cursor);
      if (index == std::string::npos || index > end ||
          parts[i].size() > end - index)
        return false;
      cursor = index + parts[i].size();
    }
    return true;
  }
  static bool ValidPattern(const std::string& pattern) {
    return !pattern.empty() && pattern.size() <= 2048 &&
           std::count(pattern.begin(), pattern.end(), '*') <= 32 &&
           std::all_of(pattern.begin(), pattern.end(),
                       [](unsigned char c) { return c >= 32 && c <= 126; });
  }
  bool Selects(const std::string& url) const {
    if (kind == "resource")
      return !host.empty() && url.rfind("https://" + host + "/", 0) == 0;
    if (kind == "schemes") {
      auto colon = url.find(':');
      return colon != std::string::npos &&
             std::find(selectors.begin(), selectors.end(),
                       url.substr(0, colon)) != selectors.end();
    }
    if (!enabled ||
        (url.rfind("http://", 0) != 0 && url.rfind("https://", 0) != 0))
      return false;
    return std::any_of(
        selectors.begin(), selectors.end(),
        [&](const std::string& p) { return Matches(p, url, case_sensitive); });
  }
  void Respond(const std::string& id, const EncodableValue* value) {
    auto entry = pending.find(id);
    if (entry == pending.end()) return;
    auto request = entry->second;
    pending.erase(entry);
    const auto* metadata = value ? std::get_if<EncodableMap>(value) : nullptr;
    const auto* pass = metadata ? Get(*metadata, "passThrough") : nullptr;
    if (enabled && kind == "http" && pass && std::get_if<bool>(pass) &&
        std::get<bool>(*pass)) {
      request->deferral->Complete();
      request->deferral.reset();
      return;
    }
    int status = 500;
    std::wstring headers = L"Content-Length: 0\r\nCache-Control: no-store\r\n";
    wil::com_ptr<IStream> stream;
    if (metadata && enabled) {
      status = static_cast<int>(Number(Get(*metadata, "statusCode"), 500));
      if (!((status >= 200 && status <= 299) ||
            (status >= 400 && status <= 599)))
        status = 500;
      const auto* header_value = Get(*metadata, "headers");
      const auto* header_map =
          header_value ? std::get_if<EncodableMap>(header_value) : nullptr;
      if (header_map) {
        headers.clear();
        for (const auto& header : *header_map) {
          const auto* key = std::get_if<std::string>(&header.first);
          const auto* text = std::get_if<std::string>(&header.second);
          if (key && text && key->find_first_of("\r\n") == std::string::npos &&
              text->find_first_of("\r\n") == std::string::npos)
            headers += util::Utf16FromUtf8(*key + ": " + *text + "\r\n");
        }
      }
      const auto* file_value = Get(*metadata, "filePath");
      const auto* file =
          file_value ? std::get_if<std::string>(file_value) : nullptr;
      if (file) {
        wil::com_ptr<IStream> source;
        auto offset = Number(Get(*metadata, "offset")),
             length = Number(Get(*metadata, "contentLength"));
        auto hr = SHCreateStreamOnFileEx(util::Utf16FromUtf8(*file).c_str(),
                                         STGM_READ | STGM_SHARE_DENY_WRITE,
                                         FILE_ATTRIBUTE_NORMAL, FALSE, nullptr,
                                         source.put());
        if (SUCCEEDED(hr) && offset >= 0 && length >= 0)
          stream.attach(new ResourceFileStream(
              std::move(source), static_cast<uint64_t>(offset),
              static_cast<uint64_t>(length), alive));
        else {
          status = 500;
          headers = L"Content-Length: 0\r\n";
        }
      } else {
        const auto* bytes_value = Get(*metadata, "bytes");
        const auto* bytes = bytes_value
                                ? std::get_if<std::vector<uint8_t>>(bytes_value)
                                : nullptr;
        if (bytes && !bytes->empty() &&
            bytes->size() <= (std::numeric_limits<UINT>::max)())
          stream.attach(SHCreateMemStream(bytes->data(),
                                          static_cast<UINT>(bytes->size())));
        if (bytes && !bytes->empty() && !stream) {
          status = 500;
          headers = L"Content-Length: 0\r\n";
        }
      }
    }
    wil::com_ptr<ICoreWebView2WebResourceResponse> response;
    if (SUCCEEDED(environment->CreateWebResourceResponse(
            stream.get(), status, L"Resource", headers.c_str(),
            response.put())))
      request->args->put_Response(response.get());
    request->deferral->Complete();
    request->deferral.reset();
  }
  void Cancel() {
    alive->store(false);
    enabled = false;
    while (!pending.empty()) Respond(pending.begin()->first, nullptr);
  }
  ~State() {
    Cancel();
    if (channel && notify_closed) channel->InvokeMethod("closed", nullptr);
  }
  static void Begin(const std::shared_ptr<State>& state,
                    ICoreWebView2WebResourceRequestedEventArgs* args,
                    ICoreWebView2WebResourceRequest* request,
                    const std::string& url) {
    auto pending = std::make_shared<Pending>();
    pending->args = args;
    if (FAILED(args->GetDeferral(pending->deferral.put()))) return;
    auto id = std::to_string(++state->next_id);
    state->pending[id] = pending;
    const std::weak_ptr<State> weak = state;
    pending->timer = StartTimeout([weak, id] {
      if (auto current = weak.lock()) {
        current->channel->InvokeMethod(
            "cancel", std::make_unique<EncodableValue>(EncodableMap{
                          {EncodableValue("id"), EncodableValue(id)}}));
        current->Respond(id, nullptr);
      }
    });
    if (!state->enabled || !pending->timer || state->pending.size() > 64) {
      state->Respond(id, nullptr);
      return;
    }
    EncodableMap headers;
    wil::com_ptr<ICoreWebView2HttpRequestHeaders> request_headers;
    wil::com_ptr<ICoreWebView2HttpHeadersCollectionIterator> iterator;
    if (SUCCEEDED(request->get_Headers(request_headers.put())) &&
        SUCCEEDED(request_headers->GetIterator(iterator.put()))) {
      BOOL has = FALSE;
      iterator->get_HasCurrentHeader(&has);
      while (has) {
        wil::unique_cotaskmem_string name, value;
        if (SUCCEEDED(iterator->GetCurrentHeader(name.put(), value.put())))
          headers[EncodableValue(util::Utf8FromUtf16(name.get()))] =
              EncodableValue(util::Utf8FromUtf16(value.get()));
        iterator->MoveNext(&has);
      }
    }
    wil::unique_cotaskmem_string method;
    request->get_Method(method.put());
    EncodableMap arguments{
        {EncodableValue("id"), EncodableValue(id)},
        {EncodableValue("uri"), EncodableValue(url)},
        {EncodableValue("method"),
         EncodableValue(method ? util::Utf8FromUtf16(method.get()) : "GET")},
        {EncodableValue("headers"), EncodableValue(headers)}};
    bool available = false;
    wil::com_ptr<IStream> source, copy;
    std::vector<uint8_t> body;
    if (SUCCEEDED(request->get_Content(source.put()))) {
      if (!source)
        available = true;
      else if (SUCCEEDED(source->Clone(copy.put()))) {
        STATSTG stat{};
        LARGE_INTEGER start{};
        if (SUCCEEDED(copy->Stat(&stat, STATFLAG_NONAME)) &&
            stat.cbSize.QuadPart <= 4 * 1024 * 1024 &&
            SUCCEEDED(copy->Seek(start, STREAM_SEEK_SET, nullptr))) {
          body.resize(static_cast<size_t>(stat.cbSize.QuadPart));
          ULONG read = 0;
          available =
              body.empty() ||
              (SUCCEEDED(copy->Read(body.data(),
                                    static_cast<ULONG>(body.size()), &read)) &&
               read == body.size());
        }
      }
    }
    arguments[EncodableValue("bodyAvailable")] = EncodableValue(available);
    if (available)
      arguments[EncodableValue("body")] = EncodableValue(std::move(body));
    // ResourceContext cannot distinguish main-frame and iframe documents;
    // isForMainFrame intentionally remains null.
    state->channel->InvokeMethod(
        "open", std::make_unique<EncodableValue>(arguments),
        std::make_unique<flutter::MethodResultFunctions<EncodableValue>>(
            [weak, id](const EncodableValue* value) {
              if (auto current = weak.lock()) current->Respond(id, value);
            },
            [weak, id](const std::string&, const std::string&,
                       const EncodableValue*) {
              if (auto current = weak.lock()) current->Respond(id, nullptr);
            },
            [weak, id] {
              if (auto current = weak.lock()) current->Respond(id, nullptr);
            }));
  }
};

struct ResourceBridgeWindows::Registry {
  struct Rule {
    std::string pattern;
    bool block, sensitive;
    std::vector<int> contexts;
  };
  wil::com_ptr<ICoreWebView2Environment> environment;
  std::shared_ptr<State> resource, http, schemes;
  std::vector<Rule> rules;
  static std::vector<int> Contexts(const std::string& name) {
    if (name == "document") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_DOCUMENT};
    if (name == "styleSheet")
      return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_STYLESHEET};
    if (name == "image") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_IMAGE};
    if (name == "media") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_MEDIA};
    if (name == "font") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FONT};
    if (name == "script") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_SCRIPT};
    if (name == "raw")
      return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_XML_HTTP_REQUEST,
              COREWEBVIEW2_WEB_RESOURCE_CONTEXT_FETCH};
    if (name == "ping") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_PING};
    if (name == "other") return {COREWEBVIEW2_WEB_RESOURCE_CONTEXT_OTHER};
    return {};
  }
  HRESULT Handle(ICoreWebView2WebResourceRequestedEventArgs* args) {
    wil::com_ptr<ICoreWebView2WebResourceResponse> prior;
    if (SUCCEEDED(args->get_Response(prior.put())) && prior) return S_OK;
    wil::com_ptr<ICoreWebView2WebResourceRequest> request;
    if (FAILED(args->get_Request(request.put()))) return S_OK;
    wil::unique_cotaskmem_string raw;
    if (FAILED(request->get_Uri(raw.put())) || !raw) return S_OK;
    auto url = util::Utf8FromUtf16(raw.get());
    COREWEBVIEW2_WEB_RESOURCE_CONTEXT context =
        COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL;
    args->get_ResourceContext(&context);
    bool blocked = false;
    for (const auto& rule : rules) {
      if ((!rule.contexts.empty() &&
           std::find(rule.contexts.begin(), rule.contexts.end(),
                     static_cast<int>(context)) == rule.contexts.end()) ||
          !State::Matches(rule.pattern, url, rule.sensitive))
        continue;
      blocked = rule.block;
    }
    if (blocked) {
      wil::com_ptr<ICoreWebView2WebResourceResponse> response;
      auto hr = environment->CreateWebResourceResponse(
          nullptr, 403, L"Blocked",
          L"Content-Length: 0\r\nCache-Control: no-store\r\n", response.put());
      return SUCCEEDED(hr) ? args->put_Response(response.get()) : hr;
    }
    // One dispatcher arbitrates all plugin request handlers. Application
    // resources, custom schemes and HTTP interception cannot double-respond.
    for (const auto& state : {resource, schemes, http}) {
      if (state && state->Selects(url)) {
        State::Begin(state, args, request.get(), url);
        break;
      }
    }
    return S_OK;
  }
};

ResourceBridgeWindows::ResourceBridgeWindows(ICoreWebView2* view)
    : view_(view), registry_(std::make_shared<Registry>()) {}
ResourceBridgeWindows::~ResourceBridgeWindows() {
  if (registered_) view_->remove_WebResourceRequested(token_);
  for (const auto& filter : filters_)
    view_->RemoveWebResourceRequestedFilter(
        filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  registry_.reset();
}
HRESULT ResourceBridgeWindows::Reattach() {
  // WebView2 requires WebResourceRequested registration after put_NewWindow.
  // Some Runtimes retain the earlier registration; remove it before adding a
  // new one so the same request cannot be answered twice.
  if (registered_) view_->remove_WebResourceRequested(token_);
  registered_ = false;
  for (const auto& filter : filters_)
    view_->RemoveWebResourceRequestedFilter(
        filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  filters_.clear();
  const HRESULT result = EnsureHandler();
  return SUCCEEDED(result) ? UpdateFilters() : result;
}
HRESULT ResourceBridgeWindows::EnsureHandler() {
  if (registered_) return S_OK;
  wil::com_ptr<ICoreWebView2_2> view2;
  auto hr = view_->QueryInterface(IID_PPV_ARGS(view2.put()));
  if (FAILED(hr)) return hr;
  hr = view2->get_Environment(registry_->environment.put());
  if (FAILED(hr)) return hr;
  const std::weak_ptr<Registry> weak = registry_;
  hr = view_->add_WebResourceRequested(
      Microsoft::WRL::Callback<ICoreWebView2WebResourceRequestedEventHandler>(
          [weak](ICoreWebView2*,
                 ICoreWebView2WebResourceRequestedEventArgs* args) -> HRESULT {
            auto registry = weak.lock();
            return registry ? registry->Handle(args) : S_OK;
          })
          .Get(),
      &token_);
  if (SUCCEEDED(hr)) registered_ = true;
  return hr;
}
HRESULT ResourceBridgeWindows::UpdateFilters() {
  std::vector<std::wstring> next;
  if (!registry_->rules.empty() ||
      (registry_->http && registry_->http->enabled))
    next.push_back(L"*");
  else {
    if (registry_->resource && !registry_->resource->host.empty())
      next.push_back(
          util::Utf16FromUtf8("https://" + registry_->resource->host + "/*"));
    if (registry_->schemes)
      for (const auto& scheme : registry_->schemes->selectors)
        next.push_back(util::Utf16FromUtf8(scheme + ":*"));
  }
  std::vector<std::wstring> added;
  for (const auto& filter : next)
    if (std::find(filters_.begin(), filters_.end(), filter) == filters_.end()) {
      auto hr = view_->AddWebResourceRequestedFilter(
          filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
      if (FAILED(hr)) {
        for (const auto& value : added)
          view_->RemoveWebResourceRequestedFilter(
              value.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
        return hr;
      }
      added.push_back(filter);
    }
  for (const auto& filter : filters_)
    if (std::find(next.begin(), next.end(), filter) == next.end())
      view_->RemoveWebResourceRequestedFilter(
          filter.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  filters_ = std::move(next);
  return S_OK;
}
HRESULT ResourceBridgeWindows::Configure(flutter::BinaryMessenger* messenger,
                                         const std::string& channel,
                                         const std::string& host,
                                         bool enabled) {
  auto hr = EnsureHandler();
  if (FAILED(hr)) return hr;
  if (host.empty() ||
      host.find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789-.") !=
          std::string::npos)
    return E_INVALIDARG;
  auto next = std::make_shared<State>();
  next->channel_name = channel;
  next->host = host;
  next->enabled = enabled;
  next->environment = registry_->environment;
  next->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, channel, &flutter::StandardMethodCodec::GetInstance());
  auto previous = registry_->resource;
  registry_->resource = next;
  hr = UpdateFilters();
  if (FAILED(hr)) {
    registry_->resource = previous;
    next->notify_closed = false;
    return hr;
  }
  if (previous) {
    if (previous->channel_name == channel) previous->notify_closed = false;
    previous->Cancel();
  }
  return S_OK;
}
HRESULT ResourceBridgeWindows::ConfigureNetwork(
    flutter::BinaryMessenger* messenger, const flutter::EncodableMap& args) {
  auto hr = EnsureHandler();
  if (FAILED(hr)) return hr;
  auto* kind_value = Get(args, "kind");
  auto* name_value = Get(args, "channel");
  auto* enabled_value = Get(args, "enabled");
  auto* kind = kind_value ? std::get_if<std::string>(kind_value) : nullptr;
  auto* name = name_value ? std::get_if<std::string>(name_value) : nullptr;
  auto* enabled = enabled_value ? std::get_if<bool>(enabled_value) : nullptr;
  if (!kind || (*kind != "http" && *kind != "schemes") || !name || !enabled)
    return E_INVALIDARG;
  auto& slot = *kind == "http" ? registry_->http : registry_->schemes;
  if (!*enabled) {
    if (slot && slot->channel_name == *name) slot->Cancel();
    return UpdateFilters();
  }
  auto* selector_value = Get(args, *kind == "http" ? "urlPatterns" : "schemes");
  auto* selectors = selector_value
                        ? std::get_if<flutter::EncodableList>(selector_value)
                        : nullptr;
  if (!selectors || selectors->empty() || selectors->size() > 256)
    return E_INVALIDARG;
  auto next = std::make_shared<State>();
  next->kind = *kind;
  for (const auto& selector : *selectors) {
    auto* value = std::get_if<std::string>(&selector);
    if (!value || !State::ValidPattern(*value) ||
        (*kind == "schemes" &&
         (value->find_first_not_of("abcdefghijklmnopqrstuvwxyz0123456789+.-") !=
              std::string::npos ||
          value->size() > 32)))
      return E_INVALIDARG;
    next->selectors.push_back(*value);
  }
  next->enabled = true;
  next->channel_name = *name;
  next->environment = registry_->environment;
  auto* sensitive = Get(args, "caseSensitive");
  next->case_sensitive =
      sensitive && std::get_if<bool>(sensitive) && std::get<bool>(*sensitive);
  next->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, *name, &flutter::StandardMethodCodec::GetInstance());
  auto previous = slot;
  slot = next;
  hr = UpdateFilters();
  if (FAILED(hr)) {
    slot = previous;
    next->notify_closed = false;
    return hr;
  }
  if (previous) previous->Cancel();
  return S_OK;
}
HRESULT ResourceBridgeWindows::ConfigureRules(
    const flutter::EncodableList& rules) {
  auto hr = EnsureHandler();
  if (FAILED(hr)) return hr;
  if (rules.size() > 256) return E_INVALIDARG;
  std::vector<Registry::Rule> next;
  for (const auto& item : rules) {
    auto* rule = std::get_if<EncodableMap>(&item);
    if (!rule) return E_INVALIDARG;
    auto* pattern_value = Get(*rule, "urlPattern");
    auto* action_value = Get(*rule, "action");
    auto* types_value = Get(*rule, "resourceTypes");
    auto* case_value = Get(*rule, "caseSensitive");
    auto* pattern =
        pattern_value ? std::get_if<std::string>(pattern_value) : nullptr;
    auto* action =
        action_value ? std::get_if<std::string>(action_value) : nullptr;
    auto* types = types_value ? std::get_if<flutter::EncodableList>(types_value)
                              : nullptr;
    if (!pattern || !State::ValidPattern(*pattern) || !action ||
        (*action != "block" && *action != "allow") || !types)
      return E_INVALIDARG;
    Registry::Rule result{*pattern,
                          *action == "block",
                          case_value && std::get_if<bool>(case_value) &&
                              std::get<bool>(*case_value),
                          {}};
    for (const auto& type : *types) {
      auto* name = std::get_if<std::string>(&type);
      if (!name) return E_INVALIDARG;
      auto contexts = Registry::Contexts(*name);
      if (contexts.empty()) return E_INVALIDARG;
      result.contexts.insert(result.contexts.end(), contexts.begin(),
                             contexts.end());
    }
    next.push_back(std::move(result));
  }
  auto previous = std::move(registry_->rules);
  registry_->rules = std::move(next);
  hr = UpdateFilters();
  if (FAILED(hr)) registry_->rules = std::move(previous);
  return hr;
}
}  // namespace webview_all_windows

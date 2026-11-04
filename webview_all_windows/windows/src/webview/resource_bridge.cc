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

UINT_PTR StartTimeout(UINT timeout_millis, std::function<void()> callback) {
  const UINT_PTR timer =
      SetTimer(nullptr, 0, timeout_millis, [](HWND, UINT, UINT_PTR id, DWORD) {
        const auto entry = request_timeouts.find(id);
        if (entry == request_timeouts.end())
          return;
        auto expired = std::move(entry->second);
        request_timeouts.erase(entry);
        KillTimer(nullptr, id);
        expired();
      });
  if (timer)
    request_timeouts[timer] = std::move(callback);
  return timer;
}

const EncodableValue *Get(const EncodableMap &map, const char *key) {
  const auto entry = map.find(EncodableValue(key));
  return entry == map.end() ? nullptr : &entry->second;
}
int64_t Number(const EncodableValue *value, int64_t fallback = 0) {
  if (!value)
    return fallback;
  if (const auto *number = std::get_if<int64_t>(value))
    return *number;
  if (const auto *number = std::get_if<int32_t>(value))
    return *number;
  return fallback;
}

// A file-backed view of one response range. All data already exists on disk;
// reads do not copy the complete file into Dart or native memory.
class ResourceFileStream final : public IStream {
public:
  ResourceFileStream(wil::com_ptr<IStream> source, uint64_t offset,
                     uint64_t length, std::shared_ptr<std::atomic<bool>> alive)
      : source_(std::move(source)), offset_(offset), length_(length),
        alive_(std::move(alive)) {
    CoCreateFreeThreadedMarshaler(static_cast<IStream *>(this),
                                  marshaler_.put());
  }
  HRESULT STDMETHODCALLTYPE QueryInterface(REFIID iid, void **value) override {
    if (!value)
      return E_POINTER;
    *value = nullptr;
    if (iid == __uuidof(IMarshal) && marshaler_)
      return marshaler_->QueryInterface(iid, value);
    if (iid != __uuidof(IUnknown) && iid != __uuidof(ISequentialStream) &&
        iid != __uuidof(IStream))
      return E_NOINTERFACE;
    *value = static_cast<IStream *>(this);
    AddRef();
    return S_OK;
  }
  ULONG STDMETHODCALLTYPE AddRef() override { return ++references_; }
  ULONG STDMETHODCALLTYPE Release() override {
    const ULONG count = --references_;
    if (!count)
      delete this;
    return count;
  }
  HRESULT STDMETHODCALLTYPE Read(void *buffer, ULONG count,
                                 ULONG *read) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (read)
      *read = 0;
    if (!alive_->load())
      return STG_E_REVERTED;
    if (!buffer && count)
      return STG_E_INVALIDPOINTER;
    LARGE_INTEGER position{};
    position.QuadPart = static_cast<LONGLONG>(offset_ + position_);
    HRESULT hr = source_->Seek(position, STREAM_SEEK_SET, nullptr);
    if (FAILED(hr))
      return hr;
    const ULONG available =
        static_cast<ULONG>(std::min<uint64_t>(count, length_ - position_));
    ULONG received = 0;
    hr = source_->Read(buffer, available, &received);
    position_ += received;
    if (read)
      *read = received;
    if (FAILED(hr))
      return hr;
    return received == count ? S_OK : S_FALSE;
  }
  HRESULT STDMETHODCALLTYPE Seek(LARGE_INTEGER move, DWORD origin,
                                 ULARGE_INTEGER *position) override {
    std::lock_guard<std::mutex> lock(mutex_);
    if (origin > STREAM_SEEK_END)
      return STG_E_INVALIDFUNCTION;
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
    if (position)
      position->QuadPart = position_;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Stat(STATSTG *stat, DWORD) override {
    if (!stat)
      return E_POINTER;
    memset(stat, 0, sizeof(*stat));
    stat->type = STGTY_STREAM;
    stat->cbSize.QuadPart = length_;
    stat->grfMode = STGM_READ;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Clone(IStream **stream) override {
    if (!stream)
      return E_POINTER;
    *stream = nullptr;
    std::lock_guard<std::mutex> lock(mutex_);
    wil::com_ptr<IStream> copy;
    const HRESULT hr = source_->Clone(copy.put());
    if (FAILED(hr))
      return hr;
    auto *result =
        new ResourceFileStream(std::move(copy), offset_, length_, alive_);
    result->position_ = position_;
    *stream = result;
    return S_OK;
  }
  HRESULT STDMETHODCALLTYPE Write(const void *, ULONG, ULONG *) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE SetSize(ULARGE_INTEGER) override {
    return STG_E_ACCESSDENIED;
  }
  HRESULT STDMETHODCALLTYPE CopyTo(IStream *target, ULARGE_INTEGER count,
                                   ULARGE_INTEGER *read,
                                   ULARGE_INTEGER *written) override {
    if (!target)
      return STG_E_INVALIDPOINTER;
    if (read)
      read->QuadPart = 0;
    if (written)
      written->QuadPart = 0;
    std::vector<uint8_t> buffer(65536);
    uint64_t remaining = count.QuadPart;
    while (remaining) {
      const ULONG requested =
          static_cast<ULONG>(std::min<uint64_t>(remaining, buffer.size()));
      ULONG received = 0, sent = 0;
      HRESULT hr = Read(buffer.data(), requested, &received);
      if (FAILED(hr))
        return hr;
      if (!received)
        return S_FALSE;
      if (read)
        read->QuadPart += received;
      hr = target->Write(buffer.data(), received, &sent);
      if (written)
        written->QuadPart += sent;
      if (FAILED(hr))
        return hr;
      if (sent != received)
        return STG_E_MEDIUMFULL;
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
} // namespace

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
      if (deferral)
        deferral->Complete();
    }
  };
  std::unique_ptr<flutter::MethodChannel<EncodableValue>> channel;
  wil::com_ptr<ICoreWebView2Environment> environment;
  std::string host;
  bool enabled = false;
  UINT request_timeout_millis = 30000;
  int64_t next_id = 0;
  std::shared_ptr<std::atomic<bool>> alive =
      std::make_shared<std::atomic<bool>>(true);
  std::map<std::string, std::shared_ptr<Pending>> pending;

  void Respond(const std::string &id, const EncodableValue *value) {
    const auto entry = pending.find(id);
    if (entry == pending.end())
      return;
    auto request = entry->second;
    pending.erase(entry);
    int status = 500;
    std::wstring headers = L"Content-Length: 0\r\n";
    wil::com_ptr<IStream> stream;
    const auto *metadata = value ? std::get_if<EncodableMap>(value) : nullptr;
    if (metadata && enabled) {
      status = static_cast<int>(Number(Get(*metadata, "statusCode"), 500));
      const auto *header_value = Get(*metadata, "headers");
      const auto *header_map =
          header_value ? std::get_if<EncodableMap>(header_value) : nullptr;
      if (header_map) {
        headers.clear();
        for (const auto &header : *header_map) {
          const auto *key = std::get_if<std::string>(&header.first);
          const auto *text = std::get_if<std::string>(&header.second);
          if (key && text)
            headers += util::Utf16FromUtf8(*key + ": " + *text + "\r\n");
        }
      }
      const auto *file_value = Get(*metadata, "filePath");
      const auto *file =
          file_value ? std::get_if<std::string>(file_value) : nullptr;
      if (file) {
        wil::com_ptr<IStream> source;
        const HRESULT hr = SHCreateStreamOnFileEx(
            util::Utf16FromUtf8(*file).c_str(),
            STGM_READ | STGM_SHARE_DENY_WRITE, FILE_ATTRIBUTE_NORMAL, FALSE,
            nullptr, source.put());
        if (SUCCEEDED(hr)) {
          stream.attach(new ResourceFileStream(
              std::move(source),
              static_cast<uint64_t>(Number(Get(*metadata, "offset"))),
              static_cast<uint64_t>(Number(Get(*metadata, "contentLength"))),
              alive));
        } else {
          status = 500;
          headers = L"Content-Length: 0\r\n";
        }
      } else {
        const auto *bytes_value = Get(*metadata, "bytes");
        const auto *bytes = bytes_value
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
            response.put()))) {
      request->args->put_Response(response.get());
    }
    request->deferral->Complete();
    request->deferral.reset();
  }

  void Cancel() {
    alive->store(false);
    alive = std::make_shared<std::atomic<bool>>(true);
    enabled = false;
    while (!pending.empty())
      Respond(pending.begin()->first, nullptr);
  }
};

ResourceBridgeWindows::ResourceBridgeWindows(ICoreWebView2 *view)
    : view_(view), state_(std::make_shared<State>()) {}
ResourceBridgeWindows::~ResourceBridgeWindows() {
  state_->Cancel();
  if (state_->channel)
    state_->channel->InvokeMethod("closed", nullptr);
  if (registered_)
    view_->remove_WebResourceRequested(token_);
  if (!filter_.empty())
    view_->RemoveWebResourceRequestedFilter(
        filter_.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
}

HRESULT ResourceBridgeWindows::Configure(flutter::BinaryMessenger *messenger,
                                         const std::string &channel,
                                         const std::string &host,
                                         bool enabled,
                                         UINT request_timeout_millis) {
  state_->Cancel();
  state_->channel = std::make_unique<flutter::MethodChannel<EncodableValue>>(
      messenger, channel, &flutter::StandardMethodCodec::GetInstance());
  state_->host = host;
  state_->request_timeout_millis = request_timeout_millis;
  wil::com_ptr<ICoreWebView2_2> view2;
  HRESULT hr = view_->QueryInterface(IID_PPV_ARGS(view2.put()));
  if (FAILED(hr))
    return hr;
  hr = view2->get_Environment(state_->environment.put());
  if (FAILED(hr))
    return hr;
  if (!filter_.empty())
    view_->RemoveWebResourceRequestedFilter(
        filter_.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  filter_ = util::Utf16FromUtf8("https://" + host + "/*");
  hr = view_->AddWebResourceRequestedFilter(
      filter_.c_str(), COREWEBVIEW2_WEB_RESOURCE_CONTEXT_ALL);
  if (FAILED(hr))
    return hr;
  if (!registered_) {
    const std::weak_ptr<State> weak = state_;
    hr = view_->add_WebResourceRequested(
        Microsoft::WRL::Callback<ICoreWebView2WebResourceRequestedEventHandler>(
            [weak](
                ICoreWebView2 *,
                ICoreWebView2WebResourceRequestedEventArgs *args) -> HRESULT {
              const auto state = weak.lock();
              if (!state)
                return S_OK;
              wil::com_ptr<ICoreWebView2WebResourceRequest> request;
              if (FAILED(args->get_Request(request.put())))
                return S_OK;
              wil::unique_cotaskmem_string uri, method;
              request->get_Uri(uri.put());
              request->get_Method(method.put());
              const std::string url = uri ? util::Utf8FromUtf16(uri.get()) : "";
              if (url.rfind("https://" + state->host + "/", 0) != 0)
                return S_OK;
              auto pending = std::make_shared<State::Pending>();
              pending->args = args;
              if (FAILED(args->GetDeferral(pending->deferral.put())))
                return S_OK;
              const std::string id = std::to_string(++state->next_id);
              state->pending[id] = pending;
              pending->timer = StartTimeout(
                  state->request_timeout_millis, [weak, id]() {
                    if (auto current = weak.lock()) {
                      current->channel->InvokeMethod(
                          "cancel",
                          std::make_unique<EncodableValue>(EncodableMap{
                              {EncodableValue("id"), EncodableValue(id)}}));
                      current->Respond(id, nullptr);
                    }
                  });
              if (!state->enabled) {
                state->Respond(id, nullptr);
                return S_OK;
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
                  if (SUCCEEDED(
                          iterator->GetCurrentHeader(name.put(), value.put())))
                    headers[EncodableValue(util::Utf8FromUtf16(name.get()))] =
                        EncodableValue(util::Utf8FromUtf16(value.get()));
                  iterator->MoveNext(&has);
                }
              }
              EncodableMap arguments{
                  {EncodableValue("id"), EncodableValue(id)},
                  {EncodableValue("uri"), EncodableValue(url)},
                  {EncodableValue("method"),
                   EncodableValue(method ? util::Utf8FromUtf16(method.get())
                                         : "GET")},
                  {EncodableValue("headers"), EncodableValue(headers)}};
              state->channel->InvokeMethod(
                  "open", std::make_unique<EncodableValue>(arguments),
                  std::make_unique<
                      flutter::MethodResultFunctions<EncodableValue>>(
                      [weak, id](const EncodableValue *value) {
                        if (auto current = weak.lock())
                          current->Respond(id, value);
                      },
                      [weak, id](const std::string &, const std::string &,
                                 const EncodableValue *) {
                        if (auto current = weak.lock())
                          current->Respond(id, nullptr);
                      },
                      [weak, id]() {
                        if (auto current = weak.lock())
                          current->Respond(id, nullptr);
                      }));
              return S_OK;
            })
            .Get(),
        &token_);
    if (FAILED(hr))
      return hr;
    registered_ = true;
  }
  state_->enabled = enabled;
  return S_OK;
}
} // namespace webview_all_windows

package com.abandoft.webview_all_android;

import android.graphics.Bitmap;
import android.graphics.Canvas;
import android.os.Handler;
import android.os.Looper;
import android.os.Message;
import android.os.Build;
import android.os.Bundle;
import android.app.Activity;
import android.content.Context;
import android.print.PrintJob;
import android.print.PrintManager;
import androidx.webkit.WebViewCompat;
import android.view.ViewGroup;
import android.webkit.RenderProcessGoneDetail;
import android.webkit.WebView;
import androidx.webkit.WebViewFeature;
import io.flutter.plugin.common.BinaryMessenger;
import io.flutter.plugin.common.MethodChannel;
import java.io.ByteArrayOutputStream;
import java.io.File;
import java.lang.ref.WeakReference;
import java.util.ArrayList;
import java.util.HashMap;
import java.util.Map;
import java.util.UUID;
import java.util.WeakHashMap;

/** Native browser operations and bounded, controller-owned page tasks. */
final class BrowserOperations {
  private static final int MAX_BYTES = 64 * 1024 * 1024;
  private final MethodChannel channel;
  private final ProxyApiRegistrar registrar;
  private final Map<String, PendingWindow> windows = new HashMap<>();
  private final Map<WebView, Boolean> enabled = new WeakHashMap<>();
  private final Map<String, NavigationState> navigationStates = new HashMap<>();
  private final Map<File, PendingArchive> archives = new HashMap<>();
  private final Map<String, PrintJob> printJobs = new HashMap<>();
  private static String printState(PrintJob job) {
    if (job == null) return "unknown";
    if (job.isCompleted()) return "completed";
    if (job.isCancelled()) return "cancelled";
    if (job.isFailed()) return "failed";
    if (job.isBlocked()) return "blocked";
    if (job.isStarted()) return "started";
    if (job.isQueued()) return "queued";
    return "presented";
  }
  private final class PendingArchive {
    final WeakReference<WebView> view;
    final File file;
    final MethodChannel.Result result;
    final Handler handler = new Handler(Looper.getMainLooper());
    final Runnable timeout = () -> fail("archive_timeout", "The native archive timed out.");
    boolean done;
    PendingArchive(WebView view, File file, MethodChannel.Result result) {
      this.view = new WeakReference<>(view); this.file = file; this.result = result;
      archives.put(file, this); handler.postDelayed(timeout, 30000);
    }
    void fail(String code, String message) {
      if (!finish()) return;
      file.delete(); result.error(code, message, null);
    }
    boolean finish() {
      if (done) return false;
      done = true; archives.remove(file); handler.removeCallbacks(timeout); return true;
    }
    void complete(String path) {
      if (!finish()) { file.delete(); return; }
      try {
        if (path == null || !file.getAbsolutePath().equals(path) || file.length() <= 0 || file.length() > MAX_BYTES)
          throw new java.io.IOException("The archive is empty or exceeds the 64 MiB limit.");
        try (java.io.FileInputStream input = new java.io.FileInputStream(file)) {
          ByteArrayOutputStream bytes = new ByteArrayOutputStream();
          byte[] chunk = new byte[65536]; int count;
          while ((count = input.read(chunk)) != -1) {
            if (bytes.size() > MAX_BYTES - count) throw new java.io.IOException("Archive exceeds the output limit.");
            bytes.write(chunk, 0, count);
          }
          result.success(bytes.toByteArray());
        }
      } catch (java.io.IOException | RuntimeException error) { result.error("archive_failed", error.toString(), null); }
      finally { file.delete(); }
    }
  }
  private static final class NavigationState {
    final Bundle data;
    final String profile;
    final boolean limited;
    NavigationState(WebView view, Bundle data) {
      this.data = data;
      profile = profileName(view);
      limited = view instanceof WebViewProxyApi.WebViewPlatformView &&
          ((WebViewProxyApi.WebViewPlatformView) view).limitedIncognito;
    }
    boolean matches(WebView view) {
      return profile.equals(profileName(view)) && limited ==
          (view instanceof WebViewProxyApi.WebViewPlatformView &&
           ((WebViewProxyApi.WebViewPlatformView) view).limitedIncognito);
    }
  }
  private static String profileName(WebView view) {
    return WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)
        ? WebViewCompat.getProfile(view).getName() : "Default";
  }
  private static final Map<WebView, Boolean> usedTargets = new WeakHashMap<>();
  static void markNavigation(WebView view) {
    usedTargets.put(view, true);
    BrowserOperations owner = owners.get(view);
    if (owner != null) {
      for (PendingWindow request : new ArrayList<>(owner.windows.values())) {
        if (request.parent.get() == view)
          request.finish(null);
      }
    }
  }
  private static final Map<WebView, BrowserOperations> owners = new WeakHashMap<>();

  private final class PendingWindow {
    final WeakReference<WebView> parent;
    final Message message;
    final String id = UUID.randomUUID().toString();
    final Handler handler = new Handler(Looper.getMainLooper());
    final Runnable timeout = () -> finish(null);
    boolean done;
    PendingWindow(WebView view, Message value) {
      parent = new WeakReference<>(view);
      message = value;
    }
    boolean finish(WebView child) {
      if (done)
        return false;
      done = true;
      windows.remove(id);
      handler.removeCallbacks(timeout);
      try {
        ((WebView.WebViewTransport) message.obj).setWebView(child);
        message.sendToTarget();
        return child != null;
      } catch (RuntimeException ignored) {
        return false;
      }
    }
  }

  static Boolean requestWindow(WebView parent, boolean dialog, boolean gesture, Message message) {
    BrowserOperations owner = owners.get(parent);
    if (owner == null || !Boolean.TRUE.equals(owner.enabled.get(parent)))
      return null;
    PendingWindow request = owner.new PendingWindow(parent, message);
    owner.windows.put(request.id, request);
    request.handler.postDelayed(request.timeout, 25000);
    Map<String, Object> args = new HashMap<>();
    args.put(
        "webViewId", owner.registrar.getInstanceManager().getIdentifierForStrongReference(parent));
    args.put("requestId", request.id);
    args.put("isDialog", dialog);
    args.put("isUserGesture", gesture);
    owner.channel.invokeMethod("newWindowRequested", args);
    return true;
  }

  static void windowCloseRequested(WebView view) {
    BrowserOperations owner = owners.get(view);
    if (owner == null)
      return;
    Map<String, Object> args = new HashMap<>();
    args.put(
        "webViewId", owner.registrar.getInstanceManager().getIdentifierForStrongReference(view));
    owner.channel.invokeMethod("windowCloseRequested", args);
  }

  @androidx.annotation.RequiresApi(26)
  static boolean rendererGone(WebView view, RenderProcessGoneDetail detail) {
    BrowserOperations owner = owners.get(view);
    if (owner != null) {
      Map<String, Object> event = new HashMap<>();
      event.put("webViewId", owner.registrar.getInstanceManager().getIdentifierForStrongReference(view));
      event.put("didCrash", detail.didCrash());
      owner.channel.invokeMethod("processFailed", event);
    }
    // Android requires removing and destroying each affected WebView. Returning
    // true handles the failure and keeps the application process alive.
    if (view.getParent() instanceof ViewGroup) ((ViewGroup) view.getParent()).removeView(view);
    try { view.destroy(); }
    catch (RuntimeException error) {
      android.util.Log.w("webview_all", "Cleaning up the failed renderer: " + error);
    }
    return true;
  }

  static void cancel(WebView view) {
    usedTargets.remove(view);
    BrowserOperations owner = owners.remove(view);
    if (owner == null)
      return;
    owner.enabled.remove(view);
    for (PendingArchive request : new ArrayList<>(owner.archives.values())) {
      if (request.view.get() == view) request.fail("archive_cancelled", "The WebView was closed.");
    }
    for (PendingWindow request : new ArrayList<>(owner.windows.values())) {
      if (request.parent.get() == view)
        request.finish(null);
    }
  }

  BrowserOperations(ProxyApiRegistrar registrar, BinaryMessenger messenger) {
    this.registrar = registrar;
    channel = new MethodChannel(messenger, "com.abandoft.webview_all_android/browser");
    channel.setMethodCallHandler((call, result) -> {
      if (BrowserProfiles.handle(call, result)) return;
      if (call.method.equals("printJobState") || call.method.equals("cancelPrintJob") || call.method.equals("releasePrintJob")) {
        String id = call.argument("jobId");
        PrintJob job = printJobs.get(id);
        try {
          if (call.method.equals("releasePrintJob")) { printJobs.remove(id); result.success(null); }
          else if (call.method.equals("printJobState")) result.success(printState(job));
          else {
            boolean active = job != null && !job.isCompleted() && !job.isCancelled() && !job.isFailed();
            if (active) job.cancel();
            result.success(active);
          }
        } catch (RuntimeException error) { result.error("print_failed", error.toString(), null); }
        return;
      }
      if (call.method.equals("releaseNavigationState")) {
        navigationStates.remove((String) call.argument("stateId"));
        result.success(null);
        return;
      }
      if (call.method.equals("supportsProcessFailures")) {
        result.success(Build.VERSION.SDK_INT >= 26);
        return;
      }
      if (call.method.equals("supportsNamedProfiles")) {
        result.success(WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)); return;
      }
      if (call.method.equals("supportsCompleteDataClearing")) {
        result.success(WebViewFeature.isFeatureSupported(WebViewFeature.DELETE_BROWSING_DATA));
        return;
      }
      if (call.method.equals("attachNewWindow") || call.method.equals("rejectNewWindow")) {
        String requestId = call.argument("requestId");
        PendingWindow request = windows.get(requestId);
        if (request == null) {
          result.success(false);
          return;
        }
        if (call.method.equals("rejectNewWindow")) {
          request.finish(null);
          result.success(true);
          return;
        }
        Number childId = call.argument("childWebViewId");
        Object candidate = childId == null
            ? null
            : registrar.getInstanceManager().getInstance(childId.longValue());
        WebView child = candidate instanceof WebView ? (WebView) candidate : null;
        if (child == null || child == request.parent.get()
            || Boolean.TRUE.equals(usedTargets.get(child))
            || child.copyBackForwardList().getSize() != 0) {
          request.finish(null);
          result.error(
              "invalid_child", "A fresh WebView in the opener's session is required.", null);
          return;
        }
        usedTargets.put(child, true);
        result.success(request.finish(child));
        return;
      }
      if (!call.method.equals("takeScreenshot")
          && !call.method.equals("setContentRules")
          && !call.method.equals("configureNetworkBridge")
          && !call.method.equals("createArchive")
          && !call.method.equals("printPage")
          && !call.method.equals("clearNavigationHistory")
          && !call.method.equals("saveNavigationState")
          && !call.method.equals("restoreNavigationState")
          && !call.method.equals("setNewWindowDelegateEnabled")
          && !call.method.equals("observeProcessFailures")
          && !call.method.equals("observeWindowClose")) {
        result.notImplemented();
        return;
      }
      Number id = call.argument("webViewId");
      Object instance =
          id == null ? null : registrar.getInstanceManager().getInstance(id.longValue());
      if (!(instance instanceof WebView)) {
        result.error("invalid_view", "The WebView is closed or unavailable.", null);
        return;
      }
      WebView view = (WebView) instance;
      owners.put(view, this);
      if (call.method.equals("setContentRules") || call.method.equals("configureNetworkBridge")) {
        try {
          result.success(call.method.equals("setContentRules") ? NetworkControl.configure(view, call.argument("rules")) :
              ResourceBridge.configureNetwork(view, messenger, (Map<?, ?>) call.arguments));
        } catch (RuntimeException error) { result.error("network_configuration", error.toString(), null); }
        return;
      }
      if (call.method.equals("createArchive")) {
        if (!"mhtml".equals(call.argument("format"))) { result.success(null); return; }
        PendingArchive pending = null;
        try {
          File file = File.createTempFile("webview-all-archive-", ".mhtml", registrar.getContext().getCacheDir());
          pending = new PendingArchive(view, file, result);
          PendingArchive request = pending;
          view.saveWebArchive(file.getAbsolutePath(), false, request::complete);
        } catch (java.io.IOException | RuntimeException error) {
          if (pending != null) pending.fail("archive_failed", error.toString());
          else result.error("archive_failed", error.toString(), null);
        }
        return;
      }
      if (call.method.equals("printPage")) {
        String name = call.argument("jobName");
        if (!(registrar.getContext() instanceof Activity) || name == null || name.trim().isEmpty() || name.length() > 256 || printJobs.size() >= 32) {
          result.error("print_unavailable", "Printing requires an attached Activity, a valid name and an available job slot. Dispose old job handles.", null); return;
        }
        try {
          PrintManager manager = (PrintManager) registrar.getContext().getSystemService(Context.PRINT_SERVICE);
          if (manager == null) { result.success(null); return; }
          PrintJob job = manager.print(name, view.createPrintDocumentAdapter(name), null);
          String jobId = UUID.randomUUID().toString(); printJobs.put(jobId, job);
          Map<String, Object> value = new HashMap<>();
          value.put("jobId", jobId); value.put("state", printState(job));
          value.put("canQuery", true); value.put("canCancel", true);
          result.success(value);
        } catch (RuntimeException error) { result.error("print_failed", error.toString(), null); }
        return;
      }
      if (call.method.equals("clearNavigationHistory")) {
        view.clearHistory(); result.success(true); return;
      }
      if (call.method.equals("saveNavigationState")) {
        if (navigationStates.size() >= 16) {
          result.error("snapshot_limit", "Dispose unused navigation snapshots before saving another.", null); return;
        }
        Bundle state = new Bundle();
        if (view.saveState(state) == null) { result.success(null); return; }
        String stateId = UUID.randomUUID().toString();
        navigationStates.put(stateId, new NavigationState(view, state));
        result.success(stateId); return;
      }
      if (call.method.equals("restoreNavigationState")) {
        NavigationState state = navigationStates.get((String) call.argument("stateId"));
        if (state == null || !state.matches(view)) { result.success(false); return; }
        if (usedTargets.containsKey(view) || view.copyBackForwardList().getSize() > 0) {
          result.error("restore_requires_new_view", "Android restoreState requires a fresh WebView that has not started navigation. Create a related session in the same profile before restoring. The current page was retained.", null); return;
        }
        boolean restored = view.restoreState(new Bundle(state.data)) != null;
        if (restored) usedTargets.put(view, true);
        result.success(restored);
        return;
      }
      if (call.method.equals("setNewWindowDelegateEnabled")
          || call.method.equals("observeProcessFailures")
          || call.method.equals("observeWindowClose")) {
        owners.put(view, this);
        if (call.method.equals("setNewWindowDelegateEnabled")) {
          enabled.put(view, Boolean.TRUE.equals(call.argument("enabled")));
          if (!Boolean.TRUE.equals(enabled.get(view))) {
            for (PendingWindow request : new ArrayList<>(windows.values())) {
              if (request.parent.get() == view)
                request.finish(null);
            }
          }
        }
        result.success(null);
        return;
      }
      Bitmap bitmap = null;
      try {
        int width = view.getWidth(), height = view.getHeight();
        if (width <= 0 || height <= 0 || (long) width * height > MAX_BYTES / 4) {
          result.error(
              "capture_size", "The viewport is empty or exceeds the capture size limit.", null);
          return;
        }
        bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888);
        view.draw(new Canvas(bitmap));
        ByteArrayOutputStream bytes = new ByteArrayOutputStream();
        if (!bitmap.compress(Bitmap.CompressFormat.PNG, 100, bytes) || bytes.size() > MAX_BYTES) {
          result.error("capture_failed",
              "The native snapshot could not be encoded within the size limit.", null);
          return;
        }
        result.success(bytes.toByteArray());
      } catch (Exception error) {
        result.error("capture_failed", error.toString(), null);
      } finally {
        if (bitmap != null)
          bitmap.recycle();
      }
    });
  }

  void close() {
    for (PendingArchive request : new ArrayList<>(archives.values())) request.fail("archive_cancelled", "The Flutter engine was detached.");
    navigationStates.clear();
    printJobs.clear();
    for (PendingWindow request : new ArrayList<>(windows.values())) request.finish(null);
    for (WebView view : new ArrayList<>(owners.keySet())) {
      if (owners.get(view) == this)
        owners.remove(view);
    }
    enabled.clear();
    channel.setMethodCallHandler(null);
  }
}

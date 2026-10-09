#include "plugin/webview_all_linux_plugin_private.h"
#include "common/method_channel_utils.h"

#include <dlfcn.h>

// The bundle folder, beside this plugin's library, that holds only the channel
// extension. Must match the extension's install destination in
// `linux/CMakeLists.txt`.
constexpr const gchar* kWebExtensionsDirectoryName =
    "webview_all_linux_web_extensions";

// Points the default web context, which every view uses, at the extension
// folder beside this plugin's library, once per process.
//
// WebKitGTK loads every library in that folder into the web process and
// accepts the folder only before the context loads anything. When the lookup
// fails, or the folder is missing (logged as a warning), no channel object
// exists, so channels deliver nothing.
static void set_default_web_extensions_directory() {
  static gboolean configured = FALSE;
  if (configured) {
    return;
  }
  configured = TRUE;

  // A file-local anchor: no other library can interpose it.
  Dl_info info;
  if (dladdr(reinterpret_cast<void*>(&set_default_web_extensions_directory),
             &info) == 0 ||
      info.dli_fname == nullptr) {
    return;
  }

  gchar* plugin_directory = g_path_get_dirname(info.dli_fname);
  gchar* extensions_directory =
      g_build_filename(plugin_directory, kWebExtensionsDirectoryName, nullptr);
  if (g_file_test(extensions_directory, G_FILE_TEST_IS_DIR)) {
    webkit_web_context_set_web_extensions_directory(
        webkit_web_context_get_default(), extensions_directory);
  } else {
    g_warning("webview_all_linux: no channel extension folder at %s, so "
              "JavaScript channels deliver nothing",
              extensions_directory);
  }
  g_free(extensions_directory);
  g_free(plugin_directory);
}

G_DEFINE_TYPE(WebviewAllLinuxPlugin,
              webview_all_linux_plugin,
              g_object_get_type())

static void webview_all_linux_plugin_dispose(GObject* object) {
  WebviewAllLinuxPlugin* self =
      reinterpret_cast<WebviewAllLinuxPlugin*>(object);

  self->disposing = TRUE;
  if (self->webviews != nullptr) {
    g_hash_table_destroy(self->webviews);
    self->webviews = nullptr;
  }
  detach_linux_webview_host(self);
  g_clear_object(&self->root_channel);
  g_clear_object(&self->registrar);

  G_OBJECT_CLASS(webview_all_linux_plugin_parent_class)->dispose(object);
}

static void webview_all_linux_plugin_class_init(
    WebviewAllLinuxPluginClass* klass) {
  G_OBJECT_CLASS(klass)->dispose = webview_all_linux_plugin_dispose;
}

static void webview_all_linux_plugin_init(WebviewAllLinuxPlugin* self) {
  self->next_webview_id = 1;
  self->webviews = g_hash_table_new_full(g_direct_hash, g_direct_equal, nullptr,
                                         destroy_linux_webview);
}

void webview_all_linux_plugin_register_with_registrar(
    FlPluginRegistrar* registrar) {
  set_default_web_extensions_directory();

  WebviewAllLinuxPlugin* plugin = reinterpret_cast<WebviewAllLinuxPlugin*>(
      g_object_new(webview_all_linux_plugin_get_type(), nullptr));

  plugin->registrar = FL_PLUGIN_REGISTRAR(g_object_ref(registrar));
  plugin->root_channel = fl_method_channel_new(
      fl_plugin_registrar_get_messenger(registrar),
      "com.abandoft.webview_all_linux", method_codec());

  fl_method_channel_set_method_call_handler(plugin->root_channel,
                                            root_method_call_cb,
                                            g_object_ref(plugin),
                                            g_object_unref);
  g_object_unref(plugin);
}

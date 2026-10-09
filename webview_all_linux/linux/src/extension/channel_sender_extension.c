// A WebKitGTK web-process extension that defines every JavaScript channel
// object. WebKitGTK's UI-process API (`script-message-received`) names no
// sender for a script message, so the plugin registers no script message
// handler for a channel: a page reaches a channel only through the object
// this extension defines. Each message carries the URL and main-frame flag of
// the document whose window holds the object, captured when that document
// started and read here in the web process.
//
// The plugin sends each page its view's channel names as the user message
// `webview-all-channel-names`: when the page asks for them on creation, and on
// every channel change. The main world's `window-object-cleared` then defines
// them before any script of a new document runs, an app's document-start user
// scripts included. A document that starts before the names arrive gets them
// from the plugin's channel script, which hands them to
// `webviewAllDefineChannels` at document start in the isolated world
// `webview-all-channels`; that call defines only the names the document lacks.
#include <webkit2/webkit-web-extension.h>

// Must match `kChannelScriptWorldName` in `webview_javascript.cc`.
static const char kChannelScriptWorldName[] = "webview-all-channels";

// Must match `kChannelMessageName` in `webview_javascript.cc`.
static const char kChannelMessageName[] = "webview-all-channel-message";

// Must match `kChannelNamesMessageName` in `webview_javascript.cc`.
static const char kChannelNamesMessageName[] = "webview-all-channel-names";

// Must match `kChannelNamesRequestName` in `webview_javascript.cc`.
static const char kChannelNamesRequestName[] =
    "webview-all-channel-names-request";

// A page's channel names: a NULL-terminated string array.
static const char kPageChannelNamesKey[] = "webview-all-channel-names";

// The names defined for a frame's current document: a set of strings.
static const char kFrameDefinedChannelsKey[] = "webview-all-defined-channels";

// Evaluated in a document's main world, usually from window-object-cleared
// before any script of the new document runs, so `String` is normally the
// realm's own; in a reused about:blank window, where window-object-cleared
// does not fire, a same-origin predecessor's script may already have
// replaced it. Yields the function that builds one channel object around a
// sender function. `String(message)` throws to the caller when the
// conversion fails, and then nothing is sent.
static const char kChannelObjectFactorySource[] =
    "(function (String) {"
    "  'use strict';"
    "  return function (send) {"
    "    return {"
    "      postMessage: function postMessage(message) {"
    "        var text = String(message);"
    "        send(text, text.length);"
    "      }"
    "    };"
    "  };"
    "})(String)";

static WebKitWebExtension *web_extension;

// The isolated world of the plugin's channel script; kept for the process's
// life.
static WebKitScriptWorld *channel_world;

// The frame and page whose isolated channel world got a new window object.
typedef struct {
  GWeakRef frame;
  guint64 page_id;
} ChannelFrame;

// What every message of one channel in one document reports.
typedef struct {
  gchar *channel;
  // NULL when the document's origin is opaque.
  gchar *document_url;
  guint64 page_id;
  gboolean is_main_frame;
} ChannelSender;

static void channel_frame_free(gpointer data) {
  ChannelFrame *target = data;
  g_weak_ref_clear(&target->frame);
  g_free(target);
}

static void channel_sender_free(gpointer data) {
  ChannelSender *sender = data;
  g_free(sender->channel);
  g_free(sender->document_url);
  g_free(sender);
}

// Returns a copy of `value`'s string, or NULL when `value` is not a string or
// its text is empty or not valid UTF-8.
static gchar *dup_string(JSCValue *value) {
  if (!jsc_value_is_string(value)) {
    return NULL;
  }
  gchar *text = jsc_value_to_string(value);
  if (text != NULL && (*text == '\0' || !g_utf8_validate(text, -1, NULL))) {
    g_clear_pointer(&text, g_free);
  }
  return text;
}

// Whether `text`, the UTF-8 form of a JavaScript string `utf16_length` code
// units long, kept all of them. The conversion loses an unpaired surrogate and
// a C string ends at U+0000; either way the text would arrive changed.
static gboolean holds_every_code_unit(const gchar *text, double utf16_length) {
  if (!g_utf8_validate(text, -1, NULL)) {
    return FALSE;
  }
  gint64 units = 0;
  for (const gchar *cursor = text; *cursor != '\0';
       cursor = g_utf8_next_char(cursor)) {
    units += g_utf8_get_char(cursor) > 0xFFFF ? 2 : 1;
  }
  return (double)units == utf16_length;
}

// The sender function a channel object closes over: `postMessage` calls it
// with the converted text and that text's length in UTF-16 code units.
static void send_channel_message(GPtrArray *args, gpointer user_data) {
  ChannelSender *sender = user_data;
  if (args->len != 2) {
    return;
  }
  JSCValue *text_value = g_ptr_array_index(args, 0);
  JSCValue *length_value = g_ptr_array_index(args, 1);
  if (!jsc_value_is_string(text_value) || !jsc_value_is_number(length_value)) {
    return;
  }

  gchar *text = jsc_value_to_string(text_value);
  if (text == NULL ||
      !holds_every_code_unit(text, jsc_value_to_double(length_value))) {
    g_free(text);
    return;
  }

  WebKitWebPage *page =
      webkit_web_extension_get_page(web_extension, sender->page_id);
  if (page != NULL) {
    WebKitUserMessage *message = webkit_user_message_new(
        kChannelMessageName,
        g_variant_new("(ssmsb)", sender->channel, text, sender->document_url,
                      sender->is_main_frame));
    webkit_web_page_send_message_to_view(page, message, NULL, NULL, NULL);
  }
  g_free(text);
}

// Returns the URL of the document whose isolated world `context` belongs to,
// or NULL when the document's origin is opaque (a sandboxed document, HTML
// loaded with no base URL): such an origin serializes as "null". Page script
// cannot reach the isolated world, so it cannot replace what this reads.
static gchar *read_document_url(JSCContext *context) {
  JSCValue *global = jsc_context_get_global_object(context);
  JSCValue *origin = jsc_value_object_get_property(global, "origin");
  JSCValue *document = jsc_value_object_get_property(global, "document");
  gchar *serialized_origin = dup_string(origin);
  gchar *url = NULL;
  if (serialized_origin != NULL && g_strcmp0(serialized_origin, "null") != 0 &&
      jsc_value_is_object(document)) {
    JSCValue *url_value = jsc_value_object_get_property(document, "URL");
    url = dup_string(url_value);
    g_object_unref(url_value);
  }
  g_free(serialized_origin);
  g_object_unref(document);
  g_object_unref(origin);
  g_object_unref(global);
  return url;
}

// Defines `window[sender->channel]` in the main world of `page_context` as a
// writable, configurable property holding a channel object built by
// `factory`. Takes ownership of `sender`.
static void define_channel(JSCContext *page_context, JSCValue *factory,
                           ChannelSender *sender) {
  JSCValue *send = jsc_value_new_function_variadic(
      page_context, NULL, G_CALLBACK(send_channel_message), sender,
      channel_sender_free, G_TYPE_NONE);
  JSCValue *channel_object =
      jsc_value_function_call(factory, JSC_TYPE_VALUE, send, G_TYPE_NONE);
  if (jsc_context_get_exception(page_context) == NULL &&
      jsc_value_is_object(channel_object)) {
    JSCValue *global = jsc_context_get_global_object(page_context);
    jsc_value_object_define_property_data(
        global, sender->channel,
        JSC_VALUE_PROPERTY_CONFIGURABLE | JSC_VALUE_PROPERTY_ENUMERABLE |
            JSC_VALUE_PROPERTY_WRITABLE,
        channel_object);
    g_object_unref(global);
  }
  // A name the window holds as non-configurable keeps its existing value.
  jsc_context_clear_exception(page_context);
  g_object_unref(channel_object);
  g_object_unref(send);
}

// Defines each of `names` that `frame`'s current document lacks, in that
// document's main world. Every message reports that document's URL and
// main-frame flag, read now.
static void define_frame_channels(WebKitFrame *frame, guint64 page_id,
                                  const gchar *const *names) {
  // Getting the main world's context can emit its `window-object-cleared`
  // first, which starts the document's record of defined names.
  JSCContext *page_context = webkit_frame_get_js_context(frame);
  GHashTable *defined =
      g_object_get_data(G_OBJECT(frame), kFrameDefinedChannelsKey);
  if (defined == NULL) {
    defined = g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL);
    g_object_set_data_full(G_OBJECT(frame), kFrameDefinedChannelsKey, defined,
                           (GDestroyNotify)g_hash_table_unref);
  }

  JSCContext *channel_context =
      webkit_frame_get_js_context_for_script_world(frame, channel_world);
  gchar *document_url = read_document_url(channel_context);
  gboolean is_main_frame = webkit_frame_is_main_frame(frame);
  JSCValue *factory =
      jsc_context_evaluate(page_context, kChannelObjectFactorySource, -1);
  if (jsc_context_get_exception(page_context) == NULL &&
      jsc_value_is_function(factory)) {
    for (const gchar *const *name = names; *name != NULL; ++name) {
      if (g_hash_table_contains(defined, *name)) {
        continue;
      }
      g_hash_table_add(defined, g_strdup(*name));
      ChannelSender *sender = g_new0(ChannelSender, 1);
      sender->channel = g_strdup(*name);
      sender->document_url = g_strdup(document_url);
      sender->page_id = page_id;
      sender->is_main_frame = is_main_frame;
      define_channel(page_context, factory, sender);
    }
  }
  jsc_context_clear_exception(page_context);
  g_object_unref(factory);
  g_free(document_url);
  g_object_unref(channel_context);
  g_object_unref(page_context);
}

// A new document's main-world window object: forgets the names defined for the
// previous document and defines the page's channel names before any script
// of this document runs.
static void on_main_world_cleared(WebKitScriptWorld *world,
                                  WebKitWebPage *page, WebKitFrame *frame,
                                  gpointer user_data) {
  g_object_set_data_full(
      G_OBJECT(frame), kFrameDefinedChannelsKey,
      g_hash_table_new_full(g_str_hash, g_str_equal, g_free, NULL),
      (GDestroyNotify)g_hash_table_unref);
  const gchar *const *names =
      g_object_get_data(G_OBJECT(page), kPageChannelNamesKey);
  if (names != NULL) {
    define_frame_channels(frame, webkit_web_page_get_id(page), names);
  }
}

// `webviewAllDefineChannels(names)`: the plugin's channel script hands the
// view's channel names here from the isolated world, at document start.
static void define_channels(GPtrArray *args, gpointer user_data) {
  ChannelFrame *target = user_data;
  if (args->len != 1 || !jsc_value_is_array(g_ptr_array_index(args, 0))) {
    return;
  }
  WebKitFrame *frame = g_weak_ref_get(&target->frame);
  if (frame == NULL) {
    return;
  }

  JSCValue *array = g_ptr_array_index(args, 0);
  JSCValue *length = jsc_value_object_get_property(array, "length");
  guint count = (guint)jsc_value_to_double(length);
  GPtrArray *names = g_ptr_array_new_with_free_func(g_free);
  for (guint index = 0; index < count; ++index) {
    JSCValue *name = jsc_value_object_get_property_at_index(array, index);
    gchar *channel = dup_string(name);
    if (channel != NULL) {
      g_ptr_array_add(names, channel);
    }
    g_object_unref(name);
  }
  g_ptr_array_add(names, NULL);

  define_frame_channels(frame, target->page_id,
                        (const gchar *const *)names->pdata);
  g_ptr_array_unref(names);
  g_object_unref(length);
  g_object_unref(frame);
}

// Installs `webviewAllDefineChannels` in a frame's isolated channel world,
// which no page script can reach.
static void on_channel_world_cleared(WebKitScriptWorld *world,
                                     WebKitWebPage *page, WebKitFrame *frame,
                                     gpointer user_data) {
  ChannelFrame *target = g_new0(ChannelFrame, 1);
  g_weak_ref_init(&target->frame, frame);
  target->page_id = webkit_web_page_get_id(page);

  JSCContext *context =
      webkit_frame_get_js_context_for_script_world(frame, world);
  JSCValue *function = jsc_value_new_function_variadic(
      context, "webviewAllDefineChannels", G_CALLBACK(define_channels), target,
      channel_frame_free, G_TYPE_NONE);
  jsc_context_set_value(context, "webviewAllDefineChannels", function);
  g_object_unref(function);
  g_object_unref(context);
}

// Keeps the channel names the plugin sends this page for its next documents.
static gboolean on_page_user_message_received(WebKitWebPage *page,
                                              WebKitUserMessage *message,
                                              gpointer user_data) {
  if (g_strcmp0(webkit_user_message_get_name(message),
                kChannelNamesMessageName) != 0) {
    return FALSE;
  }
  GVariant *parameters = webkit_user_message_get_parameters(message);
  if (parameters != NULL &&
      g_variant_is_of_type(parameters, G_VARIANT_TYPE_STRING_ARRAY)) {
    g_object_set_data_full(G_OBJECT(page), kPageChannelNamesKey,
                           g_variant_dup_strv(parameters, NULL),
                           (GDestroyNotify)g_strfreev);
  }
  return TRUE;
}

// Asks the plugin for the page's channel names. The plugin answers at once
// with a names message, ahead of its answers for the page's first navigation;
// the channel script covers a document that starts before the names arrive.
static void on_page_created(WebKitWebExtension *extension, WebKitWebPage *page,
                            gpointer user_data) {
  g_signal_connect(page, "user-message-received",
                   G_CALLBACK(on_page_user_message_received), NULL);
  webkit_web_page_send_message_to_view(
      page, webkit_user_message_new(kChannelNamesRequestName, NULL), NULL,
      NULL, NULL);
}

G_MODULE_EXPORT void
webkit_web_extension_initialize(WebKitWebExtension *extension) {
  web_extension = extension;
  // Created before any page reaches this process, so the plugin's channel
  // script, which names this world, runs in it.
  channel_world = webkit_script_world_new_with_name(kChannelScriptWorldName);
  g_signal_connect(channel_world, "window-object-cleared",
                   G_CALLBACK(on_channel_world_cleared), NULL);
  g_signal_connect(webkit_script_world_get_default(), "window-object-cleared",
                   G_CALLBACK(on_main_world_cleared), NULL);
  g_signal_connect(extension, "page-created", G_CALLBACK(on_page_created),
                   NULL);
}

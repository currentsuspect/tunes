#include "mpris.h"

#include <gio/gio.h>

#include <unistd.h>

#include <cstdlib>
#include <string>

// What the app last reported, and when, so Position can run on between
// reports the way the playhead does.
namespace {

const gchar kIntrospection[] = R"(
<node>
  <interface name="org.mpris.MediaPlayer2">
    <method name="Raise"/>
    <method name="Quit"/>
    <property name="CanQuit" type="b" access="read"/>
    <property name="CanRaise" type="b" access="read"/>
    <property name="HasTrackList" type="b" access="read"/>
    <property name="Identity" type="s" access="read"/>
    <property name="DesktopEntry" type="s" access="read"/>
    <property name="SupportedUriSchemes" type="as" access="read"/>
    <property name="SupportedMimeTypes" type="as" access="read"/>
  </interface>
  <interface name="org.mpris.MediaPlayer2.Player">
    <method name="Next"/>
    <method name="Previous"/>
    <method name="Pause"/>
    <method name="PlayPause"/>
    <method name="Stop"/>
    <method name="Play"/>
    <method name="Seek"><arg direction="in" name="Offset" type="x"/></method>
    <method name="SetPosition">
      <arg direction="in" name="TrackId" type="o"/>
      <arg direction="in" name="Position" type="x"/>
    </method>
    <method name="OpenUri"><arg direction="in" name="Uri" type="s"/></method>
    <signal name="Seeked"><arg name="Position" type="x"/></signal>
    <property name="PlaybackStatus" type="s" access="read"/>
    <property name="LoopStatus" type="s" access="readwrite"/>
    <property name="Rate" type="d" access="readwrite"/>
    <property name="Shuffle" type="b" access="readwrite"/>
    <property name="Metadata" type="a{sv}" access="read"/>
    <property name="Volume" type="d" access="readwrite"/>
    <property name="Position" type="x" access="read"/>
    <property name="MinimumRate" type="d" access="read"/>
    <property name="MaximumRate" type="d" access="read"/>
    <property name="CanGoNext" type="b" access="read"/>
    <property name="CanGoPrevious" type="b" access="read"/>
    <property name="CanPlay" type="b" access="read"/>
    <property name="CanPause" type="b" access="read"/>
    <property name="CanSeek" type="b" access="read"/>
    <property name="CanControl" type="b" access="read"/>
  </interface>
</node>)";

const gchar kPath[] = "/org/mpris/MediaPlayer2";
const gchar kRoot[] = "org.mpris.MediaPlayer2";
const gchar kPlayer[] = "org.mpris.MediaPlayer2.Player";

struct State {
  std::string status = "Stopped";
  std::string loop = "None";
  bool shuffle = false;
  bool can_next = false;
  bool can_previous = false;
  bool has_track = false;
  std::string track_id = "/org/mpris/MediaPlayer2/TrackList/NoTrack";
  std::string title;
  std::string artist;
  std::string album;
  std::string art_url;
  gint64 length_us = 0;
  gint64 position_us = 0;
  gint64 reported_at = 0;  // g_get_monotonic_time() of position_us
  double rate = 1.0;
};

GDBusConnection* g_connection = nullptr;
GDBusNodeInfo* g_node = nullptr;
FlMethodChannel* g_channel = nullptr;
GtkWindow* g_window = nullptr;
State g_state;

gint64 current_position() {
  if (g_state.status != "Playing") return g_state.position_us;
  gint64 ran = g_get_monotonic_time() - g_state.reported_at;
  gint64 at = g_state.position_us + static_cast<gint64>(ran * g_state.rate);
  if (g_state.length_us > 0 && at > g_state.length_us) at = g_state.length_us;
  return at;
}

GVariant* metadata() {
  GVariantBuilder b;
  g_variant_builder_init(&b, G_VARIANT_TYPE("a{sv}"));
  g_variant_builder_add(&b, "{sv}", "mpris:trackid",
                        g_variant_new_object_path(g_state.track_id.c_str()));
  if (g_state.has_track) {
    if (g_state.length_us > 0) {
      g_variant_builder_add(&b, "{sv}", "mpris:length",
                            g_variant_new_int64(g_state.length_us));
    }
    g_variant_builder_add(&b, "{sv}", "xesam:title",
                          g_variant_new_string(g_state.title.c_str()));
    const gchar* artists[] = {g_state.artist.c_str(), nullptr};
    g_variant_builder_add(&b, "{sv}", "xesam:artist",
                          g_variant_new_strv(artists, -1));
    g_variant_builder_add(&b, "{sv}", "xesam:album",
                          g_variant_new_string(g_state.album.c_str()));
    if (!g_state.art_url.empty()) {
      g_variant_builder_add(&b, "{sv}", "mpris:artUrl",
                            g_variant_new_string(g_state.art_url.c_str()));
    }
  }
  return g_variant_builder_end(&b);
}

GVariant* get_property(GDBusConnection*, const gchar*, const gchar*,
                       const gchar* iface, const gchar* name, GError**,
                       gpointer) {
  if (g_strcmp0(iface, kRoot) == 0) {
    if (g_strcmp0(name, "CanQuit") == 0) return g_variant_new_boolean(TRUE);
    if (g_strcmp0(name, "CanRaise") == 0) return g_variant_new_boolean(TRUE);
    if (g_strcmp0(name, "HasTrackList") == 0)
      return g_variant_new_boolean(FALSE);
    if (g_strcmp0(name, "Identity") == 0) return g_variant_new_string("Tunes");
    if (g_strcmp0(name, "DesktopEntry") == 0)
      return g_variant_new_string(APPLICATION_ID);
    if (g_strcmp0(name, "SupportedUriSchemes") == 0 ||
        g_strcmp0(name, "SupportedMimeTypes") == 0)
      return g_variant_new_strv(nullptr, 0);
    return nullptr;
  }
  if (g_strcmp0(name, "PlaybackStatus") == 0)
    return g_variant_new_string(g_state.status.c_str());
  if (g_strcmp0(name, "LoopStatus") == 0)
    return g_variant_new_string(g_state.loop.c_str());
  if (g_strcmp0(name, "Rate") == 0) return g_variant_new_double(g_state.rate);
  if (g_strcmp0(name, "Shuffle") == 0)
    return g_variant_new_boolean(g_state.shuffle);
  if (g_strcmp0(name, "Metadata") == 0) return metadata();
  if (g_strcmp0(name, "Volume") == 0) return g_variant_new_double(1.0);
  if (g_strcmp0(name, "Position") == 0)
    return g_variant_new_int64(current_position());
  if (g_strcmp0(name, "MinimumRate") == 0) return g_variant_new_double(0.5);
  if (g_strcmp0(name, "MaximumRate") == 0) return g_variant_new_double(2.0);
  if (g_strcmp0(name, "CanGoNext") == 0)
    return g_variant_new_boolean(g_state.can_next);
  if (g_strcmp0(name, "CanGoPrevious") == 0)
    return g_variant_new_boolean(g_state.can_previous);
  if (g_strcmp0(name, "CanPlay") == 0 || g_strcmp0(name, "CanPause") == 0 ||
      g_strcmp0(name, "CanSeek") == 0)
    return g_variant_new_boolean(g_state.has_track);
  if (g_strcmp0(name, "CanControl") == 0) return g_variant_new_boolean(TRUE);
  return nullptr;
}

// Passes a command to the app: {"name": ..., "value": ...}.
void command(const gchar* name, FlValue* value = nullptr) {
  if (g_channel == nullptr) return;
  g_autoptr(FlValue) args = fl_value_new_map();
  fl_value_set_string_take(args, "name", fl_value_new_string(name));
  if (value != nullptr) fl_value_set_string(args, "value", value);
  fl_method_channel_invoke_method(g_channel, "command", args, nullptr, nullptr,
                                  nullptr);
}

gboolean set_property(GDBusConnection*, const gchar*, const gchar*,
                      const gchar*, const gchar* name, GVariant* value,
                      GError**, gpointer) {
  if (g_strcmp0(name, "Shuffle") == 0) {
    g_autoptr(FlValue) v = fl_value_new_bool(g_variant_get_boolean(value));
    command("shuffle", v);
  } else if (g_strcmp0(name, "LoopStatus") == 0) {
    g_autoptr(FlValue) v =
        fl_value_new_string(g_variant_get_string(value, nullptr));
    command("loop", v);
  }
  // Rate and Volume belong to the app's own controls; accepted, not applied.
  return TRUE;
}

void method_call(GDBusConnection*, const gchar*, const gchar*, const gchar*,
                 const gchar* method, GVariant* params,
                 GDBusMethodInvocation* invocation, gpointer) {
  if (g_strcmp0(method, "Raise") == 0) {
    if (g_window != nullptr) gtk_window_present(g_window);
  } else if (g_strcmp0(method, "Quit") == 0) {
    if (g_window != nullptr) gtk_window_close(g_window);
  } else if (g_strcmp0(method, "Play") == 0) {
    command("play");
  } else if (g_strcmp0(method, "Pause") == 0) {
    command("pause");
  } else if (g_strcmp0(method, "PlayPause") == 0) {
    command("playPause");
  } else if (g_strcmp0(method, "Stop") == 0) {
    command("pause");
  } else if (g_strcmp0(method, "Next") == 0) {
    command("next");
  } else if (g_strcmp0(method, "Previous") == 0) {
    command("previous");
  } else if (g_strcmp0(method, "Seek") == 0) {
    gint64 offset = 0;
    g_variant_get(params, "(x)", &offset);
    gint64 to = current_position() + offset;
    if (to < 0) to = 0;
    g_autoptr(FlValue) v = fl_value_new_int(to);
    command("seek", v);
  } else if (g_strcmp0(method, "SetPosition") == 0) {
    const gchar* track = nullptr;
    gint64 to = 0;
    g_variant_get(params, "(&ox)", &track, &to);
    // Only for the song it was asked about, as the spec says.
    if (g_strcmp0(track, g_state.track_id.c_str()) == 0 && to >= 0 &&
        (g_state.length_us == 0 || to <= g_state.length_us)) {
      g_autoptr(FlValue) v = fl_value_new_int(to);
      command("seek", v);
    }
  }
  g_dbus_method_invocation_return_value(invocation, nullptr);
}

const GDBusInterfaceVTable kVTable = {method_call, get_property, set_property,
                                      {nullptr}};

void emit_changed(const gchar* iface, GVariantBuilder* changed) {
  if (g_connection == nullptr) return;
  g_dbus_connection_emit_signal(
      g_connection, nullptr, kPath, "org.freedesktop.DBus.Properties",
      "PropertiesChanged",
      g_variant_new("(sa{sv}as)", iface, changed, nullptr), nullptr);
}

std::string str(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_STRING
             ? fl_value_get_string(v)
             : "";
}

gint64 num(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_INT
             ? fl_value_get_int(v)
             : 0;
}

bool flag(FlValue* map, const char* key) {
  FlValue* v = fl_value_lookup_string(map, key);
  return v != nullptr && fl_value_get_type(v) == FL_VALUE_TYPE_BOOL &&
         fl_value_get_bool(v);
}

// The app's report of what is playing: emits what changed, and Seeked when
// the position moved other than by playing on.
void update(FlValue* map) {
  State next;
  next.status = str(map, "status");
  next.loop = str(map, "loop");
  next.shuffle = flag(map, "shuffle");
  next.can_next = flag(map, "canNext");
  next.can_previous = flag(map, "canPrevious");
  next.title = str(map, "title");
  next.artist = str(map, "artist");
  next.album = str(map, "album");
  next.art_url = str(map, "artUrl");
  next.length_us = num(map, "lengthUs");
  next.position_us = num(map, "positionUs");
  next.reported_at = g_get_monotonic_time();
  std::string id = str(map, "trackId");
  next.has_track = !id.empty();
  next.track_id = next.has_track ? "/com/currentsuspect/tunes/track/" + id
                                 : "/org/mpris/MediaPlayer2/TrackList/NoTrack";

  bool track_changed = next.track_id != g_state.track_id ||
                       next.title != g_state.title ||
                       next.art_url != g_state.art_url ||
                       next.length_us != g_state.length_us;
  gint64 expected = current_position();
  bool jumped = !track_changed &&
                std::llabs(next.position_us - expected) > 1500000;

  GVariantBuilder changed;
  g_variant_builder_init(&changed, G_VARIANT_TYPE("a{sv}"));
  bool any = false;
  auto add = [&](const char* name, bool differs) {
    if (!differs) return;
    any = true;
    g_variant_builder_add(&changed, "{sv}", name,
                          get_property(nullptr, nullptr, nullptr, kPlayer,
                                       name, nullptr, nullptr));
  };
  State before = g_state;
  g_state = next;
  add("PlaybackStatus", before.status != next.status);
  add("LoopStatus", before.loop != next.loop);
  add("Shuffle", before.shuffle != next.shuffle);
  add("CanGoNext", before.can_next != next.can_next);
  add("CanGoPrevious", before.can_previous != next.can_previous);
  add("CanPlay", before.has_track != next.has_track);
  add("CanPause", before.has_track != next.has_track);
  add("CanSeek", before.has_track != next.has_track);
  add("Metadata", track_changed);
  if (any) {
    emit_changed(kPlayer, &changed);
  } else {
    g_variant_builder_clear(&changed);
  }
  if (jumped && g_connection != nullptr) {
    g_dbus_connection_emit_signal(g_connection, nullptr, kPath, kPlayer,
                                  "Seeked",
                                  g_variant_new("(x)", next.position_us),
                                  nullptr);
  }
}

void on_method(FlMethodChannel*, FlMethodCall* call, gpointer) {
  if (g_strcmp0(fl_method_call_get_name(call), "update") == 0) {
    FlValue* args = fl_method_call_get_args(call);
    if (args != nullptr && fl_value_get_type(args) == FL_VALUE_TYPE_MAP) {
      update(args);
    }
    fl_method_call_respond_success(call, nullptr, nullptr);
    return;
  }
  fl_method_call_respond_not_implemented(call, nullptr);
}

void on_name_lost(GDBusConnection*, const gchar* name, gpointer) {
  // Another copy of Tunes holds the plain name: this one goes by its pid.
  if (g_str_has_suffix(name, ".tunes")) {
    g_autofree gchar* own =
        g_strdup_printf("org.mpris.MediaPlayer2.tunes.instance%d", getpid());
    g_bus_own_name(G_BUS_TYPE_SESSION, own, G_BUS_NAME_OWNER_FLAGS_NONE,
                   nullptr, nullptr, nullptr, nullptr, nullptr);
  }
}

void on_bus(GDBusConnection* connection, const gchar*, gpointer) {
  g_connection = connection;
  for (int i = 0; g_node->interfaces[i] != nullptr; i++) {
    g_dbus_connection_register_object(connection, kPath, g_node->interfaces[i],
                                      &kVTable, nullptr, nullptr, nullptr);
  }
}

}  // namespace

void mpris_start(FlView* view, GtkWindow* window) {
  g_window = window;
  g_node = g_dbus_node_info_new_for_xml(kIntrospection, nullptr);
  if (g_node == nullptr) return;
  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_channel = fl_method_channel_new(fl_engine_get_binary_messenger(engine),
                                    "tunes/mpris", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(g_channel, on_method, nullptr,
                                            nullptr);
  // A second copy running takes a name of its own rather than none
  // (on_name_lost).
  g_bus_own_name(G_BUS_TYPE_SESSION, "org.mpris.MediaPlayer2.tunes",
                 G_BUS_NAME_OWNER_FLAGS_DO_NOT_QUEUE, on_bus, nullptr,
                 on_name_lost, nullptr, nullptr);
}

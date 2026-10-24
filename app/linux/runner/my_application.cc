#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"
#include "mpris.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

static gchar* window_size_file() {
  return g_build_filename(g_get_user_config_dir(), APPLICATION_ID,
                          "window.ini", nullptr);
}

static void load_window_size(gint* width, gint* height, gboolean* maximized) {
  g_autofree gchar* path = window_size_file();
  g_autoptr(GKeyFile) file = g_key_file_new();
  if (!g_key_file_load_from_file(file, path, G_KEY_FILE_NONE, nullptr)) return;
  gint w = g_key_file_get_integer(file, "window", "width", nullptr);
  gint h = g_key_file_get_integer(file, "window", "height", nullptr);
  // Ignore anything too small to use, a file from a broken run included.
  if (w >= 400 && h >= 300) {
    *width = w;
    *height = h;
  }
  *maximized = g_key_file_get_boolean(file, "window", "maximized", nullptr);
}

static gboolean save_window_size(GtkWidget* widget, GdkEvent*, gpointer) {
  GtkWindow* window = GTK_WINDOW(widget);
  g_autoptr(GKeyFile) file = g_key_file_new();
  gboolean maximized = gtk_window_is_maximized(window);
  if (!maximized) {
    gint w = 0, h = 0;
    gtk_window_get_size(window, &w, &h);
    g_key_file_set_integer(file, "window", "width", w);
    g_key_file_set_integer(file, "window", "height", h);
  } else {
    // Keep the size it had before it was maximised.
    g_autofree gchar* path = window_size_file();
    g_autoptr(GKeyFile) old = g_key_file_new();
    if (g_key_file_load_from_file(old, path, G_KEY_FILE_NONE, nullptr)) {
      g_key_file_set_integer(
          file, "window", "width",
          g_key_file_get_integer(old, "window", "width", nullptr));
      g_key_file_set_integer(
          file, "window", "height",
          g_key_file_get_integer(old, "window", "height", nullptr));
    }
  }
  g_key_file_set_boolean(file, "window", "maximized", maximized);
  g_autofree gchar* path = window_size_file();
  g_autofree gchar* dir = g_path_get_dirname(path);
  g_mkdir_with_parents(dir, 0700);
  g_key_file_save_to_file(file, path, nullptr);
  return FALSE;  // Let the window close.
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));

  // Use a header bar when running in GNOME as this is the common style used
  // by applications and is the setup most users will be using (e.g. Ubuntu
  // desktop).
  // If running on X and not using GNOME then just use a traditional title bar
  // in case the window manager does more exotic layout, e.g. tiling.
  // If running on Wayland assume the header bar will work (may need changing
  // if future cases occur).
  gboolean use_header_bar = TRUE;
#ifdef GDK_WINDOWING_X11
  GdkScreen* screen = gtk_window_get_screen(window);
  if (GDK_IS_X11_SCREEN(screen)) {
    const gchar* wm_name = gdk_x11_screen_get_window_manager_name(screen);
    if (g_strcmp0(wm_name, "GNOME Shell") != 0) {
      use_header_bar = FALSE;
    }
  }
#endif
  if (use_header_bar) {
    GtkHeaderBar* header_bar = GTK_HEADER_BAR(gtk_header_bar_new());
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Tunes");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Tunes");
  }

  // The size it was last closed at (and whether it was maximised), so it
  // opens as it was left rather than at 1280x720 every time.
  gint width = 1280, height = 720;
  gboolean maximized = FALSE;
  load_window_size(&width, &height, &maximized);
  gtk_window_set_default_size(window, width, height);
  if (maximized) gtk_window_maximize(window);
  g_signal_connect(window, "delete-event", G_CALLBACK(save_window_size),
                   nullptr);

  // The logo, by name from the icon theme (tools/install-linux.sh puts it
  // there under the app id, which is also what Wayland docks match the
  // window to), else from the copy bundled with the app.
  gtk_window_set_icon_name(window, APPLICATION_ID);
  g_autofree gchar* exe = g_file_read_link("/proc/self/exe", nullptr);
  if (exe != nullptr) {
    g_autofree gchar* dir = g_path_get_dirname(exe);
    g_autofree gchar* icon = g_build_filename(
        dir, "data", "flutter_assets", "assets", "icon.png", nullptr);
    if (g_file_test(icon, G_FILE_TEST_EXISTS)) {
      gtk_window_set_icon_from_file(window, icon, nullptr);
    }
  }

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#000000");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  mpris_start(view, window);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);

  g_autoptr(GError) error = nullptr;
  if (!g_application_register(application, nullptr, &error)) {
    g_warning("Failed to register: %s", error->message);
    *exit_status = 1;
    return TRUE;
  }

  g_application_activate(application);
  *exit_status = 0;

  return TRUE;
}

// Implements GApplication::startup.
static void my_application_startup(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application startup.

  G_APPLICATION_CLASS(my_application_parent_class)->startup(application);
}

// Implements GApplication::shutdown.
static void my_application_shutdown(GApplication* application) {
  // MyApplication* self = MY_APPLICATION(object);

  // Perform any actions required at application shutdown.

  G_APPLICATION_CLASS(my_application_parent_class)->shutdown(application);
}

// Implements GObject::dispose.
static void my_application_dispose(GObject* object) {
  MyApplication* self = MY_APPLICATION(object);
  g_clear_pointer(&self->dart_entrypoint_arguments, g_strfreev);
  G_OBJECT_CLASS(my_application_parent_class)->dispose(object);
}

static void my_application_class_init(MyApplicationClass* klass) {
  G_APPLICATION_CLASS(klass)->activate = my_application_activate;
  G_APPLICATION_CLASS(klass)->local_command_line =
      my_application_local_command_line;
  G_APPLICATION_CLASS(klass)->startup = my_application_startup;
  G_APPLICATION_CLASS(klass)->shutdown = my_application_shutdown;
  G_OBJECT_CLASS(klass)->dispose = my_application_dispose;
}

static void my_application_init(MyApplication* self) {}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     G_APPLICATION_NON_UNIQUE, nullptr));
}

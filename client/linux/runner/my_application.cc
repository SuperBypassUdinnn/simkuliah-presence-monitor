#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

// Purpose: GTK application runner for the Linux desktop build.
// Data & Logic Flow: Creates the single application window hosting the Flutter view; second launches forward activation to the running instance and re-present its window (tray-hidden included), and every re-map of a previously hidden window forces a fresh Flutter frame.
// Key Components: MyApplication (unique GApplication, single window)

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  GtkWindow* first_window;
  // Window re-map bookkeeping; see window_map_cb.
  gboolean window_mapped_before;
  guint restore_size_source;
  gint restore_width;
  gint restore_height;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Returns TRUE when dart_entrypoint_arguments contains the given flag.
static gboolean my_application_has_arg(MyApplication* self, const char* flag) {
  if (self->dart_entrypoint_arguments == nullptr) {
    return FALSE;
  }
  for (int i = 0; self->dart_entrypoint_arguments[i] != nullptr; i++) {
    if (g_strcmp0(self->dart_entrypoint_arguments[i], flag) == 0) {
      return TRUE;
    }
  }
  return FALSE;
}

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  // Started with --hidden (autostart): keep the window hidden; the tray
  // icon appears and a later launcher click presents the window.
  if (!my_application_has_arg(self, "--hidden")) {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

// Called when the single application window is destroyed; keeps the
// activate guard from presenting a dangling window.
static void window_destroy_cb(GtkWidget* widget, MyApplication* self) {
  self->first_window = nullptr;
}

// Restores the window size captured before window_map_cb's one-pixel nudge.
static gboolean restore_window_size_cb(gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  self->restore_size_source = 0;
  if (self->first_window == nullptr) {
    return G_SOURCE_REMOVE;
  }
  gtk_window_resize(self->first_window, self->restore_width,
                    self->restore_height);
  return G_SOURCE_REMOVE;
}

// Forces the Flutter embedder to produce a frame after the window is mapped
// again.
//
// Hiding to the tray unmaps the window; showing it again at the same size
// leaves the Flutter view with no configure event, so the embedder never
// receives a new frame target and the window presents an empty (black)
// surface. Nothing is repainted until the user happens to resize the window.
// A one-pixel resize generates that configure event, and the size is restored
// in a later main-loop iteration because GTK coalesces resizes issued in the
// same iteration into a no-op. The first map is skipped: the window is
// allocated from scratch there, which already produces a configure event.
static void window_map_cb(GtkWidget* widget, MyApplication* self) {
  if (!self->window_mapped_before) {
    self->window_mapped_before = TRUE;
    return;
  }

  if (self->restore_size_source != 0) {
    // A second map inside the same 16 ms window restarts the restore timer
    // but keeps the size captured on the first map, so repeated maps can
    // never walk the height upward one pixel per map.
    g_source_remove(self->restore_size_source);
    self->restore_size_source = g_timeout_add(16, restore_window_size_cb, self);
    return;
  }

  gtk_window_get_size(GTK_WINDOW(widget), &self->restore_width,
                      &self->restore_height);
  if (self->restore_width <= 0 || self->restore_height <= 0) {
    return;
  }

  gtk_window_resize(GTK_WINDOW(widget), self->restore_width,
                    self->restore_height + 1);
  self->restore_size_source = g_timeout_add(16, restore_window_size_cb, self);
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);

  // Single-instance activation: with a unique GApplication, a second launch
  // forwards "activate" to the running instance (possibly hidden in the
  // tray); re-show the existing window instead of creating another Flutter
  // view. Recursively show all children (FlView) so windows waking from
  // --hidden autostart are fully mapped; window_map_cb then re-renders the
  // embedder when the window was previously hidden.
  if (self->first_window != nullptr) {
    gtk_window_deiconify(self->first_window);
    gtk_widget_show_all(GTK_WIDGET(self->first_window));
    gtk_window_present(self->first_window);
    return;
  }

  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->first_window = window;
  g_signal_connect(window, "destroy", G_CALLBACK(window_destroy_cb), self);
  g_signal_connect(window, "map", G_CALLBACK(window_map_cb), self);

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
    gtk_header_bar_set_title(header_bar, "Simkuliah Monitor");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Simkuliah Monitor");
  }

  gtk_window_set_default_size(window, 1280, 720);

  // Prefer the themed icon installed by the packaging step; this falls back
  // silently when running from a raw bundle without the icon installed.
  gtk_window_set_default_icon_name("simkuliah-monitor");

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
  if (self->restore_size_source != 0) {
    g_source_remove(self->restore_size_source);
    self->restore_size_source = 0;
  }
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

static void my_application_init(MyApplication* self) {
  self->first_window = nullptr;
  self->window_mapped_before = FALSE;
  self->restore_size_source = 0;
  self->restore_width = 0;
  self->restore_height = 0;
}

MyApplication* my_application_new() {
  // Set the program name to the application ID, which helps various systems
  // like GTK and desktop environments map this running application to its
  // corresponding .desktop file. This ensures better integration by allowing
  // the application to be recognized beyond its binary name.
  g_set_prgname(APPLICATION_ID);

  // Default (unique) GApplication flags make a second launch forward its
  // activation to the running instance; see my_application_activate. Debug
  // builds (flutter run) stay non-unique so a running installed instance
  // does not hijack the dev session.
  GApplicationFlags flags = G_APPLICATION_DEFAULT_FLAGS;
#ifndef NDEBUG
  flags = G_APPLICATION_NON_UNIQUE;
#endif
  return MY_APPLICATION(g_object_new(my_application_get_type(),
                                     "application-id", APPLICATION_ID, "flags",
                                     flags, nullptr));
}

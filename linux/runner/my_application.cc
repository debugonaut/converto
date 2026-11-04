#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  gboolean startup_probe;
  gboolean picker_open;
  gboolean first_frame;
  gboolean probe_finished;
};

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

static gboolean close_probe(gpointer data);

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  if (self->startup_probe) {
    g_printerr("CONVERTO_LINUX_FIRST_FRAME_OK\n");
    self->first_frame = TRUE;
    if (self->probe_finished) {
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, close_probe,
          g_object_ref(gtk_widget_get_toplevel(GTK_WIDGET(view))), g_object_unref);
    }
  } else {
    gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
  }
}

// Close through GTK's normal lifecycle, after the method response is delivered.
static gboolean close_probe(gpointer data) {
  gtk_window_close(GTK_WINDOW(data));
  return G_SOURCE_REMOVE;
}

static gboolean cancel_probe_picker(gpointer data) {
  gtk_dialog_response(GTK_DIALOG(data), GTK_RESPONSE_CANCEL);
  return G_SOURCE_REMOVE;
}

static void files_method_call(FlMethodChannel* channel, FlMethodCall* call,
                              gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  GtkWindow* window = gtk_application_get_active_window(GTK_APPLICATION(self));
  // A probe window is deliberately hidden and may not be active.
  if (!window) {
    GList* windows = gtk_application_get_windows(GTK_APPLICATION(self));
    if (windows) window = GTK_WINDOW(windows->data);
  }
  const gchar* method = fl_method_call_get_name(call);
  if (g_strcmp0(method, "finishProbe") == 0 && self->startup_probe) {
    fl_method_call_respond_success(call, nullptr, nullptr);
    self->probe_finished = TRUE;
    if (self->first_frame) {
      g_idle_add_full(G_PRIORITY_DEFAULT_IDLE, close_probe,
                      g_object_ref(window), g_object_unref);
    }
    return;
  }
  const bool directory = g_strcmp0(method, "pickDirectory") == 0;
  if (!directory && g_strcmp0(method, "pickFiles") != 0) {
    fl_method_call_respond_not_implemented(call, nullptr);
    return;
  }
  if (self->picker_open) {
    fl_method_call_respond_error(call, "busy", "A file dialog is already open.",
                                nullptr, nullptr);
    return;
  }
  self->picker_open = TRUE;
  GtkWidget* dialog = gtk_file_chooser_dialog_new(
      directory ? "Save results to" : "Choose files to work with", window,
      directory ? GTK_FILE_CHOOSER_ACTION_SELECT_FOLDER : GTK_FILE_CHOOSER_ACTION_OPEN,
      "_Cancel", GTK_RESPONSE_CANCEL, "_Select", GTK_RESPONSE_ACCEPT, nullptr);
  g_object_ref_sink(dialog);
  gtk_window_set_modal(GTK_WINDOW(dialog), TRUE);
  gtk_window_set_destroy_with_parent(GTK_WINDOW(dialog), TRUE);
  GtkFileChooser* chooser = GTK_FILE_CHOOSER(dialog);
  gtk_file_chooser_set_local_only(chooser, TRUE);
  FlValue* picker_args = fl_method_call_get_args(call);
  FlValue* multiple = picker_args && fl_value_get_type(picker_args) == FL_VALUE_TYPE_MAP
      ? fl_value_lookup_string(picker_args, "allowMultiple") : nullptr;
  const bool allow_multiple = !multiple || fl_value_get_type(multiple) != FL_VALUE_TYPE_BOOL
      || fl_value_get_bool(multiple);
  gtk_file_chooser_set_select_multiple(chooser, !directory && allow_multiple);
  if (!directory) {
    GtkFileFilter* filter = gtk_file_filter_new();
    gtk_file_filter_set_name(filter, "Supported files");
    FlValue* args = fl_method_call_get_args(call);
    FlValue* extensions = args && fl_value_get_type(args) == FL_VALUE_TYPE_MAP
        ? fl_value_lookup_string(args, "extensions") : nullptr;
    if (extensions && fl_value_get_type(extensions) == FL_VALUE_TYPE_LIST) {
      for (size_t i = 0; i < fl_value_get_length(extensions); i++) {
        FlValue* item = fl_value_get_list_value(extensions, i);
        if (fl_value_get_type(item) != FL_VALUE_TYPE_STRING) continue;
        const gchar* extension = fl_value_get_string(item);
        // GTK glob patterns are case sensitive; permit both common forms.
        g_autofree gchar* pattern = g_strdup_printf("*.%s", extension);
        g_autofree gchar* upper = g_ascii_strup(pattern, -1);
        gtk_file_filter_add_pattern(filter, pattern);
        gtk_file_filter_add_pattern(filter, upper);
      }
    }
    gtk_file_chooser_add_filter(chooser, filter);
    GtkFileFilter* all = gtk_file_filter_new();
    gtk_file_filter_set_name(all, "All files");
    gtk_file_filter_add_pattern(all, "*");
    gtk_file_chooser_add_filter(chooser, all);
  }
  if (self->startup_probe) g_idle_add(cancel_probe_picker, dialog);
  g_autoptr(FlValue) result = fl_value_new_null();
  if (gtk_dialog_run(GTK_DIALOG(dialog)) == GTK_RESPONSE_ACCEPT) {
    if (directory) {
      g_autofree gchar* filename = gtk_file_chooser_get_filename(chooser);
      if (filename) { g_clear_pointer(&result, fl_value_unref); result = fl_value_new_string(filename); }
    } else {
      g_clear_pointer(&result, fl_value_unref);
      result = fl_value_new_list();
      GSList* paths = gtk_file_chooser_get_filenames(chooser);
      for (GSList* item = paths; item; item = item->next) {
        fl_value_append_take(result, fl_value_new_string(static_cast<const gchar*>(item->data)));
      }
      g_slist_free_full(paths, g_free);
    }
  }
  gtk_widget_destroy(dialog);
  g_object_unref(dialog);
  self->picker_open = FALSE;
  fl_method_call_respond_success(call, result, nullptr);
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
    gtk_header_bar_set_title(header_bar, "Converto");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Converto");
  }

  gtk_window_set_default_size(window, 1180, 840);
  GdkGeometry geometry = {};
  geometry.min_width = 780;
  geometry.min_height = 600;
  gtk_window_set_geometry_hints(window, nullptr, &geometry, GDK_HINT_MIN_SIZE);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  GdkRGBA background_color;
  // Background defaults to black, override it here if necessary, e.g. #00000000
  // for transparent.
  gdk_rgba_parse(&background_color, "#171819");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  fl_register_plugins(FL_PLUGIN_REGISTRY(view));
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  g_autoptr(FlMethodChannel) channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(fl_view_get_engine(view)),
      "com.debugonaut.converto/files", FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(channel, files_method_call, self, nullptr);

  gtk_widget_grab_focus(GTK_WIDGET(view));
}

// Implements GApplication::local_command_line.
static gboolean my_application_local_command_line(GApplication* application,
                                                  gchar*** arguments,
                                                  int* exit_status) {
  MyApplication* self = MY_APPLICATION(application);
  // Strip out the first argument as it is the binary name.
  self->dart_entrypoint_arguments = g_strdupv(*arguments + 1);
  self->startup_probe = g_strv_contains(self->dart_entrypoint_arguments,
                                       "--converto-startup-probe");

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

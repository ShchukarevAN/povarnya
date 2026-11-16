#include "my_application.h"

#include <flutter_linux/flutter_linux.h>
#include <gdk/gdkkeysyms.h>
#ifdef GDK_WINDOWING_X11
#include <gdk/gdkx.h>
#endif

#include "flutter/generated_plugin_registrant.h"

struct _MyApplication {
  GtkApplication parent_instance;
  char** dart_entrypoint_arguments;
  FlMethodChannel* window_theme_channel;
  GtkWidget* header_bar;
  GtkWindow* window;
};

// Цвета заголовка передаются Flutter уже вычисленными из шести ролей палитры.
// Нативный слой не хранит самостоятельную копию цветовых тем.
static void apply_header_bar_colors(GtkWidget* header_bar,
                                    gint64 background_argb,
                                    gint64 foreground_argb) {
  if (header_bar == nullptr) {
    return;
  }

  const guint32 background = static_cast<guint32>(background_argb) & 0x00ffffff;
  const guint32 foreground = static_cast<guint32>(foreground_argb) & 0x00ffffff;
  g_autofree gchar* css = g_strdup_printf(
      "headerbar { background-image: none; background-color: #%06x; color: #%06x; } "
      "headerbar button { color: #%06x; background-image: none; }",
      background, foreground, foreground);

  GtkCssProvider* provider = GTK_CSS_PROVIDER(
      g_object_get_data(G_OBJECT(header_bar), "povarnya-titlebar-css"));
  if (provider == nullptr) {
    provider = gtk_css_provider_new();
    gtk_style_context_add_provider(gtk_widget_get_style_context(header_bar),
                                   GTK_STYLE_PROVIDER(provider),
                                   GTK_STYLE_PROVIDER_PRIORITY_APPLICATION);
    g_object_set_data_full(G_OBJECT(header_bar), "povarnya-titlebar-css",
                           provider, g_object_unref);
  }

  g_autoptr(GError) error = nullptr;
  gtk_css_provider_load_from_data(provider, css, -1, &error);
  if (error != nullptr) {
    g_warning("Failed to style title bar: %s", error->message);
  }
}

static void set_window_maximized(GtkWindow* window, gboolean maximized) {
  if (window == nullptr) {
    return;
  }
  if (maximized) {
    gtk_window_maximize(window);
  } else {
    gtk_window_unmaximize(window);
  }
}

static void set_povarnya_window_icon(GtkWindow* window) {
  if (window == nullptr) {
    return;
  }
  // Release bundle самодостаточен: значок лежит рядом с бинарником в data.
  // /proc/self/exe надёжнее текущего каталога, который зависит от способа
  // запуска приложения — из терминала, меню или .desktop-файла.
  g_autoptr(GError) error = nullptr;
  g_autofree gchar* executable = g_file_read_link("/proc/self/exe", &error);
  if (executable == nullptr) {
    g_clear_error(&error);
    return;
  }
  g_autofree gchar* executable_directory = g_path_get_dirname(executable);
  g_autofree gchar* icon_path = g_build_filename(
      executable_directory, "data", "resources", "povarnya.png", nullptr);
  if (!gtk_window_set_icon_from_file(window, icon_path, &error)) {
    g_warning("Failed to load Povarnya application icon: %s", error->message);
  }
}

static void window_theme_method_call_cb(FlMethodChannel* channel,
                                        FlMethodCall* method_call,
                                        gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  g_autoptr(FlMethodResponse) response = nullptr;

  if (strcmp(fl_method_call_get_name(method_call), "setTitleBarTheme") == 0) {
    FlValue* arguments = fl_method_call_get_args(method_call);
    FlValue* background = arguments == nullptr ? nullptr
        : fl_value_lookup_string(arguments, "background");
    FlValue* foreground = arguments == nullptr ? nullptr
        : fl_value_lookup_string(arguments, "foreground");
    if (arguments != nullptr && fl_value_get_type(arguments) == FL_VALUE_TYPE_MAP &&
        background != nullptr && foreground != nullptr &&
        fl_value_get_type(background) == FL_VALUE_TYPE_INT &&
        fl_value_get_type(foreground) == FL_VALUE_TYPE_INT) {
      apply_header_bar_colors(self->header_bar, fl_value_get_int(background),
                              fl_value_get_int(foreground));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_THEME", "Theme colors must be a map of integers.", nullptr));
    }
  } else if (strcmp(fl_method_call_get_name(method_call),
                    "setWindowMaximized") == 0) {
    FlValue* arguments = fl_method_call_get_args(method_call);
    if (arguments != nullptr &&
        fl_value_get_type(arguments) == FL_VALUE_TYPE_BOOL) {
      set_window_maximized(self->window, fl_value_get_bool(arguments));
      response = FL_METHOD_RESPONSE(fl_method_success_response_new(nullptr));
    } else {
      response = FL_METHOD_RESPONSE(fl_method_error_response_new(
          "INVALID_WINDOW_STATE", "Window state must be a boolean.", nullptr));
    }
  } else {
    response = FL_METHOD_RESPONSE(fl_method_not_implemented_response_new());
  }

  g_autoptr(GError) error = nullptr;
  if (!fl_method_call_respond(method_call, response, &error)) {
    g_warning("Failed to respond to title bar theme request: %s", error->message);
  }
}

static void minimize_window(GtkButton* button, gpointer window) {
  GdkWindow* native_window = gtk_widget_get_window(GTK_WIDGET(window));
  if (native_window != nullptr) {
    gdk_window_iconify(native_window);
  }
}

static gboolean is_maximized = FALSE;

static gboolean handle_window_state(GtkWidget* widget,
                                    GdkEventWindowState* event,
                                    gpointer user_data) {
  MyApplication* self = MY_APPLICATION(user_data);
  const gboolean maximized =
      (event->new_window_state & GDK_WINDOW_STATE_MAXIMIZED) != 0;
  if (is_maximized == maximized) {
    return FALSE;
  }
  is_maximized = maximized;
  if (self->window_theme_channel != nullptr) {
    g_autoptr(FlValue) arguments = fl_value_new_bool(maximized);
    fl_method_channel_invoke_method(self->window_theme_channel,
                                    "windowMaximizedChanged", arguments,
                                    nullptr, nullptr, nullptr);
  }
  return FALSE;
}

static gboolean restore_flutter_focus(gpointer window) {
  GtkWidget* view = GTK_WIDGET(
      g_object_get_data(G_OBJECT(window), "povarnya-flutter-view"));
  if (view != nullptr) {
    gtk_widget_grab_focus(view);
  }
  return G_SOURCE_REMOVE;
}

static void toggle_fullscreen(GtkButton* button, gpointer window) {
  // Максимизация сохраняет заголовок окна и его управляющие кнопки.
  set_window_maximized(GTK_WINDOW(window),
                       !gtk_window_is_maximized(GTK_WINDOW(window)));
  // Нажатая GTK-кнопка остаётся владельцем фокуса. Без его возврата во
  // Flutter перестают поступать и ввод чисел, и Ctrl +/-. Делаем это в idle,
  // когда диспетчер GTK уже завершил обработку нажатия и смену размера окна.
  g_idle_add(restore_flutter_focus, window);
}

static gboolean handle_window_key_press(GtkWidget* widget, GdkEventKey* event,
                                        gpointer window) {
  if (event->keyval != GDK_KEY_F11) {
    return FALSE;
  }
  // F11 использует тот же режим, что и кнопка заголовка: максимизация без
  // скрытия управляющей панели, поэтому повторное нажатие сразу возвращает
  // прежний размер окна.
  toggle_fullscreen(nullptr, window);
  return TRUE;
}

G_DEFINE_TYPE(MyApplication, my_application, GTK_TYPE_APPLICATION)

// Called when first Flutter frame received.
static void first_frame_cb(MyApplication* self, FlView* view) {
  gtk_widget_show(gtk_widget_get_toplevel(GTK_WIDGET(view)));
}

// Implements GApplication::activate.
static void my_application_activate(GApplication* application) {
  MyApplication* self = MY_APPLICATION(application);
  GtkWindow* window =
      GTK_WINDOW(gtk_application_window_new(GTK_APPLICATION(application)));
  self->window = window;
  set_povarnya_window_icon(window);
  g_signal_connect(window, "key-press-event", G_CALLBACK(handle_window_key_press),
                   window);
  g_signal_connect(window, "window-state-event", G_CALLBACK(handle_window_state),
                   self);

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
    self->header_bar = GTK_WIDGET(header_bar);
    gtk_widget_show(GTK_WIDGET(header_bar));
    gtk_header_bar_set_title(header_bar, "Поварня");
    gtk_header_bar_set_show_close_button(header_bar, TRUE);
    GtkWidget* minimize_button = gtk_button_new_from_icon_name(
        "window-minimize-symbolic", GTK_ICON_SIZE_BUTTON);
    gtk_widget_show(minimize_button);
    g_signal_connect(minimize_button, "clicked", G_CALLBACK(minimize_window),
                     window);
    gtk_header_bar_pack_start(header_bar, minimize_button);
    GtkWidget* fullscreen_button = gtk_button_new_from_icon_name(
        "view-fullscreen-symbolic", GTK_ICON_SIZE_BUTTON);
    gtk_widget_show(fullscreen_button);
    g_signal_connect(fullscreen_button, "clicked", G_CALLBACK(toggle_fullscreen),
                     window);
    gtk_header_bar_pack_end(header_bar, fullscreen_button);
    gtk_window_set_titlebar(window, GTK_WIDGET(header_bar));
  } else {
    gtk_window_set_title(window, "Поварня");
  }

  gtk_window_set_default_size(window, 1280, 720);

  g_autoptr(FlDartProject) project = fl_dart_project_new();
  fl_dart_project_set_dart_entrypoint_arguments(
      project, self->dart_entrypoint_arguments);

  FlView* view = fl_view_new(project);
  g_object_set_data(G_OBJECT(window), "povarnya-flutter-view", view);
  GdkRGBA background_color;
  // Flutter рисует поверхность сам из активной палитры.
  gdk_rgba_parse(&background_color, "transparent");
  fl_view_set_background_color(view, &background_color);
  gtk_widget_show(GTK_WIDGET(view));
  gtk_container_add(GTK_CONTAINER(window), GTK_WIDGET(view));

  // Show the window when Flutter renders.
  // Requires the view to be realized so we can start rendering.
  g_signal_connect_swapped(view, "first-frame", G_CALLBACK(first_frame_cb),
                           self);
  gtk_widget_realize(GTK_WIDGET(view));

  FlEngine* engine = fl_view_get_engine(view);
  g_autoptr(FlStandardMethodCodec) codec = fl_standard_method_codec_new();
  self->window_theme_channel = fl_method_channel_new(
      fl_engine_get_binary_messenger(engine), "povarnya/window_theme",
      FL_METHOD_CODEC(codec));
  fl_method_channel_set_method_call_handler(
      self->window_theme_channel, window_theme_method_call_cb, self, nullptr);

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
  g_clear_object(&self->window_theme_channel);
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

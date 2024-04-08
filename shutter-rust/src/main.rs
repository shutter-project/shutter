mod mainwindow;
mod editorwindow;
mod settings;

use gtk::prelude::*;
use gtk::{gio, glib};

const SHUTTER_DBUS_PATH: &str = "org.shutter-project.Shutter.Rust";
const SHUTTER_VERSION: &str = env!("CARGO_PKG_VERSION");

fn main() -> glib::ExitCode {
    gio::resources_register_include!("shutter.gresource").expect("Failed to register resources.");

    // Create a new application
    let app = gtk::Application::builder()
        .application_id(SHUTTER_DBUS_PATH)
        .flags(gio::ApplicationFlags::HANDLES_COMMAND_LINE)
        .build();
    app.add_main_option(
        "version",
        ('v' as u8).into(),
        glib::OptionFlags::NONE,
        glib::OptionArg::None,
        "Prints version information",
        None,
    );

    app.connect_startup(startup);
    app.connect_activate(|_| {});
    app.connect_handle_local_options(lcmdline);
    app.connect_command_line(cmdline);

    // Run the application
    app.run()
}

fn lcmdline(_: &gtk::Application, cmd: &glib::VariantDict) -> i32 {
    if cmd.contains("version") {
        println!("Shutter {}", SHUTTER_VERSION);
        println!(
            "Gtk {}.{}.{}",
            gtk::major_version(),
            gtk::minor_version(),
            gtk::micro_version()
        );
        return 0;
    }
    -1
}

fn cmdline(app: &gtk::Application, cmd: &gio::ApplicationCommandLine) -> i32 {
    println!(
        "cmdline, {:?} {:?}",
        cmd.options_dict().end(),
        cmd.arguments()
    );
    -1
}

fn startup(app: &gtk::Application) {
    println!("startup");

    let settings = settings::Settings::load();
    println!("{:?}", settings);

    // Create a window and set the title

    let window = mainwindow::MainWindow::new(app);
    // Despite what docs are saying, this is necessary, and cannot be set from .ui
    window.set_property("show-menubar", true);

    app.add_action_entries([gio::ActionEntry::builder("quit")
        .activate(|a: &gtk::Application, _, _| {
            a.quit();
        })
        .build()]);

    // Present window
    window.present();

    let editor = editorwindow::EditorWindow::new(app);
    editor.present();
}

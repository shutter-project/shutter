use glib::Object;
use gtk::{gio, glib, Application};

glib::wrapper! {
    pub struct MainWindow(ObjectSubclass<imp::MainWindow>)
        @extends gtk::ApplicationWindow, gtk::Window, gtk::Widget,
        @implements gio::ActionGroup, gio::ActionMap, gtk::Accessible, gtk::Buildable,
                    gtk::ConstraintTarget, gtk::Native, gtk::Root, gtk::ShortcutManager;
}

impl MainWindow {
    pub fn new(app: &Application) -> Self {
        // Create new window
        Object::builder().property("application", app).build()
    }
}

mod imp {
    use glib::subclass::InitializingObject;
    use gtk::prelude::*;
    use gtk::subclass::prelude::*;
    use gtk::{glib, CompositeTemplate};

    #[derive(CompositeTemplate, Default)]
    #[template(resource = "/org/shutter-project/Shutter/Rust/mainwindow.ui")]
    pub struct MainWindow {
        #[template_child]
        pub button: TemplateChild<gtk::Button>,
    }

    #[gtk::template_callbacks]
    impl MainWindow {
        #[template_callback]
        fn handle_button_clicked(button: &gtk::Button) {
            // Set the label to "Hello World!" after the button has been clicked on
            button.set_label("Hello World!");
        }
    }

    #[glib::object_subclass]
    impl ObjectSubclass for MainWindow {
        // `NAME` needs to match `class` attribute of template
        const NAME: &'static str = "MyGtkAppWindow";
        type Type = super::MainWindow;
        type ParentType = gtk::ApplicationWindow;

        fn class_init(klass: &mut Self::Class) {
            klass.bind_template();
            klass.bind_template_callbacks();
        }

        fn instance_init(obj: &InitializingObject<Self>) {
            obj.init_template();
        }
    }

    // Trait shared by all GObjects
    impl ObjectImpl for MainWindow {
        /*  fn constructed(&self) {
            // Call "constructed" on parent
            self.parent_constructed();
        }*/
    }

    // Trait shared by all widgets
    impl WidgetImpl for MainWindow {}

    // Trait shared by all windows
    impl WindowImpl for MainWindow {}

    // Trait shared by all application windows
    impl ApplicationWindowImpl for MainWindow {}
}

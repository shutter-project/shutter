use glib::Object;
use gtk::{gio, glib, Application};

glib::wrapper! {
    pub struct EditorWindow(ObjectSubclass<imp::EditorWindow>)
        @extends gtk::Window, gtk::Widget,
        @implements gio::ActionGroup, gio::ActionMap, gtk::Accessible, gtk::Buildable,
                    gtk::ConstraintTarget, gtk::Native, gtk::Root, gtk::ShortcutManager;
}

impl EditorWindow {
    pub fn new(app: &Application) -> Self {
        // Create new window
        Object::builder().property("application", app).build()
    }
}

mod imp {
    use glib::subclass::InitializingObject;
    use gtk::prelude::*;
    use gtk::subclass::prelude::*;
    use gtk::{glib, gio, CompositeTemplate};

    #[derive(CompositeTemplate, Default)]
    #[template(resource = "/org/shutter-project/Shutter/Rust/editorwindow.ui")]
    pub struct EditorWindow {
        #[template_child]
        pub button: TemplateChild<gtk::Widget>,
    }

    #[gtk::template_callbacks]
    impl EditorWindow {
    }

    #[glib::object_subclass]
    impl ObjectSubclass for EditorWindow {
        // `NAME` needs to match `class` attribute of template
        const NAME: &'static str = "MyEditorWindow";
        type Type = super::EditorWindow;
        type ParentType = gtk::Window;

        fn class_init(klass: &mut Self::Class) {
            klass.bind_template();
            klass.bind_template_callbacks();
        }

        fn instance_init(obj: &InitializingObject<Self>) {
            obj.init_template();
        }
    }

    // Trait shared by all GObjects
    impl ObjectImpl for EditorWindow {
        fn constructed(&self) {
            // Call "constructed" on parent
            self.parent_constructed();
            let group = gio::SimpleActionGroup::new();
            let action = gio::SimpleAction::new_stateful("tool", Some(glib::VariantTy::STRING), &"select".into());
            action.connect_activate(|action, param| {
                println!("activate {:?} {:?}", action, param);
                action.set_state(param.unwrap());
            });
            group.add_action(&action);
            self.button.insert_action_group("editor", Some(&group));
        }
    }

    // Trait shared by all widgets
    impl WidgetImpl for EditorWindow {}

    // Trait shared by all windows
    impl WindowImpl for EditorWindow {}

    // Trait shared by all application windows
    impl ApplicationWindowImpl for EditorWindow {}
}

fn main() {
    glib_build_tools::compile_resources(
        &["resources"],
        "resources.gresource.xml",
        "shutter.gresource",
    );
}

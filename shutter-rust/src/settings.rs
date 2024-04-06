use serde::{Deserialize, Serialize};

#[derive(Debug)]
pub struct Settings {
    opt: Opt,
}

#[derive(Debug, Serialize, Deserialize)]
struct Opt {
    general: General,
    gui: Gui,
    plugins: Vec<Plugin>,
    recent: Recent,
}

#[derive(Debug, Serialize, Deserialize)]
struct General {
    #[serde(rename = "@app_version")]
    app_version: Option<String>,
    #[serde(rename = "@as_confirmation_necessary", deserialize_with="debool", default="boolnone")]
    as_confirmation_necessary: Option<bool>,
    #[serde(rename = "@winresize_h")]
    winresize_h: Option<u32>,
    #[serde(rename = "@winresize_w")]
    winresize_w: Option<u32>,
}

#[derive(Debug, Serialize, Deserialize)]
struct Gui {
    #[serde(rename = "@btoolbar_active", deserialize_with="debool", default="boolnone")]
    btoolbar_active: Option<bool>,
}

fn boolnone() -> Option<bool> {
    None
}

fn debool<'de, D>(deserializer: D) -> Result<Option<bool>, D::Error> where D: serde::de::Deserializer<'de> {
    let buf = String::deserialize(deserializer)?;
    if buf.is_empty() {
        return Ok(Some(false));
    }
    if buf == "1" {
        return Ok(Some(true));
    }
    return Ok(Some(false));
}

#[derive(Debug, Serialize, Deserialize)]
struct Recent {
    #[serde(rename = "@ruu_hosting")]
    ruu_hosting: i32,
}

#[derive(Debug, Serialize, Deserialize)]
struct Plugin {
    #[serde(rename = "@name")]
    name: String,
    #[serde(rename = "@category")]
    category: String,
    #[serde(rename = "@lang")]
    lang: String,
}

impl Settings {
    pub fn load() -> anyhow::Result<Settings> {
        let xdg_dirs = xdg::BaseDirectories::with_prefix("shutter").unwrap();
        println!("{:?}", xdg_dirs);
        let dir = if xdg_dirs.get_config_home().exists() {
            xdg_dirs.get_config_home()
        } else {
            #[allow(deprecated)]
            let olddir = std::env::home_dir().unwrap().join(".shutter");
            if olddir.exists() {
                println!("TODO move to ~/.config/shutter");
                olddir
            } else {
                todo!("new config");
            }
        };

        let f = std::fs::File::open(dir.join("settings.xml"))?;
        let f = std::io::BufReader::new(f);
        let xml: Opt = quick_xml::de::from_reader(f)?;
        Ok(Settings { opt: xml })
    }
}

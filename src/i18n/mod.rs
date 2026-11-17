use crate::models::NavigationTab;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Language {
    Finnish,
    English,
}

#[allow(dead_code)]
impl Language {
    pub fn from_code(code: &str) -> Self {
        if code.eq_ignore_ascii_case("en") {
            Language::English
        } else {
            Language::Finnish
        }
    }

    pub fn code(&self) -> &'static str {
        match self {
            Language::Finnish => "fi",
            Language::English => "en",
        }
    }

    pub fn tab_title(&self, tab: NavigationTab) -> &'static str {
        match (self, tab) {
            (Language::Finnish, NavigationTab::BoxManager) => "Boksin hallinta",
            (Language::English, NavigationTab::BoxManager) => "Box Manager",

            (Language::Finnish, NavigationTab::Remote) => "Kaukosäädin",
            (Language::English, NavigationTab::Remote) => "Remote Control",

            (Language::Finnish, NavigationTab::Channels) => "Kanavat & EPG",
            (Language::English, NavigationTab::Channels) => "Channels & EPG",

            (Language::Finnish, NavigationTab::TimersAndMovies) => "Ajastukset & Tallenteet",
            (Language::English, NavigationTab::TimersAndMovies) => "Timers & Movies",

            (Language::Finnish, NavigationTab::SettingsSync) => "Asetusten synkronointi",
            (Language::English, NavigationTab::SettingsSync) => "Settings Sync",

            (Language::Finnish, NavigationTab::Bootlogo) => "Käynnistyskuva",
            (Language::English, NavigationTab::Bootlogo) => "Bootlogo",

            (Language::Finnish, NavigationTab::ImageManager) => "Image Manager",
            (Language::English, NavigationTab::ImageManager) => "Image Manager",

            (Language::Finnish, NavigationTab::Support) => "Tietoja & Tuki",
            (Language::English, NavigationTab::Support) => "About & Support",
        }
    }

    pub fn active_box_label(&self) -> &'static str {
        match self {
            Language::Finnish => "Valittu vastaanotin:",
            Language::English => "Active receiver:",
        }
    }

    pub fn no_box_selected(&self) -> &'static str {
        match self {
            Language::Finnish => "Ei valittua boksia",
            Language::English => "No receiver selected",
        }
    }

    pub fn refresh_btn(&self) -> &'static str {
        match self {
            Language::Finnish => "Päivitä",
            Language::English => "Refresh",
        }
    }
}

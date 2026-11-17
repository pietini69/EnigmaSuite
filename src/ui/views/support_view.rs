use egui::{Color32, RichText, Ui};
use crate::models::EnigmaBox;
use crate::i18n::Language;

pub struct SupportView;

impl Default for SupportView {
    fn default() -> Self {
        Self
    }
}

impl SupportView {
    pub fn render(&mut self, ui: &mut Ui, _active_box: Option<&EnigmaBox>, _lang: Language) {
        ui.heading("ℹ Tietoja & Tuki");
        ui.add_space(8.0);

        ui.group(|ui| {
            ui.label(RichText::new("EnigmaSuite V2").size(20.0).strong().color(Color32::from_rgb(59, 130, 246)));
            ui.label(RichText::new("Versio 2.0.0 (Rust Native)").size(13.0).color(Color32::GRAY));
            ui.label("Kehittäjä: Niko Pietinen");
            ui.add_space(6.0);
            ui.label("EnigmaSuite on moderni, huippunopea ja monialustainen hallintasovellus Enigma2-digibokseille (OpenATV, VTi, OpenPLi, PurE2 jne.).");
            ui.add_space(6.0);

            ui.horizontal(|ui| {
                if ui.button("🌐 Avaa GitHub-sivu").clicked() {
                    let _ = open::that("https://github.com/pietini69/EnigmaSuite");
                }
                if ui.button("📖 OpenWebif API -ohjeistus").clicked() {
                    let _ = open::that("https://github.com/E2OpenPlugins/e2openplugin-OpenWebif/wiki/OpenWebif-API-documentation");
                }
            });
        });

        ui.add_space(12.0);

        ui.group(|ui| {
            ui.strong("Pikaohjeet ja vinkit:");
            ui.add_space(4.0);
            ui.label("• Yhteyden muodostus: Varmista, että vastaanottimen OpenWebif-laajennus on päällä ja samaan lähiverkkoon yhdistetty.");
            ui.label("• Suoratoisto: Suoratoistopainikkeet (VLC) avaavat suoran striimin suoraan oletusmediasoittimellasi.");
            ui.label("• Asetusten synkronointi: Voit verrata ja kloonata kanavat sekä asetukset kahden boksin välillä vaivattomasti.");
            ui.label("• Turvallisuus: Kaikki tiedot tallennetaan paikallisesti koneellesi ilman pilvipalveluita.");
        });
    }
}

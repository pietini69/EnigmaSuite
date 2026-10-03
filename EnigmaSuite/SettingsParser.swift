import Foundation

final class SettingsParser {
    static let shared = SettingsParser()
    
    // MARK: - Parsitaan tiedoston sisältö sanakirjaksi [Avain: Arvo]
    func parse(content: String) -> [String: String] {
        var result: [String: String] = [:]
        let lines = content.components(separatedBy: .newlines)
        
        for rawLine in lines {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.isEmpty || line.hasPrefix("#") { continue }
            
            // Jaetaan ensimmäisestä '=' merkistä
            if let equalIndex = line.firstIndex(of: "=") {
                let key = String(line[..<equalIndex]).trimmingCharacters(in: .whitespaces)
                let value = String(line[line.index(after: equalIndex)...]).trimmingCharacters(in: .whitespaces)
                if !key.isEmpty {
                    result[key] = value
                }
            }
        }
        return result
    }
    
    // MARK: - Määritetään asetuksen kategoria
    func category(for key: String) -> SettingsCategory {
        // 1. Kielet ja tekstitykset
        if key == "config.osd.language" ||
           key.hasPrefix("config.autolanguage.") ||
           key.hasPrefix("config.subtitles.") {
            return .language
        }
        
        // 2. EPG (Ohjelmaopas)
        if key.hasPrefix("config.misc.graph_mepg_") ||
           key == "config.usage.epg_default_view" ||
           key.hasPrefix("config.usage.autolanguage.epglanguage") ||
           key.hasPrefix("config.plugins.epgrefresh.") ||
           key.hasPrefix("config.plugins.epgimport.") {
            return .epg
        }
        
        // 3. Tallennus ja toisto
        if key.hasPrefix("config.recording.") ||
           key == "config.usage.rec_button" ||
           key.hasPrefix("config.usage.allowed_timeshift_paths") ||
           key.hasPrefix("config.usage.on_movie_") ||
           key.hasPrefix("config.movielist.") {
            return .recording
        }
        
        // 4. Teemat ja etupaneelin näyttö
        if key.hasPrefix("config.skin.") ||
           key.hasPrefix("config.lcd.") ||
           key.hasPrefix("config.vfd.") ||
           key.contains("vfdskin") {
            return .skinAndDisplay
        }
        
        // 5. Virittimet
        if key.hasPrefix("config.Nims.") {
            return .tuners
        }
        
        // 6. Aikavyöhyke
        if key.hasPrefix("config.timezone.") {
            return .timezone
        }
        
        // 7. Liitännäiset (Plugins)
        if key.hasPrefix("config.plugins.") {
            return .plugins
        }
        
        // 8. Käyttökokemus ja valikot
        if key.hasPrefix("config.usage.") {
            return .usage
        }
        
        // 9. Muut järjestelmäasetukset
        return .misc
    }
    
    // MARK: - Päätellään virittimien määrä ja tyyppi asetustiedostosta tarvittaessa
    func deduceTuners(from settings: [String: String]) -> [TunerInfo] {
        var tunersByIndex: [Int: (family: TunerFamily, type: String)] = [:]
        
        for key in settings.keys where key.hasPrefix("config.Nims.") {
            let parts = key.components(separatedBy: ".")
            guard parts.count > 3, let idx = Int(parts[2]) else { continue }
            
            let subtype = parts[3].lowercased()
            if subtype.contains("cable") {
                tunersByIndex[idx] = (.cable, "DVB-C (Kaapeli)")
            } else if subtype.contains("dvbs") || subtype.contains("sat") || subtype.contains("diseqc") {
                tunersByIndex[idx] = (.satellite, "DVB-S2 (Satelliitti)")
            } else if subtype.contains("terrestrial") {
                tunersByIndex[idx] = (.terrestrial, "DVB-T2 (Antenni)")
            } else if tunersByIndex[idx] == nil {
                tunersByIndex[idx] = (.unknown, "Muu viritin")
            }
        }
        
        var result: [TunerInfo] = []
        for idx in tunersByIndex.keys.sorted() {
            let info = tunersByIndex[idx]!
            let letter = idx < 26 ? String(UnicodeScalar(65 + idx)!) : "\(idx)"
            result.append(TunerInfo(
                index: idx,
                name: "Viritin \(letter)",
                type: info.type,
                family: info.family
            ))
        }
        return result
    }
    
    // MARK: - Rakennetaan vertailulista kahden boksin välille
    func buildEntries(
        source: [String: String],
        target: [String: String],
        sourceTuners: [TunerInfo] = [],
        targetTuners: [TunerInfo] = [],
        defaultSelectedCategories: Set<SettingsCategory>
    ) -> [SettingEntry] {
        var allKeys = Set<String>(source.keys)
        allKeys.formUnion(target.keys)
        
        let effSourceTuners = sourceTuners.isEmpty ? deduceTuners(from: source) : sourceTuners
        let effTargetTuners = targetTuners.isEmpty ? deduceTuners(from: target) : targetTuners
        
        var entries: [SettingEntry] = []
        
        for key in allKeys.sorted() {
            let cat = category(for: key)
            let sVal = source[key]
            let tVal = target[key]
            
            var tunerCompat: TunerCompatibility = .notTuner
            if cat == .tuners {
                let parts = key.components(separatedBy: ".")
                if parts.count > 2, let nimIndex = Int(parts[2]) {
                    let sTuner = effSourceTuners.first(where: { $0.index == nimIndex })
                    let tTuner = effTargetTuners.first(where: { $0.index == nimIndex })
                    
                    if effTargetTuners.isEmpty {
                        tunerCompat = .unknown
                    } else if tTuner == nil {
                        tunerCompat = .missingInTarget(sourceType: sTuner?.type ?? "Tuntematon")
                    } else if let s = sTuner, let t = tTuner {
                        if s.family == t.family || s.type == t.type {
                            tunerCompat = .compatible
                        } else {
                            tunerCompat = .incompatibleType(sourceType: s.type, targetType: t.type)
                        }
                    } else {
                        tunerCompat = .unknown
                    }
                }
            }
            
            let isDiff = sVal != tVal
            let isCategoryDefault = defaultSelectedCategories.contains(cat)
            
            var autoSelect = false
            if isDiff && isCategoryDefault {
                if cat == .tuners {
                    if case .compatible = tunerCompat {
                        autoSelect = true
                    } else {
                        autoSelect = false
                    }
                } else {
                    autoSelect = true
                }
            }
            
            entries.append(SettingEntry(
                key: key,
                sourceValue: sVal,
                targetValue: tVal,
                category: cat,
                tunerCompatibility: tunerCompat,
                isSelected: autoSelect
            ))
        }
        
        return entries
    }
    
    // MARK: - Luodaan päivitetty asetussisältö valituilla avaimilla
    func applySelected(
        selectedEntries: [SettingEntry],
        into targetSettings: [String: String]
    ) -> String {
        var merged = targetSettings
        for entry in selectedEntries where entry.isSelected {
            if let sVal = entry.sourceValue {
                merged[entry.key] = sVal
            }
        }
        
        let sortedKeys = merged.keys.sorted()
        var outputLines: [String] = []
        for key in sortedKeys {
            if let val = merged[key] {
                outputLines.append("\(key)=\(val)")
            }
        }
        
        return outputLines.joined(separator: "\n") + "\n"
    }
}

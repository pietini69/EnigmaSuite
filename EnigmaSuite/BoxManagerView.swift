import SwiftUI

struct BoxManagerView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    // Uuden boksin lisäys
    @State private var showAddBoxSheet: Bool = false
    @State private var newBoxName: String = ""
    @State private var newBoxIP: String = ""
    @State private var newBoxPort: String = "80"
    @State private var newBoxUsername: String = "root"
    @State private var newBoxPassword: String = ""
    
    // Boksin muokkaus
    @State private var editingBox: EnigmaBox?
    
    // Telnet konsoli
    @State private var terminalCommand: String = "df -h"
    @State private var terminalOutput: String = ""
    @State private var isExecutingCommand: Bool = false
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                // MARK: - BOKSIEN HALLINTAPALKKI
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Boxes_Title"))
                            .font(.title2.bold())
                        Text(L10n("Boxes_HeaderSubtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    Button(action: {
                        Task { await state.autoDiscoverBoxes(showFeedback: true) }
                    }) {
                        HStack(spacing: 6) {
                            if state.isDiscovering {
                                ProgressView().scaleEffect(0.7)
                            } else {
                                Image(systemName: "antenna.radiowaves.left.and.right")
                            }
                            Text(L10n("Boxes_ScanNetwork"))
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(state.isDiscovering)
                    
                    Button(action: { showAddBoxSheet = true }) {
                        Label(L10n("Boxes_AddBox"), systemImage: "plus.circle.fill")
                    }
                    .buttonStyle(.borderedProminent)
                }
                
                // MARK: - LAITEKORTIT
                if state.boxes.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "network")
                            .font(.system(size: 48))
                            .foregroundColor(.secondary)
                        Text(L10n("Boxes_EmptyTitle"))
                            .font(.title3.bold())
                        Text(L10n("Boxes_EmptyDesc"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                        
                        HStack(spacing: 14) {
                            Button(action: { Task { await state.autoDiscoverBoxes(showFeedback: true) } }) {
                                Label(L10n("Boxes_EmptyButton"), systemImage: "antenna.radiowaves.left.and.right")
                            }
                            .buttonStyle(.borderedProminent)
                            
                            Button(L10n("Boxes_AddBox")) {
                                showAddBoxSheet = true
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(40)
                    .frame(maxWidth: .infinity)
                    .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
                    .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
                } else {
                    ForEach(state.boxes) { box in
                        boxCard(for: box)
                    }
                }
                
                // MARK: - TELNET PÄÄTE / KOMENTORIVI
                terminalSection
            }
            .padding(24)
        }
        .sheet(isPresented: $showAddBoxSheet) {
            addBoxSheet
        }
        .sheet(item: $editingBox) { box in
            editBoxSheet(for: box)
        }
    }
    
    // MARK: - Laitekortti
    private func boxCard(for box: EnigmaBox) -> some View {
        let isActive = state.activeBox?.id == box.id
        
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                // Tila-ikoni
                Circle()
                    .fill(box.isOnline ? Color.green : Color.red)
                    .frame(width: 12, height: 12)
                
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(box.name)
                            .font(.headline)
                        if isActive {
                            Text(L10n("Boxes_ActiveBadge"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.accentColor.opacity(0.15))
                                .foregroundColor(.accentColor)
                                .clipShape(Capsule())
                        }
                        if box.hasAuth {
                            Text("🔒 " + L10n("Boxes_Protected"))
                                .font(.caption2.bold())
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.orange.opacity(0.15))
                                .foregroundColor(.orange)
                                .clipShape(Capsule())
                        }
                    }
                    Text("http://\(box.ip):\(box.port)")
                        .font(.caption.monospaced())
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if !isActive {
                    Button(L10n("Boxes_SelectActive")) {
                        state.activeBox = box
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(action: { editingBox = box }) {
                    Image(systemName: "pencil")
                }
                .buttonStyle(.borderless)
                .help(L10n("Boxes_Edit"))
                
                Button(role: .destructive, action: {
                    state.deleteBox(box)
                }) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
                .help(L10n("Boxes_Delete"))
            }
            
            Divider()
            
            // Laitetiedot (Malli, Distro, Virittimet)
            HStack(alignment: .top, spacing: 24) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "cpu")
                            .foregroundColor(.secondary)
                        Text(L10n("Boxes_Model"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(box.model ?? (box.isOnline ? "..." : L10n("Common_NoConnection")))
                            .font(.caption)
                    }
                    
                    HStack(spacing: 6) {
                        Image(systemName: "gearshape")
                            .foregroundColor(.secondary)
                        Text("OS / Image:")
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text(box.distro ?? (box.isOnline ? "..." : L10n("Common_NoConnection")))
                            .font(.caption)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 6) {
                        Image(systemName: "antenna.radiowaves.left.and.right")
                            .foregroundColor(.secondary)
                        Text(L10n("Boxes_Tuners"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                        Text("\(box.tuners.count) " + L10n("Boxes_Pcs"))
                            .font(.caption.bold())
                    }
                    
                    if !box.tuners.isEmpty {
                        Text(box.tuners.prefix(4).map { "\($0.shortLetter): \($0.family.rawValue)" }.joined(separator: ", "))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                // Pika-virtakomennot
                HStack(spacing: 8) {
                    Button("Standby") {
                        Task { await EnigmaBoxService.shared.setPowerState(ip: box.ip, state: 0, port: box.port, username: box.username, password: box.password) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("GUI Restart") {
                        Task { await EnigmaBoxService.shared.setPowerState(ip: box.ip, state: 3, port: box.port, username: box.username, password: box.password) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                    
                    Button("Reboot") {
                        Task { await EnigmaBoxService.shared.setPowerState(ip: box.ip, state: 2, port: box.port, username: box.username, password: box.password) }
                    }
                    .buttonStyle(.bordered)
                    .font(.caption)
                }
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(isActive ? Color.accentColor : Color.secondary.opacity(0.15), lineWidth: isActive ? 2 : 1)
        )
    }
    
    // MARK: - Telnet Pääte
    private var terminalSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(L10n("Boxes_TelnetTitle"), systemImage: "terminal")
                .font(.headline)
            
            HStack(spacing: 10) {
                TextField("Command (e.g. df -h, free -m, uptime)", text: $terminalCommand)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                
                Button(action: {
                    executeTerminalCommand()
                }) {
                    HStack {
                        if isExecutingCommand {
                            ProgressView().scaleEffect(0.7)
                        } else {
                            Image(systemName: "play.fill")
                        }
                        Text(L10n("Boxes_ExecuteCommand"))
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(terminalCommand.isEmpty || isExecutingCommand || state.activeBox == nil)
            }
            
            // Pika-napit
            HStack(spacing: 8) {
                quickCommandButton("df -h")
                quickCommandButton("free -m")
                quickCommandButton("uptime")
                quickCommandButton("cat /proc/version")
                quickCommandButton("init 4")
                quickCommandButton("init 3")
            }
            
            if !terminalOutput.isEmpty {
                ScrollView {
                    Text(terminalOutput)
                        .font(.system(.caption, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(12)
                }
                .frame(height: 180)
                .background(Color.black.opacity(0.85))
                .foregroundColor(.green)
                .cornerRadius(8)
            }
        }
        .padding(18)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color(nsColor: .controlBackgroundColor)))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.15), lineWidth: 1))
    }
    
    private func quickCommandButton(_ cmd: String) -> some View {
        Button(cmd) {
            terminalCommand = cmd
            executeTerminalCommand()
        }
        .font(.caption2.monospaced())
        .buttonStyle(.bordered)
    }
    
    private func executeTerminalCommand() {
        guard let box = state.activeBox else { return }
        isExecutingCommand = true
        terminalOutput = LocalizationManager.shared.isFinnish ? "Suoritetaan: \(terminalCommand)...\n" : "Executing: \(terminalCommand)...\n"
        
        Task {
            let (_, output) = await EnigmaBoxService.shared.executeTelnetCommand(
                ip: box.ip,
                command: terminalCommand,
                port: 23,
                timeout: 8.0,
                username: box.username,
                password: box.password
            )
            
            await MainActor.run {
                self.isExecutingCommand = false
                self.terminalOutput = output
            }
        }
    }
    
    // MARK: - Lisää boksi Sheet
    private var addBoxSheet: some View {
        VStack(spacing: 14) {
            Text(L10n("Dialog_AddBoxTitle"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("Dialog_BoxNameLabel"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("Living room", text: $newBoxName)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxIpLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("192.168.1.100", text: $newBoxIP)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxPortLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("80", text: $newBoxPort)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxUsernameLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("root", text: $newBoxUsername)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxPasswordLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    SecureField("", text: $newBoxPassword)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Text(L10n("Dialog_BoxAuthHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Button(L10n("Common_Cancel")) {
                    showAddBoxSheet = false
                    newBoxName = ""
                    newBoxIP = ""
                    newBoxPort = "80"
                    newBoxUsername = "root"
                    newBoxPassword = ""
                }
                Spacer()
                Button(L10n("Common_Save")) {
                    let port = Int(newBoxPort) ?? 80
                    state.addBox(name: newBoxName, ip: newBoxIP, port: port, username: newBoxUsername, password: newBoxPassword)
                    showAddBoxSheet = false
                    newBoxName = ""
                    newBoxIP = ""
                    newBoxPort = "80"
                    newBoxUsername = "root"
                    newBoxPassword = ""
                }
                .buttonStyle(.borderedProminent)
                .disabled(newBoxIP.trimmingCharacters(in: .whitespaces).isEmpty)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 440)
    }
    
    // MARK: - Muokkaa boksia Sheet
    private func editBoxSheet(for box: EnigmaBox) -> some View {
        EditBoxSheetView(box: box) { updated in
            state.updateBox(updated)
            editingBox = nil
        } onCancel: {
            editingBox = nil
        }
    }
}

struct EditBoxSheetView: View {
    @State var name: String
    @State var ip: String
    @State var port: String
    @State var username: String
    @State var password: String
    let box: EnigmaBox
    let onSave: (EnigmaBox) -> Void
    let onCancel: () -> Void
    
    init(box: EnigmaBox, onSave: @escaping (EnigmaBox) -> Void, onCancel: @escaping () -> Void) {
        self.box = box
        self._name = State(initialValue: box.name)
        self._ip = State(initialValue: box.ip)
        self._port = State(initialValue: "\(box.port)")
        self._username = State(initialValue: box.username)
        self._password = State(initialValue: box.password)
        self.onSave = onSave
        self.onCancel = onCancel
    }
    
    var body: some View {
        VStack(spacing: 14) {
            Text(L10n("Dialog_EditBoxTitle"))
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n("Dialog_BoxNameLabel"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                TextField("Living room", text: $name)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxIpLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("192.168.1.100", text: $ip)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxPortLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("80", text: $port)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 80)
                }
            }
            
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxUsernameLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    TextField("root", text: $username)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n("Dialog_BoxPasswordLabel"))
                        .font(.caption.bold())
                        .foregroundColor(.secondary)
                    SecureField("", text: $password)
                        .textFieldStyle(.roundedBorder)
                }
            }
            
            Text(L10n("Dialog_BoxAuthHint"))
                .font(.caption2)
                .foregroundColor(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            HStack {
                Button(L10n("Common_Cancel"), action: onCancel)
                Spacer()
                Button(L10n("Common_Save")) {
                    var updated = box
                    updated.name = name
                    updated.ip = ip
                    updated.port = Int(port) ?? 80
                    updated.username = username.trimmingCharacters(in: .whitespaces).isEmpty ? "root" : username
                    updated.password = password
                    onSave(updated)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(.top, 6)
        }
        .padding(24)
        .frame(width: 440)
    }
}

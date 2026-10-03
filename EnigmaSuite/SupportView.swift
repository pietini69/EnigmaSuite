import SwiftUI
import AppKit

struct SupportView: View {
    @EnvironmentObject var state: EnigmaSuiteState
    @EnvironmentObject var l10n: LocalizationManager
    
    private let buyMeACoffeeURL = "https://buymeacoffee.com/pnp69"
    private let payPalURL = "https://www.paypal.com/paypalme/my/profile"
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // MARK: - Hero Card
                HStack(alignment: .top, spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow.opacity(0.85), Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 68, height: 68)
                            .shadow(color: Color.orange.opacity(0.3), radius: 8, x: 0, y: 3)
                        
                        Text("☕")
                            .font(.system(size: 34))
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n("Support_Title"))
                            .font(.title2.bold())
                        
                        Text(L10n("Support_Subtitle"))
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                        
                        Text(L10n("Support_Desc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(22)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color(nsColor: .controlBackgroundColor))
                        .shadow(color: Color.black.opacity(0.06), radius: 6, x: 0, y: 2)
                )
                
                // MARK: - Support Options
                Text(L10n("Support_ChooseMethod"))
                    .font(.caption.bold())
                    .foregroundColor(.secondary)
                    .padding(.horizontal, 4)
                
                HStack(spacing: 16) {
                    // 1. Buy Me a Coffee Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Text("☕")
                                .font(.title3)
                                .padding(8)
                                .background(Color.yellow.opacity(0.2))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Buy Me a Coffee")
                                    .font(.headline)
                                Text("buymeacoffee.com/pnp69")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(L10n("Support_BmacDesc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minHeight: 36, alignment: .topLeading)
                        
                        Button(action: {
                            openURL(buyMeACoffeeURL)
                        }) {
                            HStack {
                                Text("☕ " + L10n("Support_BmacBtn"))
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.orange)
                        
                        Button(action: {
                            copyToClipboard(buyMeACoffeeURL, name: "Buy Me a Coffee")
                        }) {
                            Text(L10n("Support_CopyLink"))
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    )
                    
                    // 2. PayPal Card
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Text("🅿️")
                                .font(.title3)
                                .padding(8)
                                .background(Color.blue.opacity(0.15))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                            
                            VStack(alignment: .leading, spacing: 2) {
                                Text("PayPal")
                                    .font(.headline)
                                Text("paypal.me/my/profile")
                                    .font(.caption2.monospaced())
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Text(L10n("Support_PayPalDesc"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .frame(minHeight: 36, alignment: .topLeading)
                        
                        Button(action: {
                            openURL(payPalURL)
                        }) {
                            HStack {
                                Text("🅿️ " + L10n("Support_PayPalBtn"))
                                    .fontWeight(.bold)
                                Image(systemName: "arrow.up.right")
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(Color.blue)
                        
                        Button(action: {
                            copyToClipboard(payPalURL, name: "PayPal")
                        }) {
                            Text(L10n("Support_CopyLink"))
                                .font(.caption)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                    .padding(18)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color(nsColor: .controlBackgroundColor))
                            .shadow(color: Color.black.opacity(0.04), radius: 6, x: 0, y: 2)
                    )
                }
                
                // MARK: - FAQ Card
                VStack(alignment: .leading, spacing: 12) {
                    Text(L10n("Support_FaqTitle"))
                        .font(.subheadline.bold())
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Support_FaqQ1"))
                            .font(.caption.bold())
                        Text(L10n("Support_FaqA1"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(L10n("Support_FaqQ2"))
                            .font(.caption.bold())
                        Text(L10n("Support_FaqA2"))
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 14)
                        .fill(Color(nsColor: .controlBackgroundColor))
                )
                
                // MARK: - Footer
                HStack {
                    HStack(spacing: 6) {
                        Text("❤️")
                        Text(L10n("Support_Thanks"))
                            .font(.caption.bold())
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    Text("EnigmaSuite v\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.2")")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
            }
            .padding(28)
            .frame(maxWidth: 820)
        }
        .background(Color(nsColor: .windowBackgroundColor))
    }
    
    private func openURL(_ urlString: String) {
        if let url = URL(string: urlString) {
            NSWorkspace.shared.open(url)
        }
    }
    
    private func copyToClipboard(_ text: String, name: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        state.showToast("\(name) -linkki kopioitu leikepöydälle!")
    }
}

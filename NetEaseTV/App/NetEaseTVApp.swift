import SwiftUI

@main
struct NetEaseTVApp: App {
    @State private var account = AccountStore.shared
    @State private var player = PlayerService.shared
    @State private var content = ContentStore()
    @State private var toast = ToastCenter.shared

    var body: some Scene {
        WindowGroup {
            AppShellView()
                .environment(account)
                .environment(player)
                .environment(content)
                .environment(toast)
                .preferredColorScheme(.dark)
        }
    }
}

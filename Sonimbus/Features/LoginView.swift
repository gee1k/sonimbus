import CoreImage
import CoreImage.CIFilterBuiltins
import SwiftUI
import UIKit

struct LoginView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AccountStore.self) private var account

    @State private var qrImage: UIImage?
    @State private var key: String?
    @State private var status = "正在生成二维码…"
    @State private var errorMessage: String?

    private let context = CIContext()

    var body: some View {
        ZStack {
            TVBackground(tint: TVTheme.accent)
            HStack(spacing: 90) {
                VStack(alignment: .leading, spacing: 28) {
                    Image(systemName: "cloud.fill")
                        .font(.system(size: 70, weight: .semibold))
                        .foregroundStyle(TVTheme.accent)
                    Text("登录网易云音乐")
                        .font(.system(size: 58, weight: .bold, design: .rounded))
                    Text("在手机上打开网易云音乐，扫描右侧二维码。登录后即可访问每日推荐、私人 FM 和你的全部歌单。")
                        .font(.title3)
                        .foregroundStyle(TVTheme.secondaryText)
                        .lineSpacing(8)
                        .frame(maxWidth: 700, alignment: .leading)
                    Label("凭证只保存在这台 Apple TV 上", systemImage: "lock.shield.fill")
                        .font(.headline)
                        .foregroundStyle(.white.opacity(0.78))
                    Button("稍后登录") { dismiss() }
                        .buttonStyle(TVPillButtonStyle())
                }
                .frame(maxWidth: 760, alignment: .leading)

                VStack(spacing: 24) {
                    ZStack {
                        RoundedRectangle(cornerRadius: 34, style: .continuous)
                            .fill(.white)
                        if let qrImage {
                            Image(uiImage: qrImage)
                                .interpolation(.none)
                                .resizable()
                                .scaledToFit()
                                .padding(38)
                        } else {
                            ProgressView().tint(.black).controlSize(.large)
                        }
                    }
                    .frame(width: 430, height: 430)
                    .shadow(color: TVTheme.accent.opacity(0.35), radius: 70)

                    Text(errorMessage ?? status)
                        .font(.headline)
                        .foregroundStyle(errorMessage == nil ? .white : TVTheme.accent)
                        .multilineTextAlignment(.center)
                        .frame(width: 480)

                    if errorMessage != nil {
                        Button("重新生成") {
                            Task { await beginLogin() }
                        }
                        .buttonStyle(TVPillButtonStyle(prominent: true))
                    }
                }
            }
            .padding(.horizontal, 120)
        }
        .task { await beginLogin() }
        .onExitCommand { dismiss() }
    }

    @MainActor
    private func beginLogin() async {
        errorMessage = nil
        qrImage = nil
        status = "正在生成二维码…"
        do {
            let newKey = try await NeteaseAPI.qrKey()
            key = newKey
            qrImage = makeQRCode(NeteaseAPI.qrLoginURL(key: newKey))
            status = "等待扫码"
            await poll(key: newKey)
        } catch is CancellationError {
            return
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    @MainActor
    private func poll(key: String) async {
        var consecutiveFailures = 0
        while !Task.isCancelled, self.key == key {
            do {
                let result = try await NeteaseAPI.qrCheck(key: key)
                consecutiveFailures = 0
                switch result.code {
                case 800:
                    errorMessage = "二维码已过期"
                    return
                case 801:
                    status = "等待扫码"
                case 802:
                    status = "已扫码，请在手机上确认"
                case 803:
                    status = "登录成功，正在同步资料库…"
                    if await account.bootstrap() {
                        dismiss()
                        return
                    }
                    errorMessage = account.bootstrapError ?? "账号资料同步失败，请重试"
                    return
                default:
                    status = result.message ?? "等待网易云音乐确认"
                }
            } catch is CancellationError {
                return
            } catch {
                consecutiveFailures += 1
                if consecutiveFailures >= 3 {
                    errorMessage = "网络连接不稳定，请重新生成二维码后再试"
                    return
                }
                status = "网络波动，正在自动重试…"
            }
            try? await Task.sleep(for: .seconds(2))
        }
    }

    private func makeQRCode(_ value: String) -> UIImage? {
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(value.utf8)
        filter.correctionLevel = "M"
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 12, y: 12)),
              let cgImage = context.createCGImage(output, from: output.extent) else { return nil }
        return UIImage(cgImage: cgImage)
    }
}

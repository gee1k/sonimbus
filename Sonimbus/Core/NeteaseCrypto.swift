import CommonCrypto
import CryptoKit
import Foundation

/// 网易云音乐 weapi / eapi 请求加密。
/// 固定 weapi secret 与对应 RSA 密文来自 LGPL-3.0 的 Kumone 实现。
enum NeteaseCrypto {
    private static let weapiPresetKey = "0CoJUm6Qyw8W8jud"
    private static let weapiIV = "0102030405060708"
    private static let weapiSecretKey = "kumone2026abcDEF"
    private static let weapiEncSecKey =
        "38cef2efdbcc1cfd6a44d81620dae5d23091f50ef27e01a1b1bb7e998e0fde2d" +
        "7ab6002a9e79a3c195f661cbde80e21e6245997b11b54d28407115822f95d447" +
        "7cc06b5a77de46fab6568410abf1229abef81b4c8588f386149010d190bb0b04" +
        "f064be330bd877a4d4b99514febbdb4335b10744b13d9f7ee24d314d6e62cdc9"
    private static let eapiKey = "e82ckenh8dichen8"

    static func weapi(payload: Data) -> [String: String] {
        let first = aes128(payload, key: weapiPresetKey, cbcIV: weapiIV).base64EncodedData()
        let second = aes128(first, key: weapiSecretKey, cbcIV: weapiIV).base64EncodedString()
        return ["params": second, "encSecKey": weapiEncSecKey]
    }

    static func eapi(apiPath: String, payload: Data) -> [String: String] {
        let json = String(decoding: payload, as: UTF8.self)
        let message = "nobody\(apiPath)use\(json)md5forencrypt"
        let digest = Insecure.MD5.hash(data: Data(message.utf8))
            .map { String(format: "%02x", $0) }
            .joined()
        let plaintext = "\(apiPath)-36cd479b6b5-\(json)-36cd479b6b5-\(digest)"
        let encrypted = aes128(Data(plaintext.utf8), key: eapiKey, cbcIV: nil)
        return ["params": encrypted.map { String(format: "%02X", $0) }.joined()]
    }

    private static func aes128(_ data: Data, key: String, cbcIV: String?) -> Data {
        let keyData = Data(key.utf8)
        var output = Data(count: data.count + kCCBlockSizeAES128)
        var written = 0
        let options: CCOptions = cbcIV == nil
            ? CCOptions(kCCOptionPKCS7Padding | kCCOptionECBMode)
            : CCOptions(kCCOptionPKCS7Padding)
        let ivData = cbcIV.map { Data($0.utf8) }
        let outputCapacity = output.count

        let status = output.withUnsafeMutableBytes { outputPointer in
            data.withUnsafeBytes { dataPointer in
                keyData.withUnsafeBytes { keyPointer in
                    if let ivData {
                        return ivData.withUnsafeBytes { ivPointer in
                            CCCrypt(
                                CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options,
                                keyPointer.baseAddress, keyData.count, ivPointer.baseAddress,
                                dataPointer.baseAddress, data.count,
                                outputPointer.baseAddress, outputCapacity, &written
                            )
                        }
                    }
                    return CCCrypt(
                        CCOperation(kCCEncrypt), CCAlgorithm(kCCAlgorithmAES), options,
                        keyPointer.baseAddress, keyData.count, nil,
                        dataPointer.baseAddress, data.count,
                        outputPointer.baseAddress, outputCapacity, &written
                    )
                }
            }
        }
        precondition(status == kCCSuccess, "AES encryption failed: \(status)")
        return output.prefix(written)
    }
}

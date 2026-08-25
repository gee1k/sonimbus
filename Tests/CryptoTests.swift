import Foundation
import Testing
@testable import SonimbusCore

@Test("weapi 加密输出稳定且包含 RSA 密文")
func weapiShape() {
    let result = NeteaseCrypto.weapi(payload: Data(#"{"hello":"tvOS"}"#.utf8))

    #expect(result["params"]?.isEmpty == false)
    #expect(result["encSecKey"]?.count == 256)
    #expect(Data(base64Encoded: result["params"] ?? "") != nil)
}

@Test("eapi 输出为大写十六进制并按块对齐")
func eapiShape() {
    let result = NeteaseCrypto.eapi(
        apiPath: "/api/song/enhance/player/url/v1",
        payload: Data(#"{"ids":"[1]"}"#.utf8)
    )
    let value = result["params"] ?? ""

    #expect(value.isEmpty == false)
    #expect(value == value.uppercased())
    #expect(value.count.isMultiple(of: 32))
    #expect(value.allSatisfy { $0.isHexDigit })
}

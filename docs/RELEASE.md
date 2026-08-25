# 维护者发布

本文档只记录云音厅维护者使用本机 Xcode 账号进行 TestFlight 发布的流程。普通开发者在模拟器或真机上运行项目，请直接阅读根目录 `README.md`。

## 前置条件

- Xcode 已登录有发布权限的 Apple Developer 账号；
- App Store Connect 中已创建 Bundle ID 为 `com.svend.sonimbus` 的 tvOS App；
- 本机已具备 Xcode 自动签名所需的证书和描述文件；
- Team ID 只通过环境变量传入，不写入工程或仓库。

## 打包并上传

```bash
SONIMBUS_TEAM_ID=你的TeamID ./Scripts/package-ipa.sh
```

脚本会依次完成：

1. 使用 Release 配置归档通用 tvOS 构建；
2. 导出签名 IPA 到 `build/testflight/<构建号>/ipa/`；
3. 上传 App Store Connect；
4. 将构建限制为 TestFlight Internal Only。

默认构建号为 UTC 时间戳。需要指定版本或构建号时：

```bash
SONIMBUS_TEAM_ID=你的TeamID \
SONIMBUS_MARKETING_VERSION=0.3.0 \
SONIMBUS_BUILD_NUMBER=2026082501 \
./Scripts/package-ipa.sh
```

只归档并导出 IPA、不上传：

```bash
SONIMBUS_TEAM_ID=你的TeamID ./Scripts/package-ipa.sh --no-upload
```

仓库不会保存 Apple ID、Team ID、证书名称或其他账号标识。发布前应确认本机当前登录的是正确账号，并检查版本号和构建号没有重复。

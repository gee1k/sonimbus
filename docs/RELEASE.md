# 维护者发布

本文档记录云音厅维护者发布 TestFlight 构建和 GitHub Release 的流程。普通开发者在模拟器或真机上运行项目，请直接阅读根目录 `README.md`。

## 版本策略

营销版本代表功能阶段，修复和小改动只递增 Build Number；进入新的功能阶段时再提升营销版本，并将 Build Number 重置为 `1`。两者统一维护在 Xcode target 的 **General → Identity** 中。

外部 TestFlight 测试中，每个营销版本的首个 Build 需要完整 Beta App Review，同一版本的后续 Build 可能不需要完整审核。

## TestFlight

### 自动签名（默认）

传入本机 Apple Developer Team ID，脚本会使用 Xcode 当前登录的 Apple Account 自动管理签名资源，并在导出 IPA 后上传 App Store Connect：

```bash
./Scripts/package-ipa.sh --team-id 你的TeamID
```

也可以显式指定自动签名：

```bash
./Scripts/package-ipa.sh \
  --team-id 你的TeamID \
  --signing automatic
```

如果当前 Team 尚未注册 Apple TV，Xcode 可能无法生成 tvOS Development Profile。此时可连接真机后重试，或使用手动签名模式。

### 手动签名

自动签名不可用时，可切换到手动模式：

```bash
./Scripts/package-ipa.sh \
  --team-id 你的TeamID \
  --signing manual
```

脚本会自动查找本机钥匙串中属于该 Team 的分发证书，并从 Xcode Profile 目录中选择与 `com.svend.sonimbus` 匹配、未过期且有效期最长的 App Store Profile。

需要覆盖自动选择结果时，可统一通过命令行参数传入：

```bash
./Scripts/package-ipa.sh \
  --team-id 你的TeamID \
  --signing manual \
  --certificate "Apple Distribution: 你的证书名称" \
  --profile "你的Profile名称"
```

Profile 与证书参数都是可选的，但只适用于手动签名模式。

### Build Number 与输出

脚本默认读取工程中的 Build Number。临时构建可以显式覆盖：

```bash
./Scripts/package-ipa.sh \
  --team-id 你的TeamID \
  --build-number 4
```

本地签名产物输出到：

```text
build/testflight/<营销版本>/<Build Number>/ipa/
```

只归档并导出 IPA、不上传 App Store Connect：

```bash
./Scripts/package-ipa.sh \
  --team-id 你的TeamID \
  --no-upload
```

`--build-number` 只适合临时覆盖。准备发布 GitHub Release 时，应把正式 Build Number 写入工程并提交，以保证 Tag、源码和 IPA 一致。

## GitHub Release

GitHub Actions 只构建未签名 tvOS IPA，不使用 Apple Developer 账号、证书、Profile 或 App Store Connect 凭证。

确认工程中的营销版本和 Build Number 已提交后，创建对应 Tag：

```bash
git tag v1.1.0-build.4
git push origin v1.1.0-build.4
```

Tag 格式固定为：

```text
v<营销版本>-build.<Build Number>
```

Action 会检查 Tag 与工程版本完全一致，然后创建类似下面的 GitHub Release：

```text
Sonimbus 1.1.0 (Build 4)
Sonimbus-tvOS-1.1.0-build.4-unsigned.ipa
```

同一营销版本可以连续发布多个 Build：

```text
v1.1.0-build.4
v1.1.0-build.5
```

未签名 IPA 由使用者通过支持 tvOS 的工具，以自己的 Apple Account 重新签名后安装。它不能直接安装，也不能上传 TestFlight。

## 账号信息

仓库不会保存 Apple ID、Team ID、证书名称、Profile 名称或其他账号标识。所有本地签名参数都在执行脚本时传入，GitHub Release 工作流不接触任何 Apple 账号资源。

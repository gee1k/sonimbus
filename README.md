# 云听 · NetEase TV

一个为 Apple TV 设计的原生网易云音乐客户端。使用 SwiftUI 和 AVFoundation 构建，直接连接网易云音乐的加密 API，不依赖自建后端。

## 当前功能

- 网易云 App 扫码登录，Cookie 本地持久化与自动刷新
- 首页个性推荐、每日歌曲、新歌、私人 FM
- 精选歌单完整分类、热门/最新排序、排行榜、新专辑、热门歌手
- 歌曲、歌单、专辑、歌手搜索，支持官方推荐词、最近搜索与连续分页
- 喜欢的歌曲、收藏专辑、关注歌手、账号播放记录与音乐云盘
- 云盘歌曲播放、HTTPS 链接上传、删除与曲目资料匹配
- 创建和删除歌单、收藏歌单、向自建歌单添加或移除歌曲
- 编辑自建歌单标题、描述与 HTTPS 链接封面
- 播放队列、下一首播放、添加到队列、上一首/下一首、随机、列表循环、单曲循环、拖动进度
- 心动模式、私人 FM 不喜欢、不可播放歌曲自动跳过与听歌记录回传
- 网易云无完整地址或实际加载失败时，可按名称、歌手与时长补全公开音源
- 歌手热门歌曲、完整专辑目录与相似歌手推荐
- LRC 同步歌词、翻译与罗马音，当前行自动滚动；遥控器可逐行选择并跳转播放
- Apple TV 遥控器焦点交互与系统 Now Playing / Remote Command 支持
- 选歌、全部播放或随机播放时进入一次播放页；手动返回后不再自动弹回
- 任意层级可从顶部“正在播放”进入，返回时保留原页面、筛选与滚动位置
- 播放队列、进度、最近播放与随机顺序跨启动恢复
- 标准、较高、极高、无损和高解析度无损音质选择，不可用时自动回退

## 平台限制

- tvOS 不提供面向电视应用的通用文件选择器，云盘上传采用 HTTPS 直链；文件会先下载到电视的临时目录，再上传到网易云。
- 备用公开音源会受提供方可用性和内容授权影响，不保证每首歌曲都能补全；可在“设置”中关闭。
- 歌单资料编辑仅适用于当前账号创建的歌单；封面同样使用 HTTPS 图片链接。
- Apple Music Sing、SharePlay、空间音频标记等依赖 Apple Music 服务的能力不适用于网易云音乐目录。

## 环境

- macOS 15 或更高版本
- Xcode 26 或更高版本（工程最低支持 tvOS 17）
- 真机安装需要免费的 Apple ID 或 Apple Developer 账号进行签名

## 运行

1. 用 Xcode 打开 `NetEaseTV.xcodeproj`。
2. 选择 `NetEaseTV` scheme 和 Apple TV 模拟器或已连接的 Apple TV。
3. 真机首次运行时，在 Signing & Capabilities 中选择自己的 Team。
4. 运行应用，使用手机网易云音乐 App 扫描电视上的二维码。

命令行无签名编译：

```bash
xcodebuild -project NetEaseTV.xcodeproj \
  -scheme NetEaseTV \
  -sdk appletvos \
  CODE_SIGNING_ALLOWED=NO build
```

## 打包 IPA

配置好签名 Team 后执行：

```bash
DEVELOPMENT_TEAM=你的TeamID ./Scripts/package-ipa.sh
```

脚本会在 `build/` 下生成签名后的 `NetEaseTV.ipa`。若使用免费 Apple ID，描述文件通常只有 7 天有效期；付费开发者账号通常为 1 年。IPA 仅用于你有权访问的 Apple TV 和内容。

如果只需要在 CI 或没有开发证书的机器上验证包结构：

```bash
./Scripts/package-unsigned-ipa.sh
```

它会生成 `build/unsigned/NetEaseTV-unsigned.ipa`，但该包不能直接安装，仍需使用与目标 Apple TV 匹配的证书和描述文件签名。

## 测试

```bash
swift test
```

执行真实网易云公开接口冒烟测试：

```bash
NETEASE_API_SMOKE=1 swift test --filter liveAPISmokeTest
```

## 说明与许可

本项目是非官方个人客户端，与网易云音乐或 Apple 无关联。音乐、封面、歌词与账号数据的权利归各自权利人所有；请遵守服务条款与所在地法律。

网易云协议与兼容策略参考了 LGPL-3.0 的 [missuo/kumone](https://github.com/missuo/kumone) 和 MIT 的 [NeteaseCloudMusicApiEnhanced](https://github.com/NeteaseCloudMusicApiEnhanced/api-enhanced)，具体归属见 `THIRD_PARTY_NOTICES.md` 和 `Licenses/`。本项目代码以 LGPL-3.0-only 提供。

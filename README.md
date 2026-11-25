# Relocate

按应用和全局修改 GPS 定位。原项目 [Relocate](https://github.com/NepetaDev/Relocate) 的重写版，支持 iOS 15+ 的 rootless 与 roothide 环境。

Per-app and global GPS location override, rebuilt for iOS 15+ on rootless and roothide.

## 功能

- **全局默认位置** —— 所有未单独设置的应用使用这个坐标
- **按应用覆盖** —— 每个应用可以单独指定位置，或标记为「使用真实位置」排除掉
- **系统服务** —— 「查找 iPhone」「查找朋友」等可单独设置
- **地图选点** —— 支持地名搜索、收藏、摇杆微调
- **坐标转换** —— 国内地图选点自动 GCJ-02 ↔ WGS-84 转换，落点不会偏移
- **多语言** —— 简体中文 / 繁体中文 / English

## 安装

从 [jzksnsjswkw 源](https://jzksnsjswkw.github.io/repo/) 安装，或下载 release 里的 deb：

```
com.jzksnsjswkw.relocate-roothide   # roothide，arm64e
com.jzksnsjswkw.relocate-rootless   # rootless，arm64
```

依赖：ellekit、preferenceloader、AltList。

## 使用

设置 → Relocate。

- **默认位置**：不区分应用时使用的位置
- **按应用设置**：列表里每个应用可以选默认 / 自定义 / 使用真实位置
- **系统服务**：「查找」等系统服务单独配置

设置页顶部的总开关关闭时，所有替换停止。

## 说明

**「查找」的位置有延迟。** 位置由设备上报到 iCloud 后再由 App 读取，修改后需要几分钟才体现，无法从设备端缩短。设置页的重启按钮只让新位置在本地立即生效，不影响上报间隔。

**注入范围。** 这是一个 App 层插件，hook `CLLocationManager`。未被注入的应用（roothide 下默认关闭第三方注入，需在 Bootstrap 的 App List 里手动开启）不受影响，Safari 网页定位、系统级服务也不在范围内。

**不支持 locationd 层注入。** 早期版本尝试过在 `locationd` 里改位置，在 iOS 16.5 上验证不可行：App 的位置是 `CLDaemonLocation` 结构体经 XPC 传给 App 侧构造的，不经过 `CLLocation.encodeWithCoder:`。

## 构建

需要 [theos](https://github.com/theos/theos)。

```sh
make package THEOS_PACKAGE_SCHEME=roothide   # arm64e
make package THEOS_PACKAGE_SCHEME=rootless   # arm64
```

不指定 scheme 会报错：rootful 布局不支持。

## 致谢

原项目 [Relocate](https://github.com/NepetaDev/Relocate) by [Nepeta](https://github.com/NepetaDev)。

HBPreferences 的 ObjC 源码取自 [Cephei](https://github.com/hbang/libcephei)。

## 许可

MIT，见 [LICENSE](LICENSE)。

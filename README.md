# iOSSync iOS App（TrollStore 版）

iPhone 原生 App：读取 HealthKit（今日步数 + 最近心率）+ 定位，一键推送到小米手表 2 Pro 上的 iOSSync App（Wi-Fi HTTP）。

- 无需 Mac、无需苹果开发者账号：用 **GitHub Actions 云端编译** 产出 .ipa，**TrollStore（巨魔）安装**，永久有效
- iOS 15+ 可用（你的 iOS 16.6.1 完美支持）

## 项目结构

```
project.yml                  # XcodeGen 工程定义
iOSSync/                     # Swift 源码
  iOSSyncApp.swift           # App 入口
  ContentView.swift          # 主界面（同步按钮/状态/地址设置）
  HealthReader.swift         # HealthKit（步数/心率）
  LocationReader.swift       # CoreLocation + 反向地理编码
  WatchClient.swift          # POST /sync 到手表
.github/workflows/build.yml  # 云构建流水线（macos runner）
```

## 构建 → 安装全流程

### 1. 上传到 GitHub
1. 注册/登录 [github.com](https://github.com)
2. 右上角 **+** → **New repository** → 起名 `iossync` → **Public**（Private 也可以，免费额度够用）→ Create
3. 仓库页点 **uploading an existing file** 链接（或 Add file → Upload files）
4. 把 `iosapp.zip` 解压出来的**所有文件和文件夹**（包括 `.github` 文件夹！）拖进去 → Commit changes

### 2. 云端编译
1. 仓库顶部 **Actions** 标签页
2. 左侧选 **Build IPA** → 右侧 **Run workflow** → Run
3. 等 2~3 分钟，变绿后点进本次运行
4. 页面底部 **Artifacts** 下载 `iOSSync-ipa` → 解压得到 `iOSSync.ipa`

### 3. 巨魔安装
1. 把 `iOSSync.ipa` 传到 iPhone（AirDrop / 微信 / 云盘均可）
2. iPhone 上「分享」→ **TrollStore**（或先存文件再在 TrollStore 里 Install IPA）
3. 桌面出现 **iOSSync** 图标，点开

### 4. 使用
1. 首次打开：允许健康数据（读取步数/心率）、允许定位、允许本地网络
2. 确保手机和手表连**同一个 Wi-Fi**
3. 点「测试连接」显示「已连通 ✓」→ 点「同步到手表」
4. 手表 iOSSync App 立即显示最新数据

## 常见问题

- **Actions 构建失败**：进 Actions 看红叉步骤日志，把报错发给助手
- **测试连接连不上**：检查手表 iOSSync App 是否在前台/后台运行；iPhone 代理需给 192.168.* 加直连规则
- **健康数据为 0**：HealthKit 里确实没数据（iPhone 自身或关联设备需先记录步数）

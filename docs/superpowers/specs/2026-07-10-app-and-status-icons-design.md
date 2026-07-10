# macOS 应用与状态栏图标替换设计

## 目标

- 使用 `xxsnap-icons-v1-彩色/mac/AppIcon.appiconset` 替换 macOS 应用图标。
- 使用 `xxsnap-icons-v1-黑白/mac/AppIcon.appiconset` 中适合菜单栏显示的素材替换顶部状态栏图标。
- 保持现有图标加载逻辑和 18×18 点菜单栏显示尺寸不变。

## 资源映射

彩色 AppIcon 的 16、32、128、256、512 点及对应 2x PNG 与现有资产槽位逐一映射，不进行缩放或重新编码。由于当前 `Info.plist` 通过 `CFBundleIconFile = xxsnap` 使用 `Resources/xxsnap.icns`，还需要用同一套十个彩色 PNG 重新生成并替换该 ICNS；不改变现有应用图标加载配置。

菜单栏继续使用工程实际打包的 `Resources/xxsnap.png` 作为资源名，并替换为黑白套件的 `icon-128.png`。该文件包含透明通道，适合现有 `isTemplate = true` 的深浅色自动着色；黑白套件的 16、32 和 64 像素文件没有透明通道，不能直接作为模板图，否则透明区域会成为实色方块。`Resources/Icons/xxsnap.png` 未被工程引用，保持原样。

## 范围与性能

仅替换静态 PNG 资源，不修改窗口、截图、贴图或快捷键逻辑。运行时仍只在状态栏初始化时加载一次图片，不增加定时器、监听器或重复绘制。

## 验收

- AppIcon 资产目录中的十个槽位尺寸和 scale 均有效，生成的 `xxsnap.icns` 可由 `iconutil` 正常展开。
- 菜单栏源图具有透明通道，仍按模板图显示。
- Xcode Debug 构建成功。
- 重启 `build/xcode-derived` 中的最新版 XxSnap，并确认进程已运行。

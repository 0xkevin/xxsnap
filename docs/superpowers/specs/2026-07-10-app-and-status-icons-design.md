# macOS 应用与状态栏图标替换设计

## 目标

- 使用 `xxsnap-icons-v1-彩色/mac/AppIcon.appiconset` 替换 macOS 应用图标。
- 使用 `xxsnap-icons-v1-黑白/mac/AppIcon.appiconset` 中适合菜单栏显示的素材替换顶部状态栏图标。
- 保持现有图标加载逻辑和 18×18 点菜单栏显示尺寸不变。

## 资源映射

彩色 AppIcon 的 16、32、128、256、512 点及对应 2x PNG 与现有资产槽位逐一映射，不进行缩放或重新编码。由于当前 `Info.plist` 通过 `CFBundleIconFile = xxsnap` 使用 `Resources/xxsnap.icns`，还需要用同一套十个彩色 PNG 重新生成并替换该 ICNS；不改变现有应用图标加载配置。

菜单栏继续使用工程实际打包的 `Resources/xxsnap.png` 作为资源名。黑白套件中的 PNG 虽然部分文件声明了 alpha 通道，但画布像素实际全部不透明，不能直接用于 `isTemplate = true`，否则整幅画布会成为实色方块。使用 `icon-128.png` 的反相亮度生成透明度：浅灰背景和白色分隔线变透明，黑色折纸主体保持可见，再将处理后的 PNG 写入运行时资源。`Resources/Icons/xxsnap.png` 未被工程引用，保持原样。

## 范围与性能

仅替换静态 PNG 资源，不修改窗口、截图、贴图或快捷键逻辑。运行时仍只在状态栏初始化时加载一次图片，不增加定时器、监听器或重复绘制。

## 验收

- AppIcon 资产目录中的十个槽位尺寸和 scale 均有效，生成的 `xxsnap.icns` 可由 `iconutil` 正常展开。
- 菜单栏源图超过一半像素完全透明，同时至少十分之一像素保持可见，仍按模板图显示。
- Xcode Debug 构建成功。
- 重启 `build/xcode-derived` 中的最新版 XxSnap，并确认进程已运行。

# XxSnap macOS 打包发布手册

这份手册只讲一件事：把 `main` 分支打成正式 DMG，并发布到官网。

正式包必须使用 Apple `Developer ID Application` 证书并通过公证。没有证书时只能做内部测试包，不要按正式版本发布，否则用户可能看到“无法打开”或“文件已损坏”。

## 一、第一次发布前准备

只需要准备一次：

1. 加入 Apple Developer Program。
2. 在“钥匙串访问”中安装 `Developer ID Application` 证书。
3. 为 Apple ID 创建 App 专用密码，并保存公证凭据。

### [Mac] 检查签名证书

```bash
security find-identity -v -p codesigning
```

输出中必须有 `Developer ID Application: ... (团队 ID)`。只有 `xxsnap Local Dev` 不够，不能用于正式发布。

### [Mac] 保存公证凭据

把下面三个占位值换成自己的：

```bash
xcrun notarytool store-credentials "xxsnap-notary" \
  --apple-id "你的 Apple ID" \
  --team-id "你的团队 ID" \
  --password "你的 App 专用密码"
```

凭据会保存在本机钥匙串中，不要写进代码仓库。

## 二、修改版本号

版本号在 `platforms/mac/project.yml`：

```yaml
CURRENT_PROJECT_VERSION: 1
MARKETING_VERSION: 1.0.0
```

- `MARKETING_VERSION`：用户看到的版本，例如 `1.0.0`。
- `CURRENT_PROJECT_VERSION`：构建号，每次发布都必须增大，例如 `1`、`2`、`3`。

在开发分支修改后，重新生成 Xcode 项目：

### [Mac]

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap/platforms/mac
xcodegen generate
cd ../..
```

提交代码、合并到 `main`，然后再进行下面的正式打包。生产包只允许从 `main` 构建。

## 三、确认 main 可以发布

### [Mac]

```bash
cd /Users/kevin/Projects/open-source/Snipory/xxsnap
git switch main
git pull --ff-only origin main
git status --short
```

最后一条命令必须没有输出。只要还有未提交文件，就先停止，不要打包。

运行完整测试：

```bash
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Debug \
  -derivedDataPath build/xcode-derived \
  test
```

有新增失败时不要继续发布。项目原有的已知失败要单独核对，不能把新失败当成旧问题忽略。

## 四、准备正式构建参数

### [Mac]

把占位值换成真实内容：

```bash
export VERSION="1.0.0"
export BUILD_NUMBER="1"
export TEAM_ID="你的 Apple 团队 ID"
export SIGN_IDENTITY="Developer ID Application: 证书名称 (团队 ID)"
export COMMERCIAL_PUBLIC_KEY="后台当前 commercial-ed25519-2026-01 公钥"
export RELEASE_DIR="$PWD/dist/$VERSION"
export ARCHIVE_PATH="$RELEASE_DIR/XxSnap.xcarchive"
export APP_PATH="$ARCHIVE_PATH/Products/Applications/XxSnap.app"
export DMG_NAME="XxSnap-$VERSION-universal.dmg"
export DMG_PATH="$RELEASE_DIR/$DMG_NAME"
```

`COMMERCIAL_PUBLIC_KEY` 只填生产 Ed25519 公钥，不要使用项目里的测试公钥，更不要复制后台私钥。

### [腾讯云 182.254.155.22] 查看当前公钥

```bash
sudo grep '^XXSNAP_COMMERCIAL_TRUSTED_PUBLIC_KEYS=' /etc/xxsnap/xxsnap-admin.env
```

只复制 `commercial-ed25519-2026-01` 对应的 Base64 公钥值。

正式构建还需要一份最新的免费期策略。先备份仓库中的测试策略，退出当前终端时会自动恢复：

```bash
export POLICY_FILE="$PWD/platforms/mac/Resources/Commercial/commercial-policy-bootstrap.json"
export POLICY_BACKUP="$(mktemp)"
cp "$POLICY_FILE" "$POLICY_BACKUP"
trap 'cp "$POLICY_BACKUP" "$POLICY_FILE"; rm -f "$POLICY_BACKUP"' EXIT
curl -fsS "https://download.xxsofts.com/api/v1/commercial/policy" -o "$POLICY_FILE"
```

## 五、构建并检查正式 App

### [Mac]

```bash
mkdir -p "$RELEASE_DIR"

DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild archive \
  -project platforms/mac/xxsnap.xcodeproj \
  -scheme xxsnap \
  -configuration Release \
  -archivePath "$ARCHIVE_PATH" \
  -destination "generic/platform=macOS" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  MACOSX_DEPLOYMENT_TARGET=14.0 \
  ENABLE_HARDENED_RUNTIME=YES \
  CODE_SIGN_STYLE=Manual \
  CODE_SIGN_IDENTITY="$SIGN_IDENTITY" \
  DEVELOPMENT_TEAM="$TEAM_ID" \
  XX_COMMERCIAL_PRODUCTION_SIGNING_PUBLIC_KEY_2026_01="$COMMERCIAL_PUBLIC_KEY"

cp "$POLICY_BACKUP" "$POLICY_FILE"
rm -f "$POLICY_BACKUP"
trap - EXIT
```

检查版本、架构和签名：

```bash
test -d "$APP_PATH"
defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString
defaults read "$APP_PATH/Contents/Info" CFBundleVersion
defaults read "$APP_PATH/Contents/Info" LSMinimumSystemVersion
lipo -archs "$APP_PATH/Contents/MacOS/XxSnap"
codesign --verify --deep --strict --verbose=2 "$APP_PATH"
codesign -dv --verbose=4 "$APP_PATH" 2>&1 | grep -E "Authority|TeamIdentifier|Runtime Version"
```

必须确认：

- 版本号和构建号正确；
- 最低系统是 `14.0`；
- 架构同时有 `arm64` 和 `x86_64`；
- 签名是 `Developer ID Application`；
- Hardened Runtime 已开启。

## 六、制作 DMG 并公证

### [Mac]

```bash
export DMG_STAGE="$(mktemp -d)"
ditto "$APP_PATH" "$DMG_STAGE/XxSnap.app"
ln -s /Applications "$DMG_STAGE/Applications"

hdiutil create \
  -volname "XxSnap" \
  -srcfolder "$DMG_STAGE" \
  -ov \
  -format UDZO \
  "$DMG_PATH"

rm -rf "$DMG_STAGE"
codesign --force --sign "$SIGN_IDENTITY" --timestamp "$DMG_PATH"
xcrun notarytool submit "$DMG_PATH" --keychain-profile "xxsnap-notary" --wait
xcrun stapler staple "$DMG_PATH"
xcrun stapler validate "$DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=4 "$DMG_PATH"
```

`notarytool` 必须显示 `Accepted`。不是 `Accepted` 就停止，不要上传后台。

## 七、生成 manifest.json

### [Mac]

```bash
export FILE_SIZE="$(stat -f%z "$DMG_PATH")"
export SHA256="$(shasum -a 256 "$DMG_PATH" | awk '{print $1}')"

cat > "$RELEASE_DIR/manifest.json" <<EOF
{
  "version": "$VERSION",
  "buildNumber": $BUILD_NUMBER,
  "minimumMacOSVersion": "14.0",
  "architecture": "universal2",
  "fileName": "$DMG_NAME",
  "fileSize": $FILE_SIZE,
  "sha256": "$SHA256",
  "publishedAt": null
}
EOF

printf '%s  %s\n' "$SHA256" "$DMG_NAME" > "$RELEASE_DIR/checksums.txt"
(cd "$RELEASE_DIR" && shasum -a 256 -c checksums.txt)
```

最终目录应为：

```text
dist/1.0.0/
├── XxSnap-1.0.0-universal.dmg
├── manifest.json
└── checksums.txt
```

## 八、上传并发布

### [浏览器]

1. 打开 `https://admin.xxsofts.com` 并登录。
2. 进入“版本管理”，点击“新建版本”。
3. 版本号和构建号必须与 `manifest.json` 一致。
4. 最低系统选择 `macOS 14.0`，架构保持 `Universal 2`。
5. 填写中文、英文发布说明。
6. 同时上传 DMG 和 `manifest.json`，点击“保存草稿”。
7. 核对版本、构建号、文件大小和状态，再点击“发布”。

后台会自己校验文件大小和 SHA-256。校验不通过时不要绕过，应重新检查 DMG 和 manifest。

## 九、发布后检查

### [Mac]

```bash
curl -fsS "https://download.xxsofts.com/api/v1/releases/latest?locale=zh-CN"
curl -fsSI "https://download.xxsofts.com/files/$VERSION/$DMG_NAME"
open "https://xxsnap.xxsofts.com/zh-CN/"
open "https://xxsnap.xxsofts.com/zh-CN/releases/"
```

确认官网版本、更新日志和下载按钮都指向新版本。再用另一台 Mac 下载 DMG，安装后检查截图、贴图、滚动截图、文字识别和教笔。

确认没有问题后打标签：

```bash
git tag -a "v$VERSION" -m "XxSnap $VERSION"
git push origin main "v$VERSION"
```

## 十、发布错了怎么办

不要覆盖服务器上的旧 DMG，也不要手工删除 `/srv/xxsnap/releases` 文件。

1. 登录 `admin.xxsofts.com`。
2. 在“版本管理”中撤回有问题的版本。
3. 修复代码并增加构建号。
4. 重新走完整打包、上传、发布流程。

撤回后，官网和公开 API 会自动回到仍处于“已发布”状态的上一个版本。

# 发布清单 / Release checklist

现在是开发版：`./scripts/package.sh` 打出的包是本机签名（ad-hoc），只能在打包的那台 Mac 上用。
**在完成下面几步之前，不要把安装包发给别人，也不要传到 GitHub Releases。**

1. 加入 Apple Developer Program（每年 99 美元），拿到 Developer ID Application 证书。
2. 打开 Hardened Runtime，只声明需要的 entitlement（麦克风；不要 JIT）。
3. `xcrun notarytool submit` → `xcrun stapler staple` → `spctl -a -vv` 验收。
4. 生成 dmg 和 SHA-256；以后接 Sparkle 时再生成 appcast（EdDSA 签名）。
5. 在 GitHub Releases 发布，附上更新说明（CHANGELOG）、隐私说明和许可。
6. README 写清唯一的官方下载地址，提醒不要从别处下载。

安装包、图标、iconset 都是 `package.sh` 的产物，不进 git（见 `.gitignore`）。

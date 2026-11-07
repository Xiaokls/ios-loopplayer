#!/bin/zsh
# 在 macOS 虚拟机里运行：一键生成免签名 LoopPlayer.ipa
# 用法：把仓库 clone 到 Mac VM 后，终端执行 ./build-local.sh
set -e
cd "$(dirname "$0")"

# 安装 XcodeGen（如已安装则跳过）
brew list xcodegen >/dev/null 2>&1 || brew install xcodegen

xcodegen generate
rm -rf build Payload LoopPlayer.ipa

xcodebuild -project LoopPlayer.xcodeproj \
  -scheme LoopPlayer \
  -configuration Release \
  -sdk iphoneos \
  -destination 'generic/platform=iOS' \
  -derivedDataPath build \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir Payload
cp -R build/Build/Products/Release-iphoneos/LoopPlayer.app Payload/
zip -qr LoopPlayer.ipa Payload

echo ""
echo "✅ 完成：$(pwd)/LoopPlayer.ipa"

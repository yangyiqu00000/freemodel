#!/bin/bash
# FreeModelMenuBar 编译脚本
# 在 Mac 上运行此脚本编译应用

set -e

echo "🚀 开始编译 FreeModelMenuBar..."

# 获取脚本所在目录
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# 检查 xcodebuild
if ! command -v xcodebuild &> /dev/null; then
    echo "❌ 错误：未找到 xcodebuild，请确保 Xcode 已安装"
    echo "   可以从 App Store 下载 Xcode"
    exit 1
fi

echo "✅ 找到 xcodebuild"

# 清理之前的构建
echo "🧹 清理之前的构建..."
rm -rf build

# 编译 Release 版本
# CODE_SIGNING_ALLOWED=NO：跳过 xcodebuild 内置 CodeSign phase。
# 原因：构建产物 .app bundle 根目录常带 com.apple.FinderInfo（macOS Sequoia
# 文件提供者同步标记），会让内置 codesign 报 "resource fork / Finder
# information not allowed" 而失败。签名交由下方复制到桌面后统一做。
echo "🔨 编译 Release 版本..."
xcodebuild \
    -project FreeModelMenuBar.xcodeproj \
    -scheme FreeModelMenuBar \
    -configuration Release \
    -derivedDataPath build/DerivedData \
    CODE_SIGNING_ALLOWED=NO \
    build

# 找到编译好的应用
APP_PATH="build/DerivedData/Build/Products/Release/FreeModelMenuBar.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "✅ 编译成功！"
    echo ""
    echo "📦 应用位置: $SCRIPT_DIR/$APP_PATH"
    echo ""
    
    # 复制到桌面
    DESKTOP_PATH="$HOME/Desktop"
    if [ -d "$DESKTOP_PATH" ]; then
        echo "📋 清理桌面旧版本并复制新版本..."
        rm -rf "$DESKTOP_PATH/FreeModelMenuBar.app"
        ditto "$APP_PATH" "$DESKTOP_PATH/FreeModelMenuBar.app"
        echo "✅ 已复制到桌面: $DESKTOP_PATH/FreeModelMenuBar.app"
    fi
    
    echo ""
    echo "🎉 完成！你可以："
    echo "   1. 从桌面双击运行 FreeModelMenuBar.app"
    echo "   2. 点击菜单栏的 💲 图标"
    echo "   3. 进入设置配置你的 API Key"
    echo ""
    
else
    echo "❌ 编译失败，未找到应用文件"
    exit 1
fi

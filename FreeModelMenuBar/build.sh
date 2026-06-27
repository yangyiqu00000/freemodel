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

# 签名身份（自签名证书名称）
SIGNING_IDENTITY="FreeModel Dev Signing"

# 确保自签名证书存在（不存在则创建）
# 注意：用 security find-identity（不加 -v）检查，因为自签名证书不受信任
if ! security find-identity 2>/dev/null | grep -q "$SIGNING_IDENTITY"; then
    echo "🔑 创建自签名证书 '$SIGNING_IDENTITY'..."
    CERT_DIR="/tmp/FreeModelBuildCert"
    mkdir -p "$CERT_DIR"

    CERT_CONF="$CERT_DIR/cert.conf"
    cat > "$CERT_CONF" << EOF
[ req ]
distinguished_name = dn
x509_extensions = v3_ext
prompt = no

[ dn ]
CN = $SIGNING_IDENTITY

[ v3_ext ]
keyUsage = critical, digitalSignature
extendedKeyUsage = codeSigning
subjectKeyIdentifier = hash
EOF

    openssl req -x509 -newkey rsa:2048 -keyout "$CERT_DIR/dev.key" \
        -out "$CERT_DIR/dev.crt" -days 365 -nodes \
        -config "$CERT_CONF"

    security import "$CERT_DIR/dev.crt" -k ~/Library/Keychains/login.keychain-db
    security import "$CERT_DIR/dev.key" -k ~/Library/Keychains/login.keychain-db
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s \
        -k "" ~/Library/Keychains/login.keychain-db 2>/dev/null || true

    rm -rf "$CERT_DIR"
    echo "✅ 自签名证书已创建"
fi

# 在 /tmp 中构建，避免 macOS Sequoia 文件提供者在项目目录
# （可能位于 iCloud/Dropbox 同步目录）添加 com.apple.fileprovider.fpfs#P
# 等扩展属性，导致 codesign 报 "resource fork ... not allowed"。
BUILD_ROOT="/tmp/FreeModelMenuBarBuild"
echo "🛠 清理旧构建..."
rm -rf "$BUILD_ROOT"

echo "🔨 编译 Release 版本..."
xcodebuild \
    -project "$SCRIPT_DIR/FreeModelMenuBar.xcodeproj" \
    -scheme FreeModelMenuBar \
    -configuration Release \
    -derivedDataPath "$BUILD_ROOT/DerivedData" \
    CODE_SIGNING_ALLOWED=NO \
    build

APP_PATH="$BUILD_ROOT/DerivedData/Build/Products/Release/FreeModelMenuBar.app"

if [ -d "$APP_PATH" ]; then
    echo ""
    echo "✅ 编译成功！"
    echo ""

    # 用自签名证书签名（在 /tmp 构建不会带文件提供者扩展属性）
    echo "🔏 签名应用..."

    # 获取证书 SHA-1 哈希
    CERT_HASH=$(security find-identity 2>/dev/null | grep "$SIGNING_IDENTITY" | head -1 | awk '{print $2}')
    if [ -z "$CERT_HASH" ]; then
        echo "❌ 找不到签名证书 '$SIGNING_IDENTITY'"
        exit 1
    fi
    codesign --force --deep --timestamp=none --sign "$CERT_HASH" "$APP_PATH"
    echo "✅ 签名完成"
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

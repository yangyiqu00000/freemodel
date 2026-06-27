#!/bin/bash
# sign.sh — 用稳定的自签名证书签名 FreeModelMenuBar.app
# 用法:   ./sign.sh
# 效果:   签名 ~/Desktop/FreeModelMenuBar.app
#         首次运行会弹一次密码（Keychain ACL 授权），之后永不弹窗
set -e

SIGNING_IDENTITY="FreeModel Dev Signing"
APP_PATH="$HOME/Desktop/FreeModelMenuBar.app"

# 1. 确保自签名证书存在
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

# 2. 获取证书 SHA-1 哈希
CERT_HASH=$(security find-identity 2>/dev/null | grep "$SIGNING_IDENTITY" | head -1 | awk '{print $2}')
if [ -z "$CERT_HASH" ]; then
    echo "❌ 找不到签名证书 '$SIGNING_IDENTITY'"
    exit 1
fi

# 3. 清理扩展属性（macOS Sequoia 桌面文件可能带 com.apple.fileprovider 属性）
echo "🧹 清理扩展属性..."
xattr -rc "$APP_PATH" 2>/dev/null || true

# 4. 签名
echo "🔏 签名 $APP_PATH ..."
codesign --force --deep --timestamp=none --sign "$CERT_HASH" "$APP_PATH"
echo "✅ 签名完成！证书: $SIGNING_IDENTITY ($CERT_HASH)"

# 5. 验证
echo "🔍 验证签名..."
codesign -dv "$APP_PATH" 2>&1 | grep -E "Signed|Authority|Team"
echo "✅ 验证通过"

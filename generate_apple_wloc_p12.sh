#!/bin/bash

set -euo pipefail

# 生成应用本地代理需要的证书文件。
# 产物包含：
# 1. 根证书：安装到 iPhone 后，需要在“设置 -> 通用 -> 关于本机 -> 证书信任设置”里手动完全信任。
# 2. 服务端 p12：内置到 Packet Tunnel 扩展资源里，用于代理 gs-loc 的 TLS 握手。
# 3. 服务端私钥：只用于生成 p12，p12 已经包含该私钥；运行时不需要单独导入 .key 文件。

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CERTIFICATE_BRAND="WLoc8.com"
OUTPUT_DIR="$SCRIPT_DIR/app_wloc_certs"
P12_PASSWORD="1"
FORCE_WRITE=1
COPY_APP_RESOURCES=1

print_usage() {
  echo "用法：$0 [选项]"
  echo ""
  echo "选项："
  echo "  -o, --output DIR       证书输出目录，默认：$OUTPUT_DIR"
  echo "  -p, --password PASS    p12 密码，默认：$P12_PASSWORD"
  echo "  -f, --force            如果输出目录已有文件，允许覆盖（默认行为）"
  echo "  --no-overwrite         如果输出目录已有文件，直接退出"
  echo "  --no-app-copy          不把证书同步到 App/Extension 资源目录"
  echo "  -h, --help             显示帮助"
  echo ""
  echo "示例："
  echo "  $0 --password 123456"
  echo "  $0 --output /tmp/wloc-certs --password 123456 --force"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    -o|--output)
      OUTPUT_DIR="$2"
      shift 2
      ;;
    -p|--password)
      P12_PASSWORD="$2"
      shift 2
      ;;
    -f|--force)
      FORCE_WRITE=1
      shift
      ;;
    --no-overwrite)
      FORCE_WRITE=0
      shift
      ;;
    --no-app-copy)
      COPY_APP_RESOURCES=0
      shift
      ;;
    -h|--help)
      print_usage
      exit 0
      ;;
    *)
      echo "未知参数：$1"
      print_usage
      exit 1
      ;;
  esac
done

if ! command -v openssl >/dev/null 2>&1; then
  echo "错误：未找到 openssl，请先安装或确认系统 PATH。"
  exit 1
fi

ROOT_KEY="$OUTPUT_DIR/AppWLocRootCA.key"
ROOT_CERT_PEM="$OUTPUT_DIR/AppWLocRootCA.pem"
ROOT_CERT_CER="$OUTPUT_DIR/AppWLocRootCA.cer"
SERVER_KEY="$OUTPUT_DIR/AppWLocProxy.key"
SERVER_CSR="$OUTPUT_DIR/AppWLocProxy.csr"
SERVER_CERT="$OUTPUT_DIR/AppWLocProxy.pem"
SERVER_P12="$OUTPUT_DIR/AppWLocProxy.p12"
OPENSSL_CONF="$OUTPUT_DIR/app_wloc_openssl.cnf"

if [[ -d "$OUTPUT_DIR" && "$FORCE_WRITE" -ne 1 ]]; then
  if [[ -n "$(ls -A "$OUTPUT_DIR" 2>/dev/null)" ]]; then
    echo "错误：输出目录已有文件：$OUTPUT_DIR"
    echo "如需覆盖，请添加 --force。"
    exit 1
  fi
fi

mkdir -p "$OUTPUT_DIR"

run_quiet() {
  local description="$1"
  shift
  local log_file="$OUTPUT_DIR/openssl_error.log"
  if ! "$@" >"$log_file" 2>&1; then
    echo "错误：$description 失败。"
    echo "OpenSSL 输出："
    cat "$log_file"
    exit 1
  fi
  rm -f "$log_file"
}

cat > "$OPENSSL_CONF" <<EOF
[ req ]
default_bits = 2048
prompt = no
default_md = sha256
distinguished_name = dn
req_extensions = server_req

[ dn ]
C = CN
O = $CERTIFICATE_BRAND
OU = $CERTIFICATE_BRAND Proxy
CN = gs-loc.apple.com

[ root_ca ]
subjectKeyIdentifier = hash
authorityKeyIdentifier = keyid:always,issuer
basicConstraints = critical, CA:true
keyUsage = critical, digitalSignature, keyCertSign, cRLSign

[ server_req ]
subjectAltName = @alt_names

[ server_cert ]
basicConstraints = critical, CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth
subjectAltName = @alt_names

[ alt_names ]
DNS.1 = gs-loc.apple.com
DNS.2 = gs-loc-cn.apple.com
EOF

echo "开始生成 $CERTIFICATE_BRAND 证书..."
echo "输出目录：$OUTPUT_DIR"

# 生成根证书。根证书只用于本机测试环境，私钥请不要外发。
run_quiet "生成根证书私钥" openssl genrsa -out "$ROOT_KEY" 2048
run_quiet "生成根证书" openssl req \
  -x509 \
  -new \
  -nodes \
  -key "$ROOT_KEY" \
  -sha256 \
  -days 3650 \
  -out "$ROOT_CERT_PEM" \
  -subj "/C=CN/O=$CERTIFICATE_BRAND/OU=$CERTIFICATE_BRAND Proxy/CN=$CERTIFICATE_BRAND Root CA" \
  -extensions root_ca \
  -config "$OPENSSL_CONF"

# iOS 安装根证书时，.cer 文件更方便直接分享或 AirDrop。
run_quiet "导出根证书 CER" openssl x509 -in "$ROOT_CERT_PEM" -outform DER -out "$ROOT_CERT_CER"

# 生成服务端证书，并加入两个定位服务域名的 SAN。
run_quiet "生成服务端私钥" openssl genrsa -out "$SERVER_KEY" 2048
run_quiet "生成服务端 CSR" openssl req \
  -new \
  -key "$SERVER_KEY" \
  -out "$SERVER_CSR" \
  -config "$OPENSSL_CONF"
run_quiet "签发服务端证书" openssl x509 \
  -req \
  -in "$SERVER_CSR" \
  -CA "$ROOT_CERT_PEM" \
  -CAkey "$ROOT_KEY" \
  -CAcreateserial \
  -out "$SERVER_CERT" \
  -days 825 \
  -sha256 \
  -extensions server_cert \
  -extfile "$OPENSSL_CONF"

# p12 是 App 内导入的文件，密码要和 UI 里保存的密码一致。
# 使用 legacy PBE/MAC，避免 iOS 16 的 SecPKCS12Import 无法解析 OpenSSL 3
# 默认的 PBES2/AES/SHA256 p12 并返回 errSecAuthFailed(-25293)。
run_quiet "生成 p12" openssl pkcs12 \
  -export \
  -legacy \
  -inkey "$SERVER_KEY" \
  -in "$SERVER_CERT" \
  -certfile "$ROOT_CERT_PEM" \
  -out "$SERVER_P12" \
  -name "$CERTIFICATE_BRAND Proxy" \
  -caname "$CERTIFICATE_BRAND Root CA" \
  -keypbe PBE-SHA1-3DES \
  -certpbe PBE-SHA1-3DES \
  -macalg sha1 \
  -passout "pass:$P12_PASSWORD"

if [[ "$COPY_APP_RESOURCES" -eq 1 ]]; then
  mkdir -p "$SCRIPT_DIR/Resources/iOS" "$SCRIPT_DIR/Resources/macOS" "$SCRIPT_DIR/Resources/Tunnel"
  cp "$ROOT_CERT_CER" "$SCRIPT_DIR/Resources/iOS/AppWLocRootCA.cer"
  cp "$ROOT_CERT_CER" "$SCRIPT_DIR/Resources/macOS/AppWLocRootCA.cer"
  cp "$SERVER_P12" "$SCRIPT_DIR/Resources/iOS/AppWLocProxy.p12"
  cp "$SERVER_P12" "$SCRIPT_DIR/Resources/macOS/AppWLocProxy.p12"
  cp "$SERVER_P12" "$SCRIPT_DIR/Resources/Tunnel/AppWLocProxy.p12"
fi

echo ""
echo "生成完成："
echo "  根证书 PEM：$ROOT_CERT_PEM"
echo "  根证书 CER：$ROOT_CERT_CER"
echo "  服务端证书：$SERVER_CERT"
echo "  服务端中间私钥：$SERVER_KEY"
echo "  扩展内置 p12：$SERVER_P12"
echo "  p12 密码：$P12_PASSWORD"
if [[ "$COPY_APP_RESOURCES" -eq 1 ]]; then
  echo "  iOS App 根证书：$SCRIPT_DIR/Resources/iOS/AppWLocRootCA.cer"
  echo "  macOS App 根证书：$SCRIPT_DIR/Resources/macOS/AppWLocRootCA.cer"
  echo "  App 内置 p12：$SCRIPT_DIR/Resources/iOS/AppWLocProxy.p12 / $SCRIPT_DIR/Resources/macOS/AppWLocProxy.p12"
  echo "  扩展内置 p12：$SCRIPT_DIR/Resources/Tunnel/AppWLocProxy.p12"
fi
echo ""
echo "手机端操作："
echo "  1. 把 $CERTIFICATE_BRAND 根证书安装到 iPhone。"
echo "  2. 到“设置 -> 通用 -> 关于本机 -> 证书信任设置”里完全信任该根证书。"
echo "  3. p12 会随扩展内置，用户不需要手动导入。"
echo "macOS 端操作："
echo "  1. 下载 $CERTIFICATE_BRAND 根证书后，打开“钥匙串访问”并选择左侧的“系统”钥匙串。"
echo "  2. 选择菜单“文件 -> 导入项目…”，手动导入根证书；不要双击证书直接安装。"
echo "  3. 在“系统”钥匙串中把该根证书设置为始终信任。"
echo ""
echo "注意：根证书私钥和服务端中间私钥都只用于生成证书，请不要提交、上传或外发。"
echo "      运行时只需要内置代理 p12，不需要单独导入代理 key。"

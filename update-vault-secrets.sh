#!/bin/bash
# =============================================================
# Script cập nhật secrets vào Vault từ host (không cần vault CLI)
# Chạy: ./update-vault-secrets.sh
# =============================================================
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
  set -a; source "$SCRIPT_DIR/.env"; set +a
else
  echo "❌ Không tìm thấy .env tại $SCRIPT_DIR/.env"; exit 1
fi

TOKEN="${APP_F4_PASS:-f4security}"
VAULT_URL="https://vault.${DOMAIN:-phungvip.io.vn}"

echo "🔐 Kết nối Vault: $VAULT_URL"
HEALTH=$(curl -sf -H "X-Vault-Token: $TOKEN" "$VAULT_URL/v1/sys/health" 2>&1) || {
  echo "❌ Không kết nối được Vault!"; exit 1
}
SEALED=$(echo "$HEALTH" | python3 -c "import sys,json; print(json.load(sys.stdin).get('sealed','?'))" 2>/dev/null)
echo "   sealed: $SEALED"

PAYLOAD=$(python3 -c "
import json, os
data = {
    'domain':               os.environ.get('DOMAIN', ''),
    'app-f4-pass':          os.environ.get('APP_F4_PASS', ''),
    'client-id':            os.environ.get('OIDC_CLIENT_ID', ''),
    'client-secret':        os.environ.get('OIDC_CLIENT_SECRET', ''),
    's2s-client-id':        os.environ.get('S2S_CLIENT_ID', ''),
    's2s-client-secret':    os.environ.get('S2S_CLIENT_SECRET', ''),
    'zai-api-key':          os.environ.get('ZAI_API_KEY', ''),
    'graphhopper-api-key':  os.environ.get('GRAPHHOPPER_API_KEY', ''),
    'vnpay-tmn-code':       os.environ.get('VNPAY_TMN_CODE', ''),
    'vnpay-hash-secret':    os.environ.get('VNPAY_HASH_SECRET', ''),
    'vnpay-pay-url':        os.environ.get('VNPAY_PAY_URL', ''),
    'vnpay-query-url':      os.environ.get('VNPAY_QUERY_URL', ''),
    'vnpay-refund-url':     os.environ.get('VNPAY_REFUND_URL', ''),
    'vnpay-return-url':     os.environ.get('VNPAY_RETURN_URL', ''),
    'momo-partner-code':    os.environ.get('MOMO_PARTNER_CODE', ''),
    'momo-access-key':      os.environ.get('MOMO_ACCESS_KEY', ''),
    'momo-secret-key':      os.environ.get('MOMO_SECRET_KEY', ''),
    'momo-endpoint':        os.environ.get('MOMO_ENDPOINT', ''),
    'momo-return-url':      os.environ.get('MOMO_RETURN_URL', ''),
    'momo-notify-url':      os.environ.get('MOMO_NOTIFY_URL', ''),
    'zalopay-app-id':       os.environ.get('ZALOPAY_APP_ID', ''),
    'zalopay-key1':         os.environ.get('ZALOPAY_KEY1', ''),
    'zalopay-key2':         os.environ.get('ZALOPAY_KEY2', ''),
    'zalopay-endpoint':     os.environ.get('ZALOPAY_ENDPOINT', ''),
    'zalopay-callback-url': os.environ.get('ZALOPAY_CALLBACK_URL', ''),
}
print(json.dumps({'data': data}))
")

echo "📦 Pushing secrets lên Vault..."
RESULT=$(curl -sf \
  -H "X-Vault-Token: $TOKEN" \
  -H "Content-Type: application/merge-patch+json" \
  -X PATCH \
  "$VAULT_URL/v1/secret/data/infrastructure" \
  -d "$PAYLOAD")

VERSION=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin).get('data',{}).get('version','?'))" 2>/dev/null)
echo "✅ Vault updated! (version: $VERSION)"
echo ""
echo "💡 Restart services để áp dụng:"
echo "   cd ~/ridehub/infra/vps-microservices"
echo "   docker compose restart ms_booking ms_route"

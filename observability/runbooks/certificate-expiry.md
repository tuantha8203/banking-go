# CertificateExpiringSoon / CertificateNotReady
- Mức / NFR / AD: warning (< 14 ngày) · critical (< 3 ngày hoặc NotReady) · NFR-S7 · AD-10

## Ý nghĩa
Certificate của cert-manager sắp hết hạn mà chưa renew, hoặc đang `Ready=False` (wildcard `*.kind.localhost`, CA nội bộ, leaf mTLS `<svc>-mtls`).

## Tác động
Hết hạn → HTTPS qua Traefik hoặc mTLS nội bộ hỏng, toàn bộ API/SPA không truy cập được.

## Kiểm tra (chỉ đọc)
- `bin/kubectl get certificates -A`; `bin/kubectl -n <ns> describe certificate <name>` (Events, lý do renew fail)
- `bin/kubectl get clusterissuer` — `kind-ca`, `bg-internal-ca`, `selfsigned` có Ready?
- `bin/kubectl -n cert-manager logs deploy/cert-manager | grep -i <name>`
- PromQL: `certmanager_certificate_expiration_timestamp_seconds - time()`

## Xử lý
- Sửa issuer/Certificate trong `deploy/platform/cert-manager-issuers/kind/` hoặc values chart qua PR → cert-manager renew.

## Không được làm
- Tắt TLS/mTLS tạm thời; tự xóa Secret CA (`kind-root-ca`, `bg-internal-root-ca`).

## Đóng sự cố
Certificate `Ready=True`, hết hạn > 14 ngày, alert resolved.

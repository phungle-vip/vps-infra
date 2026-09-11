# RideHub VPS Infrastructure (vps-infra)

Hạ tầng trung tâm (Central Infrastructure) dành cho hệ sinh thái Microservices của **RideHub**, chạy trên VPS sử dụng Docker Compose, định tuyến qua Cloudflare Tunnel và bảo mật Zero Trust.

---

## 1. Kiến trúc tổng quan (Architecture Overview)

Toàn bộ hạ tầng được đóng gói thành các container Docker và kết nối qua mạng nội bộ `ridehub-network`:

```
                                  INTERNET
                                     │
                        Cloudflare Edge (SSL / CDN)
                                     │ (Zero Trust Access - Keycloak OIDC)
                                     ▼
                            cloudflared (QUIC)
                                     │
                                     ▼
                                Nginx (Port 80)
      ┌─────────────┬─────────────┼─────────────┬─────────────┬─────────────┐
      ▼             ▼             ▼             ▼             ▼             ▼
  Keycloak       Consul       Kafka UI      RedisInsight    Vault        Grafana
 (Auth OIDC)    (KV/Disc)     (Kafka GUI)    (Redis GUI)   (Secrets)   (Dashboard)
      │                                                                     ▲
      ▼                                                                     │
    MySQL                                                             Loki / Promtail
  (Database)                                                            (Log Store)
      │
  Kafka KRaft ◄── Elasticsearch ◄── Redis Cache
(Event Stream)    (Pathfinding)       (Cache)
```

---

## 2. Cấu trúc thư mục (Directory Structure)

```
infra/vps-infra/
├── .env.example                               # File mẫu biến môi trường
├── docker-compose.yml                         # File điều phối toàn bộ các services hạ tầng & auto-init
├── INSTALLATION.md                            # 📘 Hướng dẫn cài đặt chi tiết & phân tích biến .env
├── README.md                                  # Tài liệu kiến trúc & vận hành tổng quan
│
└── central-server-config/                     # Toàn bộ cấu hình & scripts runtime của hạ tầng
    ├── scripts/                               # [VẬN HÀNH SAU NÀY] Thư mục do Grafana Admin quản lý
    │   ├── backup-vps.sh                      # Sao lưu Docker volumes & code lên Google Drive
    │   ├── renew-kafka-ssl.sh                 # Tái cấp chứng chỉ SSL Kafka khi đổi Domain
    │   ├── reload-consul-kv.sh                # Đồng bộ lại toàn bộ cấu hình KV lên Consul
    │   └── cli.txt                            # Lệnh CLI thao tác hạ tầng tóm tắt
    │
    ├── cloudflared/                           # Cấu hình Cloudflare Tunnel & Ingress
    │   ├── config.yml.template                # Template ingress rules (tự động render ra config.yml)
    │   └── credentials.json.example           # File mẫu credentials
    │
    ├── consul/                                # Cấu hình Consul Service Discovery & KV
    │   ├── consul.hcl                         # File cấu hình server & ACL token
    │   ├── KV/                                # Chứa file yaml config cho từng microservice
    │   ├── consul-loader.sh                   # [GỘP LẦN ĐẦU] Tự động cấp ACL Tokens & Nạp file KV
    │   └── sync-kv-to-files.sh                # Consul Watcher tự đồng bộ KV khi sửa trên UI
    │
    ├── kafka/                                 # Cấu hình Kafka KRaft
    │   ├── kraft-config.properties.template   # Template KRaft (tự động render khi start container)
    │   ├── kafka-init.sh                      # [GỘP LẦN ĐẦU] Tự sinh SSL certs & gán quyền ACLs
    │   └── tls/                               # Thư mục chứa SSL certificates và keystores
    │
    ├── keycloak/                              # Cấu hình Keycloak 26 (Quarkus)
    │   ├── jhipster-realm.json.template       # Template Realm (tự động render khi start container)
    │   ├── keycloak-entrypoint.sh             # [LẦN ĐẦU] Entrypoint render realm & đồng bộ domain
    │   └── keycloak-health-check.sh           # Script healthcheck cho Keycloak container
    │
    ├── nginx/                                 # Cấu hình Nginx Reverse Proxy
    │   ├── nginx.conf                         # Cấu hình lõi Nginx
    │   └── default.conf.template              # Template định tuyến domain con -> containers
    │
    ├── observability/                         # Cụm giám sát & Logging
    │   ├── loki-config.yaml                   # Cấu hình lưu trữ log Loki
    │   ├── prometheus.yml                     # Cấu hình Prometheus
    │   ├── promtail-config.yaml               # Cấu hình thu thập log Promtail từ Docker socket
    │   └── grafana/                           # Provisioning datasources và dashboards Ops Control
    │
    └── vault/                                 # Cấu hình HashiCorp Vault
        ├── vault.hcl                          # File cấu hình Vault server
        └── vault-startup.sh                   # [LẦN ĐẦU] Khởi động & tự động seed secrets từ .env
```

---

## 3. Cài đặt & Khởi chạy nhanh (Quickstart)

> 📘 **Xem hướng dẫn chi tiết từng bước và phân loại biến `.env` tại [INSTALLATION.md](file:///home/phungvip/ridehub/infra/vps-infra/INSTALLATION.md)**.

### Tóm tắt 3 bước triển khai:

1. **Chuẩn bị môi trường**:
   ```bash
   cd infra/vps-infra
   cp .env.example .env
   nano .env   # Điền DOMAIN và APP_F4_PASS (Xem chi tiết tại INSTALLATION.md)
   ```

2. **Khởi chạy toàn bộ hạ tầng (Zero-Touch Auto-Init)**:
   ```bash
   docker compose up -d
   ```
   *(Toàn bộ các container `infra-init`, `kafka`, `consul-loader`, `keycloak`, `vault` sẽ tự động phối hợp sinh SSL, nạp secrets, cấu hình ACLs và nạp KV).*

3. **Quản trị & Thực thi Script tác vụ qua Grafana Admin**:
   - Truy cập Grafana tại `https://grafana.<DOMAIN>`.
   - Vào Dashboard: **"Trạm Điều Khiển Webhook & Tác Vụ Ops"** (`/d/ops-control`).
   - Kéo xuống mục **🛠️ Quản Trị Kịch Bản Vận Hành Hạ Tầng** để kích hoạt hoặc copy lệnh CLI cho các script (`backup-vps.sh`, `renew-kafka-ssl.sh`, `reload-consul-kv.sh`) với các tham số mong muốn.

---

## 5. Bảng Endpoints & Cổng dịch vụ (Service Endpoints)

| Dịch vụ | Domain Public | Cổng nội bộ | Xác thực bảo vệ |
| :--- | :--- | :--- | :--- |
| **Keycloak Admin** | `https://keycloak.<DOMAIN>` | `keycloak:9080` | Public (Login bằng Keycloak Admin) |
| **Kafka UI** | `https://kafdrop.<DOMAIN>` | `kafka-ui:8080` | Cloudflare Access -> Keycloak OIDC |
| **Consul UI** | `https://consul.<DOMAIN>` | `consul:8500` | Cloudflare Access -> Keycloak OIDC |
| **RedisInsight** | `https://redisinsight.<DOMAIN>` | `redisinsight:5540` | Cloudflare Access -> Keycloak OIDC |
| **HashiCorp Vault** | `https://vault.<DOMAIN>` | `vault:8200` | Cloudflare Access -> Keycloak OIDC |
| **Grafana Monitoring**| `https://grafana.<DOMAIN>` | `grafana:3000` | Cloudflare Access -> Keycloak OIDC |
| **API Gateway** | `https://gateway.<DOMAIN>` | `gateway:8080` | Public (Spring Cloud Gateway) |
| **Kafka External SSL**| `<DOMAIN>:9094` | `kafka:9092` | SSL Keystore / Mutual TLS |
| **Kafka OAuth SASL** | `<DOMAIN>:9093` | `kafka:9093` | SASL_SSL với Keycloak JWT |
| **Redis Server** | `127.0.0.1:6379` | `redis:6379` | Mật khẩu `APP_F4_PASS` (Localhost only) |
| **Elasticsearch** | `127.0.0.1:9200` | `elasticsearch:9200`| Localhost only |

---

## 6. Vận hành & Bảo trì (Operations & Maintenance)

### Xem Logs các service
```bash
# Xem log Nginx
docker compose logs -f nginx

# Xem log Cloudflare Tunnel
docker compose logs -f cloudflared

# Xem log Keycloak
docker compose logs -f keycloak

# Xem log Kafka
docker compose logs -f kafka
```

### Khởi động lại dịch vụ
```bash
docker compose restart <service_name>
```

### Sao lưu VPS lên Google Drive
Script `backup-vps.sh` hỗ trợ đóng gói các Docker volumes (`vault_data`, `kafka-oauth-data`, `grafana_data`, `elasticsearch_data`, `redisinsight_data`) và mã nguồn, tự động đẩy lên Google Drive qua `rclone`:
```bash
./backup-vps.sh
```
*(Yêu cầu đã cấu hình remote `ggdrive:` trong rclone).*


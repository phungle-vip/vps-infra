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
├── README.md                                  # Tài liệu hướng dẫn sử dụng
│
└── central-server-config/                     # Toàn bộ cấu hình & scripts runtime của hạ tầng
    ├── scripts/                               # Scripts quản trị & backup
    │   ├── backup-vps.sh                      # Script sao lưu Docker volumes & code lên Google Drive
    │   └── cli.txt                            # Lệnh CLI thao tác hạ tầng tóm tắt
    │
    ├── cloudflared/                           # Cấu hình Cloudflare Tunnel & Zero Trust
    │   ├── config.yml.template                # Template ingress rules (tự động render ra config.yml)
    │   ├── credentials.json.example           # File mẫu credentials
    │   └── setup-cloudflare.sh                # Script duy nhất thiết lập Keycloak OIDC, Apps, SSH & WARP
    │
    ├── consul/                                # Cấu hình Consul Service Discovery & KV
    │   ├── consul.hcl                         # File cấu hình server & ACL token
    │   ├── KV/                                # Chứa file yaml config cho từng microservice
    │   ├── init-consul-acl.sh                 # (Tự động chạy) Khởi tạo ACL policies, roles và tokens
    │   └── upload-consul-file-with-token.sh   # (Tự động chạy) Đẩy KV lên Consul có ACL
    │
    ├── kafka/                                 # Cấu hình Kafka KRaft
    │   ├── kraft-config.properties.template   # Template KRaft (tự động render khi start container)
    │   ├── generate-kafka-ssl.sh              # (Tự động chạy) Tự sinh SSL certs & keystores nếu chưa có
    │   ├── init-kafka-acls.sh                 # (Tự động chạy) Khởi tạo ACLs cho Microservices
    │   └── tls/                               # Thư mục chứa SSL certificates và keystores
    │
    ├── keycloak/                              # Cấu hình Keycloak 26 (Quarkus)
    │   ├── jhipster-realm.json.template       # Template Realm (tự động render khi start container)
    │   ├── keycloak-entrypoint.sh             # (Tự động chạy) Entrypoint render realm & đồng bộ domain
    │   └── keycloak-health-check.sh           # Script healthcheck cho Keycloak container
    │
    ├── nginx/                                 # Cấu hình Nginx Reverse Proxy
    │   ├── nginx.conf                         # Cấu hình lõi Nginx
    │   └── default.conf.template              # Template định tuyến domain con -> containers (tự sinh)
    │
    ├── observability/                         # Cụm giám sát & Logging
    │   ├── loki-config.yaml                   # Cấu hình lưu trữ log Loki
    │   ├── prometheus.yml                     # Cấu hình Prometheus
    │   ├── promtail-config.yaml               # Cấu hình thu thập log Promtail từ Docker socket
    │   └── grafana/                           # Provisioning datasources và dashboards (tự khởi tạo)
    │
    └── vault/                                 # Cấu hình HashiCorp Vault
        ├── vault.hcl                          # File cấu hình Vault server
        └── vault-startup.sh                   # (Tự động chạy) Khởi động & tự động seed secrets từ .env
```

---

## 3. Yêu cầu hệ thống (Prerequisites)

* **Hệ điều hành:** Linux (khuyên dùng Ubuntu 22.04 LTS hoặc 24.04 LTS, Debian 12).
* **Dung lượng ổ cứng:** Tối thiểu **30 GB** (khuyến nghị **50 GB - 100 GB** vì Kafka, Elasticsearch và Keycloak chiếm nhiều dung lượng lưu trữ).
* **Phần mềm duy nhất cần cài trên host:**
  * Docker Engine (>= 24.0) & Docker Compose (v2).
  * `cloudflared` CLI (nếu dùng Cloudflare Tunnel).
  * `git`.
  *(Không cần cài JDK, keytool, python hay các công cụ phức tạp trên host; toàn bộ đều tự động bên trong container).*

---

## 4. Hướng dẫn thiết lập từ đầu (Setup Guide)

### Bước 1: Khởi tạo file môi trường `.env`
Sao chép file mẫu và điền các mật khẩu bảo mật:
```bash
cd infra/vps-infra
cp .env.example .env
nano .env
```
Các biến quan trọng cần chú ý:
* `APP_F4_PASS`: Mật khẩu master cho các dịch vụ dữ liệu nội bộ (Redis, Grafana, Kafka SSL keystore).
* `DOMAIN`: Tên miền của bạn (ví dụ: `phungvip.io.vn`).
* `KEYCLOAK_ADMIN` & `KEYCLOAK_ADMIN_PASSWORD`: Tài khoản quản trị Keycloak.
* `CF_API_TOKEN`: Cloudflare API Token (nếu muốn tự động cấu hình Zero Trust Access).

---

### Bước 2: Thiết lập Cloudflare Tunnel (Chạy 1 lần trên Host)

1. **Đăng nhập Cloudflare trên VPS:**
   ```bash
   cloudflared tunnel login
   ```

2. **Tạo Tunnel mới:**
   ```bash
   cloudflared tunnel create ridehub-tunnel
   ```

3. **Sao chép file credentials vào thư mục cấu hình:**
   ```bash
   cp ~/.cloudflared/<TUNNEL_ID>.json central-server-config/cloudflared/credentials.json
   chmod 644 central-server-config/cloudflared/credentials.json
   ```

4. **Định tuyến DNS trên Cloudflare về Tunnel:**
   ```bash
   cloudflared tunnel route dns -f ridehub-tunnel "*.phungvip.io.vn"
   cloudflared tunnel route dns -f ridehub-tunnel "phungvip.io.vn"
   ```

---

### Bước 3: Khởi chạy toàn bộ hạ tầng (Zero-Touch Auto-Init)

Bạn **KHÔNG CẦN** chạy bất kỳ script sh nào để sinh chứng chỉ hay cấu hình. Chỉ cần chạy:
```bash
docker compose up -d
```
Docker Compose sẽ tự động thực hiện:
* Container `infra-init` tự động render `cloudflared/config.yml`, copy dashboard Grafana và chuẩn bị token files.
* Container `kafka` tự sinh SSL Certificates (`.jks`, `.pem`), format KRaft storage và thiết lập ACLs.
* Container `consul` và `consul-config-loader` tự động tạo ACL Policies, Roles, Tokens và nạp file KV.
* Container `vault` tự động nạp toàn bộ secrets từ `.env`.
* Container `keycloak` tự động render realm từ template và khởi chạy OIDC.

Kiểm tra trạng thái các container:
```bash
docker compose ps
```
*(Đợi 30-60 giây để toàn bộ 15 container chuyển sang trạng thái `Up` và `healthy`).*

---

### Bước 4: (Tùy chọn) Cấu hình bảo mật Cloudflare Zero Trust Access với Keycloak OIDC

Nếu bạn muốn tự động liên kết Keycloak OIDC với Cloudflare Zero Trust để bảo vệ các trang quản trị và SSH:
```bash
./central-server-config/cloudflared/setup-cloudflare.sh
```
*(Hỗ trợ cờ `--apps` chỉ cài Web UI, `--ssh` chỉ cài SSH & WARP, hoặc mặc định cài toàn bộ).*

---

## 5. Bảng Endpoints & Cổng dịch vụ (Service Endpoints)

| Dịch vụ | Domain Public | Cổng nội bộ | Xác thực bảo vệ |
| :--- | :--- | :--- | :--- |
| **Keycloak Admin** | `https://keycloak.phungvip.io.vn` | `keycloak:9080` | Public (Login bằng Keycloak Admin) |
| **Kafka UI** | `https://kafdrop.phungvip.io.vn` | `kafka-ui:8080` | Cloudflare Access -> Keycloak OIDC |
| **Consul UI** | `https://consul.phungvip.io.vn` | `consul:8500` | Cloudflare Access -> Keycloak OIDC |
| **RedisInsight** | `https://redisinsight.phungvip.io.vn` | `redisinsight:5540` | Cloudflare Access -> Keycloak OIDC |
| **HashiCorp Vault** | `https://vault.phungvip.io.vn` | `vault:8200` | Cloudflare Access -> Keycloak OIDC |
| **Grafana Monitoring**| `https://grafana.phungvip.io.vn` | `grafana:3000` | Cloudflare Access -> Keycloak OIDC |
| **API Gateway** | `https://gateway.phungvip.io.vn` | `gateway:8080` | Public (Spring Cloud Gateway) |
| **Kafka External SSL**| `phungvip.io.vn:9094` | `kafka:9092` | SSL Keystore / Mutual TLS |
| **Kafka OAuth SASL** | `phungvip.io.vn:9093` | `kafka:9093` | SASL_SSL với Keycloak JWT |
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


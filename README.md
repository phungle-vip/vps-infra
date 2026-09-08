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
├── docker-compose.yml                         # File điều phối toàn bộ 15 services hạ tầng
├── README.md                                  # Tài liệu hướng dẫn sử dụng
│
└── central-server-config/                     # Toàn bộ cấu hình & scripts runtime của hạ tầng
    ├── scripts/                               # Scripts quản trị & backup
    │   ├── backup-vps.sh                      # Script sao lưu Docker volumes & code lên Google Drive
    │   └── cli.txt                            # Hướng dẫn & lệnh thao tác hạ tầng
    │
    ├── cloudflared/                           # Cấu hình Cloudflare Tunnel & Zero Trust
    │   ├── config.yml                         # Ingress rules trỏ domain về Nginx
    │   ├── credentials.json.example           # File mẫu credentials
    │   └── setup-cloudflare-access.sh         # Script tự động tạo Access App & Keycloak OIDC
    │
    ├── consul/                                # Cấu hình Consul Service Discovery & KV
    │   ├── consul.hcl                         # File cấu hình server & ACL token
    │   ├── KV/                                # Chứa file yaml config cho từng microservice
    │   └── upload-consul-file-with-token.sh   # Script tự động đẩy KV lên Consul có ACL
    │
    ├── kafka/                                 # Cấu hình Kafka KRaft
    │   ├── kraft-config.properties            # Cấu hình cụm Kafka KRaft (thay thế ZooKeeper)
    │   ├── generate-kafka-ssl.sh              # Script sinh CA, SSL certs và Keystore/Truststore JKS
    │   └── tls/                               # Chứa certs và keystore đã sinh
    │
    ├── keycloak/                              # Cấu hình Keycloak 26 (Quarkus)
    │   ├── jhipster-realm.json                # Realm cấu hình sẵn các OIDC clients và roles
    │   ├── keycloak-health-check.sh           # Script healthcheck cho Keycloak container
    │   └── keycloak-custom-reg/               # (Submodule) Keycloak Custom Registration SPI plugin
    │
    ├── nginx/                                 # Cấu hình Nginx Reverse Proxy
    │   ├── nginx.conf                         # Cấu hình lõi Nginx
    │   └── default.conf.template              # Template định tuyến domain con -> containers
    │
    ├── observability/                         # Cụm giám sát & Logging
    │   ├── loki-config.yaml                   # Cấu hình lưu trữ log Loki
    │   └── promtail-config.yaml               # Cấu hình thu thập log Promtail từ Docker socket
    │
    └── vault/                                 # Cấu hình HashiCorp Vault
        ├── vault.hcl                          # File cấu hình Vault server
        └── vault-startup.sh                   # Script khởi động và tự động seed secrets
```

---

## 3. Yêu cầu hệ thống (Prerequisites)

* **Hệ điều hành:** Linux (khuyên dùng Ubuntu 22.04 LTS hoặc 24.04 LTS, Debian 12).
* **Dung lượng ổ cứng:** Tối thiểu **30 GB** (khuyến nghị **50 GB - 100 GB** vì Kafka, Elasticsearch và Keycloak chiếm nhiều dung lượng lưu trữ).
* **Phần mềm yêu cầu:**
  * Docker Engine (>= 24.0) & Docker Compose (v2).
  * `cloudflared` CLI cài sẵn trên host VPS.
  * Tên miền đã trỏ NameServer về **Cloudflare**.

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
* **Consul & Vault Tokens**: Token quản trị cao nhất (Highest Role) được tự động sinh và lưu trữ độc lập trong `central-server-config/consul/consul-tokens.env` và `central-server-config/vault/vault-tokens.env` (không còn dùng chung `APP_F4_PASS`).
* `KEYCLOAK_ADMIN` & `KEYCLOAK_ADMIN_PASSWORD`: Tài khoản quản trị Keycloak.
* `CF_API_TOKEN`: Cloudflare API Token (quyền `Account -> Access: Apps and Policies -> Edit` và `Account -> Access: Organizations... -> Edit`).

---

### Bước 2: Thiết lập Cloudflare Tunnel

1. **Đăng nhập Cloudflare trên VPS:**
   ```bash
   cloudflared tunnel login
   ```
   *(Trình duyệt sẽ mở để chọn tên miền của bạn).*

2. **Tạo Tunnel mới:**
   ```bash
   cloudflared tunnel create ridehub-tunnel
   ```
   Lệnh sẽ trả về **Tunnel ID (UUID)** và tạo file credentials tại `~/.cloudflared/<TUNNEL_ID>.json`.

3. **Sao chép file credentials vào thư mục cấu hình:**
   ```bash
   cp ~/.cloudflared/<TUNNEL_ID>.json central-server-config/cloudflared/credentials.json
   chmod 644 central-server-config/cloudflared/credentials.json
   ```

4. **Cập nhật `config.yml`:**
   Mở file `central-server-config/cloudflared/config.yml` và thay `YOUR_TUNNEL_ID` bằng UUID vừa tạo.

5. **Định tuyến DNS trên Cloudflare về Tunnel:**
   ```bash
   cloudflared tunnel route dns -f ridehub-tunnel "*.phungvip.io.vn"
   cloudflared tunnel route dns -f ridehub-tunnel "phungvip.io.vn"
   ```

---

### Bước 3: (Tùy chọn) Sinh lại chứng chỉ SSL cho Kafka nội bộ
Các chứng chỉ mặc định đã được sinh sẵn trong `central-server-config/kafka/tls/`. Nếu bạn đổi tên miền mới, chạy script sau để tạo lại:
```bash
bash central-server-config/kafka/generate-kafka-ssl.sh
```

---

### Bước 4: Khởi chạy toàn bộ hạ tầng
Chạy Docker Compose ở chế độ nền:
```bash
docker compose up -d
```
Kiểm tra trạng thái các container:
```bash
docker compose ps
```
*(Đợi 30-60 giây để toàn bộ 15 container chuyển sang trạng thái `Up` và `healthy`).*

---

### Bước 5: Cấu hình bảo mật Cloudflare Zero Trust Access với Keycloak OIDC

Chạy script tự động cấu hình bảo vệ các trang quản trị:
```bash
./central-server-config/cloudflared/setup-cloudflare-access.sh
```
* **Chức năng:** Script sẽ tự động kết nối tới Cloudflare API, đăng ký Keycloak làm OIDC Identity Provider, và kích hoạt tính năng **Auto-redirect sang Keycloak Login** cho toàn bộ 5 dịch vụ quản trị nội bộ.

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


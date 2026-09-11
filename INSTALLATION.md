# Hướng Dẫn Cài Đặt & Cấu Hình Biến Môi Trường VPS-INFRA

Tài liệu này hướng dẫn chi tiết quy trình triển khai hạ tầng trung tâm **RideHub (vps-infra)** trên VPS, giải thích cặn kẽ ý nghĩa từng biến trong file `.env` (phân định rõ biến cần cho lần đầu và biến cần cho các script sau này).

---

## 1. Yêu cầu tiên quyết trên máy chủ (Host Prerequisites)

Bạn **chỉ cần cài đặt 3 công cụ** cơ bản có quyền quản trị hệ thống trên VPS:
* **Docker Engine** (>= 24.0) & **Docker Compose** (v2).
* **Git** (để clone và quản lý mã nguồn).
* **Cloudflared CLI** (nếu sử dụng Cloudflare Tunnel để đưa dịch vụ ra Internet).

> [!NOTE]
> Bạn **KHÔNG CẦN** cài đặt Java JDK, `keytool`, `openssl`, `python3` hay các thư viện phức tạp trên host. Toàn bộ các công cụ này đã được đóng gói và tự động thực thi bên trong các Docker containers.

---

## 2. Hướng dẫn cấu hình File `.env`

Sao chép file mẫu:
```bash
cd infra/vps-infra
cp .env.example .env
nano .env
```

Để thuận tiện cho việc quản lý, các biến môi trường được phân chia thành **2 cấp độ**:

### 🟢 Cấp độ 1: Bắt buộc để khởi chạy `docker compose up -d` lần đầu
Đây là các biến cốt lõi giúp các container khởi động, kết nối nội bộ và tự sinh cấu hình:

| Tên biến | Giá trị mẫu / Gợi ý | Giải thích chi tiết & Lưu ý |
|---|---|---|
| **`DOMAIN`** | `phungvip.io.vn` | **Bắt buộc**: Tên miền chính đã trỏ NameServer về Cloudflare. Nginx, Keycloak, Kafka SSL và Cloudflared sẽ tự động lấy biến này để sinh cấu hình FQDN. |
| **`APP_F4_PASS`** | `Mật_khẩu_mạnh_của_bạn` | **Bắt buộc**: Mật khẩu master dùng chung cho Redis (`requirepass`), Grafana Admin, Consul Master Token (fallback), và Kafka SSL keystore. |
| **`KEYCLOAK_ADMIN`** | `admin` | Tên tài khoản quản trị cao nhất của Keycloak. |
| **`KEYCLOAK_ADMIN_PASSWORD`** | `Mật_khẩu_keycloak` | **Bắt buộc**: Mật khẩu quản trị Keycloak để truy cập `https://keycloak.<DOMAIN>`. |
| **`OIDC_CLIENT_ID`** | `web_app` | ID của OpenID Connect Client cho các ứng dụng web và Microservices. |
| **`OIDC_CLIENT_SECRET`** | `0TnpRknqjQYngbnbRW7hKECA8TbR4D7V` | Khóa bí mật OIDC Client. Bản mẫu trong `.env.example` đã khớp với `jhipster-realm.json.template`. |
| **`S2S_CLIENT_ID`** | `svc-admin-bootstrap` | Service Account ID dùng cho giao tiếp liên Microservices và Kafka OAuth. |
| **`S2S_CLIENT_SECRET`** | `EB4eohc7BEY3tw1Rjg7FS8xMLfi95n0n` | Khóa bí mật giao tiếp Service-to-Service giữa các dịch vụ. |
| **`GRAFANA_OIDC_CLIENT_SECRET`** | `0TnpRknqjQYngbnbRW7hKECA8TbR4D7V` | Khóa bí mật cho Grafana đăng nhập một lần (SSO) qua Keycloak. |
| **`TZ`** | `Asia/Ho_Chi_Minh` | Múi giờ hệ thống cho toàn bộ containers. |

---

### 🟡 Cấp độ 2: Dùng cho các Script tác vụ sau này (Những thứ còn thiếu / placeholder trong `.env.example`)
Các biến này **chưa cần điền ngay** khi start Docker lần đầu, nhưng **bắt buộc phải có** khi bạn chạy các script cấu hình bảo mật hoặc sao lưu sau này:

| Tên biến | Trạng thái trong `.env.example` | Script sử dụng | Hướng dẫn cấu hình khi cần |
|---|:---:|:---:|---|
| **`CF_API_TOKEN`** | `your_cloudflare_api_token` (placeholder) | `setup-cloudflare.sh` | **Cần tạo trên Cloudflare**: Vào *Cloudflare Dashboard -> My Profile -> API Tokens -> Create Token*, cấp các quyền:<br>• `Account -> Access: Apps and Policies -> Edit`<br>• `Account -> Access: Organizations, Identity Providers, and Groups -> Edit`. |
| **`CF_ACCOUNT_ID`** | `your_cloudflare_account_id` (placeholder) | `setup-cloudflare.sh` | Lấy từ trang quản trị Cloudflare (mục Overview của Domain hoặc Zero Trust Dashboard). *Nếu đã có `TUNNEL_TOKEN` hoặc `credentials.json`, script sẽ tự động nhận diện.* |
| **`TUNNEL_TOKEN`** | Trống (`TUNNEL_TOKEN=`) | `cloudflared` | Lấy sau khi chạy lệnh `cloudflared tunnel create <name>`. Dùng để container `cloudflared` kết nối vào mạng Cloudflare Edge. |
| **`ADMIN_EMAIL`** | *Chưa có trong file mẫu* | `setup-cloudflare.sh` | Email của bạn (ví dụ: `admin@phungvip.io.vn`). Dùng để gán quyền SSH Zero Trust truy cập VPS. Mặc định nếu không điền sẽ lấy `phungvip@${DOMAIN}`. |
| **`SSH_SUBDOMAIN`** | *Chưa có trong file mẫu* | `setup-cloudflare.sh` | Subdomain cho kết nối SSH (mặc định: `ssh` -> `ssh.<DOMAIN>`). |
| **`REMOTE`** | *Chưa có trong file mẫu* | `backup-vps.sh` | Đường dẫn Google Drive trong `rclone` (ví dụ: `ggdrive:vps-backup`). Cần chạy `rclone config` trên host trước khi dùng script backup. |

---

## 3. Khởi chạy toàn bộ hạ tầng (Zero-Touch Auto-Init)

Sau khi đã hoàn thiện các biến Cấp độ 1 trong file `.env`, bạn chỉ cần chạy một lệnh duy nhất:

```bash
docker compose up -d
```

### Quá trình tự động hóa diễn ra ngầm:
1. **Container `infra-init`** khởi động trước tiên:
   - Tự động điền `${DOMAIN}` vào `central-server-config/cloudflared/config.yml.template` để sinh ra file `config.yml`.
   - Tự động kích hoạt dashboard quản trị `ops-control.json` cho Grafana Admin.
   - Tạo sẵn các file token và thư mục chứng chỉ để Docker mount volumes không bao giờ bị lỗi.
2. **Container `kafka`**:
   - Tự kiểm tra thư mục chứng chỉ: nếu chưa có, tự dùng `openssl` và `keytool` bên trong image Strimzi để sinh CA, Keystore & Truststore JKS.
   - Tự động format KRaft storage và gán ACLs cho Microservices.
3. **Container `consul-config-loader`**:
   - Đợi Consul Server healthy, tự động tạo ACL Policies, Roles và cấp tokens lưu vào `consul/consul-tokens.env`.
   - Nạp toàn bộ các file cấu hình `.yml` trong `consul/KV/` lên Consul Key-Value Store.
4. **Container `vault`**:
   - Tự động mã hóa và đẩy toàn bộ biến `.env` vào Vault KV (`secret/infrastructure`).
5. **Container `keycloak`**:
   - Tự động render realm template và khởi chạy OIDC SSO Server.

Kiểm tra trạng thái toàn bộ dịch vụ:
```bash
docker compose ps
```
*(Đợi 30–60 giây để toàn bộ 15 container chuyển sang trạng thái `Up` hoặc `healthy`).*

---

## 4. Hướng dẫn thực thi các Script sau này

Toàn bộ các script tác vụ sau này được lưu tập trung tại thư mục:
```
central-server-config/scripts/
```

Bạn có thể quản lý và kích hoạt các script này theo **2 cách**:

### Cách 1: Thao tác trực tiếp trên Grafana Admin Dashboard (Khuyến nghị)
1. Đăng nhập vào Grafana: `https://grafana.<DOMAIN>` bằng tài khoản Keycloak Admin.
2. Mở Dashboard: **"Trạm Điều Khiển Webhook & Tác Vụ Ops"** (`/d/ops-control`).
3. Kéo xuống mục **🛠️ Quản Trị Kịch Bản Vận Hành Hạ Tầng (Infrastructure Ops Scripts & Docs)**.
4. Tại đây bạn có thể:
   - Điền trực tiếp các tham số (`Domain`, `Chế độ`, `Remote Backup`, `Cloudflare API Token`).
   - Nhấn nút **⚡ Thực Thi Script** hoặc **📋 Copy CLI** để lấy câu lệnh chuẩn xác đã được điền sẵn biến.
   - Tra cứu bảng tài liệu hướng dẫn chi tiết của từng script ngay trên màn hình.

---

### Cách 2: Chạy trực tiếp qua dòng lệnh CLI trên VPS

#### A. Thiết lập Cloudflare Zero Trust (Bảo vệ Web UI & SSH):
Yêu cầu đã điền `CF_API_TOKEN` vào `.env`:
```bash
# Cấu hình toàn bộ: Keycloak IdP, Web Apps, SSH & WARP
./central-server-config/scripts/setup-cloudflare.sh --all

# Chỉ cấu hình bảo vệ 5 trang Web quản trị (Kafka UI, Consul, Vault, Grafana, Redis)
./central-server-config/scripts/setup-cloudflare.sh --apps

# Chỉ cấu hình SSH Zero Trust & WARP Device Enrollment
./central-server-config/scripts/setup-cloudflare.sh --ssh
```

#### B. Sao lưu dữ liệu VPS lên Google Drive:
Yêu cầu máy chủ đã cài và đăng nhập `rclone`:
```bash
./central-server-config/scripts/backup-vps.sh
```
*(Hoặc truyền đường dẫn remote khác: `REMOTE="my-drive:backup/today" ./central-server-config/scripts/backup-vps.sh`).*

#### C. Tái cấp chứng chỉ SSL Kafka khi đổi Domain:
```bash
./central-server-config/scripts/renew-kafka-ssl.sh <DOMAIN_MỚI> [MẬT_KHẨU]
# Sau đó restart Kafka:
docker compose restart kafka kafka-ui
```

#### D. Nạp đè lại cấu hình Consul KV:
```bash
./central-server-config/scripts/reload-consul-kv.sh
```

---

## 5. Xử lý sự cố thường gặp (Troubleshooting)

* **Container `consul` hoặc `kafka` báo un-healthy:**
  Xem log chi tiết:
  ```bash
  docker compose logs -f kafka
  docker compose logs -f consul
  ```
* **Muốn nạp lại toàn bộ cấu hình từ đầu:**
  ```bash
  docker compose down
  docker compose up -d
  ```
* **Muốn sinh lại toàn bộ chứng chỉ và file token:**
  Chỉ cần xóa nội dung trong `central-server-config/kafka/tls/*` và chạy `docker compose restart kafka`. Kafka sẽ tự động tạo lại cặp chứng chỉ mới hoàn chỉnh.

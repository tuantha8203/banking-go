# NFR — banking-go

> Yêu cầu phi chức năng có số đo. Nguồn: product.md (tiêu chí thành công), PRD §7, ARCHITECTURE-SPINE (AD-n), chốt 2026-10-05.
> Mỗi dòng phải có cách đo; dòng nào chưa đo được là nợ của observability.md.

## Đúng tiền (bắt buộc từ R1)
| ID | Yêu cầu | Đo bằng |
|---|---|---|
| NFR-M1 | Σ Nợ = Σ Có toàn hệ thống và mỗi journal; số dư KH = tổng bút toán; available = balance − Σ hold active | Job bất biến (FR-13) mỗi 5 phút trên staging + test CI; vi phạm → alert critical |
| NFR-M2 | Chaos test: N request đồng thời cùng TK, kill process giữa giao dịch, kill DB primary, retry trùng key → 0 lệch, 0 ghi đôi | `tests/chaos` chạy trong CI (testcontainers) + trên staging mỗi release |
| NFR-M3 | Không số dư KH âm; số tiền chỉ BIGINT VND | CHECK constraint + lint cấm float trong module tiền |
| NFR-M4 | Failover DB trong cluster không mất giao dịch đã `succeeded` (RPO = 0) | Synchronous standby (CNPG ANY 1 / RDS Multi-AZ); failover test đối chiếu số giao dịch trước/sau |

## Hiệu năng
| ID | Yêu cầu | Từ | Đo bằng |
|---|---|---|---|
| NFR-P1 | Chuyển nội bộ 500 TPS, p95 < 200 ms, lỗi < 0.1% | R3 (R1–R2 đo baseline) | k6 trên staging, báo cáo lưu `tests/load/reports/` |
| NFR-P2 | API đọc (số dư, sao kê, tra cứu) p95 < 100 ms | R1 | Histogram `http.server.request.duration` theo route |
| NFR-P3 | Lệnh ghi khác p95 < 300 ms; đăng nhập p95 < 500 ms (argon2id) | R1 | Như trên |
| NFR-P4 | Giao dịch `unknown`: tra soát tại 1, 3, 8, 18 phút rồi mỗi 10 phút; KH có kết quả ≤ 30 phút trong ≥ 99% trường hợp | R1 | Metric tuổi giao dịch unknown; warning > 15 phút, critical > 25 phút |
| NFR-P5 | Timeout gọi đối tác: submit 10 s; hạn callback 2 phút trước khi chuyển `unknown` | R1 | Config per partner; metric timeout theo đối tác |

Lịch job định kỳ (core-worker, AD-15); alert job trễ trong `observability.md` dùng chu kỳ ở bảng này:

| Job | Chu kỳ |
|---|---|
| `unknown_scan` | 60 s |
| `invariant_check` | 5 phút |
| `internal_balance_snapshot` | 5 phút |
| `business_day_roll` | 00:00 ICT hằng ngày |
| `customer_expiry` | 15 phút |
| Purge idempotency / outbox / inbox | 1 h |

## Sẵn sàng & phục hồi
| ID | Yêu cầu | Phạm vi | Đo bằng |
|---|---|---|---|
| NFR-A1 | SLO 99.9% / 30 ngày cho API public và admin (request không 5xx, p95 trong ngưỡng) | Staging (prod: chỉ trong cửa sổ release/demo) | SLI từ metric; error budget dashboard |
| NFR-A2 | Kill instance/DB primary dưới tải → phục hồi < 1 phút, không mất giao dịch đã xác nhận | Staging (CNPG); prod RDS 60–120 s ghi nhận, không cam kết | Failover test R3, báo cáo + dashboard |
| NFR-A3 | Mất cả cluster DB: RPO ≤ 5 phút, RTO ≤ 1 giờ | Cả hai | WAL archive liên tục; diễn tập PITR restore mỗi release |
| NFR-A4 | Mất 1 worker node staging: service vẫn chạy (CNPG 3 instance, RabbitMQ 3 replica, app ≥ 2 replica, anti-affinity) | Staging | Chaos: drain/kill node |
| NFR-A5 | Deploy không downtime: rolling update, readiness probe, graceful shutdown ≤ 30 s | Cả hai | Smoke test trong lúc deploy |

## Bảo mật
| ID | Yêu cầu | Đo bằng |
|---|---|---|
| NFR-S1 | Mật khẩu ≥ 10 ký tự, không thuộc danh sách phổ biến, argon2id; khóa 15 phút sau 5 lần sai | Unit/integration test |
| NFR-S2 | KH: access JWT 15 phút + refresh xoay vòng; admin: mật khẩu + TOTP, phiên 30 phút không thao tác | Test |
| NFR-S3 | Default deny; KH chỉ truy cập tài nguyên của mình (IDOR → `not_found`) | Test authZ cho mọi use case |
| NFR-S4 | SĐT, CCCD, TOTP secret mã hóa envelope; ảnh eKYC mã hóa at-rest ở object store (SSE-KMS prod / mã hóa đĩa staging D-6); tra cứu qua blind index; log che PII (4 số cuối) | Test + scan log mẫu |
| NFR-S5 | Không lỗi Critical/High theo OWASP Top 10 / ASVS L2 (tham khảo) | SAST + dependency scan + image scan + DAST staging trong CI |
| NFR-S6 | 100% thao tác admin và sự kiện bảo mật có audit record | Test đối chiếu use case ↔ audit action |
| NFR-S7 | Không secret trong repo; mTLS giữa service; TLS cho mọi kết nối công khai | gitleaks trong CI; kiểm cert |

## Lưu trữ dữ liệu (chính sách, bối cảnh VN tham khảo)
| Dữ liệu | Giữ | Ghi chú |
|---|---|---|
| Giao dịch, bút toán, audit | 10 năm | Append-only; staging/prod tạm thời chỉ áp dụng chính sách, không giữ thật 10 năm |
| Ảnh eKYC | 5 năm kể từ khi KH `rejected`/`expired` hoặc TK cuối cùng `closed` | Lifecycle bucket (AD-24) |
| Idempotency key | 72 giờ | AD-6 |
| Log ứng dụng | 30 ngày | Elasticsearch ILM / OpenSearch ISM |
| Metric | 30 ngày full, 13 tháng downsample | |
| Trace | 7 ngày | |

## Khả dụng UI
| ID | Yêu cầu |
|---|---|
| NFR-U1 | WCAG 2.1 AA cả hai web (axe trong CI, 0 lỗi serious/critical) |
| NFR-U2 | Web KH: LCP < 2.5 s trên mobile 4G mô phỏng; admin: ≥ 1280px |
| NFR-U3 | Trình duyệt: 2 phiên bản mới nhất Chrome, Edge, Firefox, Safari (iOS/macOS) |
| NFR-U4 | VI + EN 100% chuỗi qua i18n (lint cấm chuỗi cứng) |

## Ánh xạ kiến trúc
NFR-M* ↔ AD-4, AD-5, AD-16..18 · NFR-P4/P5 ↔ AD-7, AD-15 · NFR-A* ↔ AD-14, AD-26 · NFR-S* ↔ AD-6, AD-10, AD-11, AD-25 · NFR-P1..P3 ↔ AD-5, AD-13, AD-16 · NFR-S5 ↔ deployment.md § Pipeline · NFR-U* ↔ ADR 0009, design-system.md (không có AD).

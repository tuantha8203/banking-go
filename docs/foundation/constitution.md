# Constitution — banking-go

> Nguyên tắc bất biến cho mọi feature, mọi phiên AI, mọi review. Không feature nào được đánh đổi các điều dưới đây để lấy tốc độ hay tính năng.
> Đổi constitution chỉ qua `/foundation update constitution` kèm ADR. Chi tiết kỹ thuật: ARCHITECTURE-SPINE (AD-n).

## I. Đúng tiền trên hết
1. Tiền chỉ là số nguyên VND (`BIGINT`/`int64`). Không float, không decimal tự chế, ở bất kỳ tầng nào.
2. Mọi biến động tiền là một journal cân (Σ Nợ = Σ Có) ghi trong một transaction cùng bản ghi nghiệp vụ. Không sửa, không xóa bút toán; sai thì đảo.
3. Chỉ core thay đổi tiền. Chỉ các hàm của module `ledger` đổi số dư; chỉ `payment.Transition` đổi trạng thái giao dịch.
4. Mọi lệnh tạo hiệu ứng có idempotency key. Retry không bao giờ tạo hiệu ứng thứ hai.
5. Không gọi đối tác bên trong transaction DB. Timeout là `unknown`, không phải `failed`; chỉ tra soát mới chốt `unknown`.
6. Bất biến ledger được kiểm liên tục; vi phạm là sự cố mức cao nhất, dừng release.

## II. Test trước, chứng minh bằng số liệu
1. Viết test trước code (TDD); test tái hiện lỗi trước khi sửa lỗi.
2. Integration test dùng PostgreSQL và RabbitMQ thật (testcontainers); không mock DB cho logic tiền.
3. Mọi tuyên bố chất lượng (đúng tiền, tải, HA, bảo mật) phải có test hoặc báo cáo chạy lại được, lưu trong repo.
4. Không sửa/xóa test để "cho qua". Test chỉ được nới khi spec đổi và có lý do ghi lại.
5. "Xong" nghĩa là đã chạy thật và có evidence (lệnh + kết quả), không phải "chắc là chạy".

## III. Bảo mật mặc định
1. Default deny: mọi use case kiểm quyền ở core; KH chỉ thấy tài nguyên của mình.
2. Không log, không trả về, không đưa vào audit: mật khẩu, token, secret, ảnh, PII đầy đủ.
3. Secret chỉ qua secret manager (Sealed Secrets / AWS Secrets Manager); không bao giờ trong Git, image hay log.
4. Mọi thao tác admin và sự kiện bảo mật có audit record append-only.
5. Thao tác nhạy cảm cần người thứ hai duyệt (maker ≠ checker) từ R2; core tự kiểm bằng chứng duyệt.

## IV. Vận hành là một phần của feature
1. Feature chưa xong nếu thiếu: log có trace id, metric, alert (nếu có rủi ro), runbook cho lỗi đã biết, cách rollback.
2. Mọi thay đổi hạ tầng và cluster đi qua Git + pipeline (Argo CD / Terraform). Không `kubectl`/console sửa tay.
3. Production chỉ được thay đổi qua pipeline có duyệt tay. AI không deploy, không duyệt, không rollback prod.
4. Migration chạy lại được, tương thích ngược với bản đang chạy (expand → deploy → contract).
5. Mỗi release có demo E2E trên staging trước khi lên prod.

## V. Ranh giới và hợp đồng
1. Mỗi service chỉ chạm database của mình; mỗi module core chỉ chạm schema của mình.
2. Hợp đồng (OpenAPI sinh ra, proto, event) là nguồn sự thật; đổi phá vỡ phải có version mới.
3. Thuật ngữ theo glossary.md; không đặt từ đồng nghĩa mới.
4. Feature mâu thuẫn foundation → dừng, đề xuất `/foundation update`, không tự lách.

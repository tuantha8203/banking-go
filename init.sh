#!/bin/bash
# init.sh — kiểm tra baseline trước khi làm việc. Chạy đầu mỗi phiên.
# Không cần Docker. Integration test (testcontainers): make test-integration.
set -e
cd "$(dirname "$0")"
echo "=== Install ==="; make install
echo "=== Build ===";   make build
echo "=== Lint ===";    make lint
echo "=== Test ===";    make test
echo "=== Baseline OK ==="
echo "Tiếp theo: scripts/sprint.sh status — làm ĐÚNG MỘT task (scripts/sprint.sh next)."

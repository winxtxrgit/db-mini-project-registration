#!/usr/bin/env bash
set -e

# เลื่อน directory มาที่ root ของโปรเจกต์
cd "$(dirname "$0")/.."

echo "=========================================================="
echo " Starting Full Automated Test Suite (DevOps Automation)"
echo "=========================================================="

# เลือก Python ที่จะใช้
if [ -d ".venv" ] && [ -f ".venv/bin/python" ]; then
    PYTHON=".venv/bin/python"
else
    PYTHON="python3"
fi

echo "[1/2] Testing SQL Triggers & Business Rules (D1 - D19)..."
$PYTHON -m unittest discover -s tests -p "test_*.py" -v

echo ""
echo "[2/2] Testing Web Application, Auth & RBAC (web/test_app.py)..."
$PYTHON -m unittest discover -s web -p "test_*.py" -v

echo ""
echo "=========================================================="
echo "🎉 ALL TESTS PASSED SUCCESSFULLY!"
echo "=========================================================="

VENV := .venv
PYTHON := $(VENV)/bin/python
PIP := $(VENV)/bin/pip

# ระบบปฏิบัติการและคำสั่ง python เริ่มต้น
SYSTEM_PYTHON ?= python3

.PHONY: help setup venv test test-sql test-web run-sql run-web clean

help:
	@echo "========================================================================"
	@echo "ระบบวางแผนและตรวจสอบการลงทะเบียนตามแผนการเรียน (DevOps / CLI Helper)"
	@echo "========================================================================"
	@echo "คำสั่งที่ใช้งานได้:"
	@echo "  make setup       - ติดตั้ง Virtual Environment และ Python Dependencies"
	@echo "  make test        - รันการทดสอบทั้งหมด (ทั้ง SQL Triggers และ Web Unittest)"
	@echo "  make test-sql    - ทดสอบกฎฐานข้อมูลและ Trigger (D1 - D19)"
	@echo "  make test-web    - ทดสอบระบบเว็บและ API (web/test_app.py)"
	@echo "  make run-sql     - รันสคริปต์ SQL ทั้งหมดบน SQLite (run.sql)"
	@echo "  make run-web     - รัน Flask Web Application (พอร์ต 5000)"
	@echo "  make clean       - ลบไฟล์ชั่วคราว, cache และ test databases"
	@echo "========================================================================"

venv $(VENV):
	$(SYSTEM_PYTHON) -m venv $(VENV)
	$(PIP) install --upgrade pip
	$(PIP) install -r web/requirements.txt

setup: $(VENV)
	@echo "Environment setup complete in $(VENV)"

test: test-sql test-web
	@echo "\n========================================"
	@echo "✅ All automated test suites passed!"
	@echo "========================================"

test-sql:
	@echo "--- [1/2] Running SQL & Database Trigger Test Suite ---"
	@if [ -f "$(PYTHON)" ]; then \
		$(PYTHON) -m unittest discover -s tests -p "test_*.py" -v; \
	else \
		$(SYSTEM_PYTHON) -m unittest discover -s tests -p "test_*.py" -v; \
	fi

test-web:
	@echo "\n--- [2/2] Running Web Application & RBAC Test Suite ---"
	@if [ -f "$(PYTHON)" ]; then \
		$(PYTHON) -m unittest discover -s web -p "test_*.py" -v; \
	else \
		$(SYSTEM_PYTHON) -m unittest discover -s web -p "test_*.py" -v; \
	fi

run-sql:
	@echo "Running run.sql via sqlite3..."
	sqlite3 < run.sql

run-web: $(VENV)
	@echo "Starting Flask web server on http://127.0.0.1:5000 ..."
	$(PYTHON) web/app.py

clean:
	rm -rf __pycache__ web/__pycache__ tests/__pycache__
	rm -rf .pytest_cache
	rm -f web/registration.db test.db

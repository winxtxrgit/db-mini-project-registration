#!/bin/bash
# macOS: ดับเบิลคลิกไฟล์นี้เพื่อเปิดเว็บ Plan A ที่ http://127.0.0.1:5050 (รายละเอียดใน scripts/run_web.py)
# ถ้าดับเบิลคลิกแล้วขึ้นว่าไม่มีสิทธิ์เปิด ให้รัน chmod +x run-web.command หนึ่งครั้ง
cd "$(dirname "$0")" || exit 1

PY="$(command -v python3 || command -v python)"
if [ -z "$PY" ]; then
  echo "ต้องติดตั้ง Python 3 ก่อน: https://www.python.org/downloads/"
  read -r -n 1 -p "กดปุ่มใดก็ได้เพื่อปิด"
  exit 1
fi

"$PY" scripts/run_web.py "$@"
status=$?
if [ $status -ne 0 ]; then
  echo
  read -r -n 1 -p "เปิดเว็บไม่สำเร็จ (exit $status) กดปุ่มใดก็ได้เพื่อปิด"
fi
exit $status

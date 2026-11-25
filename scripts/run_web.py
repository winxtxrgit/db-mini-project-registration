"""เปิดหน้าเว็บ Plan A ที่ http://127.0.0.1:5050 (ใช้ได้ทั้ง macOS, Windows, Linux · ใช้แค่ standard library)

ปกติไม่ต้องเรียกไฟล์นี้เอง ให้ดับเบิลคลิก run-web.command (macOS) หรือ run-web.bat (Windows)
ทำตามลำดับ:
  1. ถ้าเว็บเปิดอยู่แล้ว เปิดเบราว์เซอร์อย่างเดียว
  2. ครั้งแรก สร้าง .venv และติดตั้งแพ็กเกจจาก web/requirements.txt
  3. ถ้า web/registration.db สร้างจาก schema เก่า (ขาดตารางที่มีใน schema.sql) ย้ายไปไว้ที่ web/backups/
     แล้วให้เว็บสร้างใหม่จาก schema.sql + seed.sql ตอนเปิดหน้าแรก
  4. รัน Flask แล้วเปิดเบราว์เซอร์เมื่อเว็บพร้อม

ตัวเลือก: --no-browser = ไม่เปิดเบราว์เซอร์ (ใช้ตอนทดสอบ)
"""
import os
import re
import signal
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request
import venv
import webbrowser
from datetime import datetime
from pathlib import Path

PORT = 5050
URL = f"http://127.0.0.1:{PORT}"
REPO = Path(__file__).resolve().parent.parent
WEB = REPO / "web"
VENV = REPO / ".venv"
VENV_PY = VENV / ("Scripts/python.exe" if os.name == "nt" else "bin/python")
DB = WEB / "registration.db"
BACKUPS = WEB / "backups"


def port_in_use() -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(0.5)
        return s.connect_ex(("127.0.0.1", PORT)) == 0


def ensure_venv() -> None:
    """สร้าง .venv และติดตั้ง Flask ครั้งแรก (หรือถ้ายังไม่มี Flask ใน .venv)"""
    if VENV_PY.exists():
        has_flask = subprocess.run([str(VENV_PY), "-c", "import flask"],
                                   capture_output=True).returncode == 0
        if has_flask:
            return
    else:
        print("สร้าง .venv ครั้งแรก...")
        venv.create(VENV, with_pip=True)
    print("ติดตั้งแพ็กเกจจาก web/requirements.txt ...")
    subprocess.run([str(VENV_PY), "-m", "pip", "install", "-q", "--disable-pip-version-check", "-r", str(WEB / "requirements.txt")],
                   check=True)


def missing_tables() -> list[str]:
    """ตารางที่มีใน schema.sql แต่ไม่มีใน web/registration.db"""
    wanted = set(re.findall(r"^CREATE TABLE (\w+)", (REPO / "schema.sql").read_text(encoding="utf-8"),
                            flags=re.MULTILINE))
    con = sqlite3.connect(DB.as_uri() + "?mode=ro", uri=True)   # อ่านอย่างเดียว ไม่สร้างไฟล์ใหม่
    try:
        have = {r[0] for r in con.execute("SELECT name FROM sqlite_master WHERE type = 'table'")}
    finally:
        con.close()
    return sorted(wanted - have)


def refresh_stale_db() -> None:
    if not DB.exists():
        return
    try:
        missing = missing_tables()
        reason = f"สร้างจาก schema เก่า ขาดตาราง: {', '.join(missing)}"
    except sqlite3.DatabaseError:
        missing, reason = True, "ไฟล์เสียหรือไม่ใช่ฐานข้อมูล SQLite"
    if not missing:
        return
    BACKUPS.mkdir(exist_ok=True)
    backup = BACKUPS / f"registration.old-{datetime.now():%Y%m%d-%H%M%S}.db"
    DB.replace(backup)
    print(f"ใช้ web/registration.db เดิมไม่ได้ ({reason})")
    print(f"ย้ายไฟล์เก่าไปที่ {backup.relative_to(REPO)} แล้ว เว็บจะสร้างใหม่จาก schema.sql + seed.sql")


def open_when_ready() -> None:
    for _ in range(60):
        try:
            urllib.request.urlopen(f"{URL}/login", timeout=1)
        except OSError:
            time.sleep(0.5)
            continue
        webbrowser.open(URL)
        return


def banner() -> None:
    line = "=" * 60
    print(line)
    print(f" เว็บ Plan A: {URL}")
    print(" รหัสผ่านทุกบัญชี: demo1234 (ดูท้าย seed.sql)")
    print("   ฝ่ายทะเบียน   admin")
    print("   ผู้จัดตาราง    scheduler")
    print("   นักศึกษา       6799000001 ถึง 6799000005, B6501, ...")
    print(" ปิดเว็บ: กด Ctrl+C หรือปิดหน้าต่างนี้")
    print(line)


def main() -> int:
    sys.stdout.reconfigure(line_buffering=True)   # ให้ข้อความขึ้นก่อน log ของ Flask
    no_browser = "--no-browser" in sys.argv[1:]
    if port_in_use():
        print(f"เว็บเปิดอยู่แล้วที่ {URL}")
        if not no_browser:
            webbrowser.open(URL)
        return 0

    try:
        ensure_venv()
    except (subprocess.CalledProcessError, OSError) as exc:
        print(f"ติดตั้ง Flask ไม่สำเร็จ ({exc}) ตรวจอินเทอร์เน็ต แล้วลองใหม่ หรือลบโฟลเดอร์ .venv แล้วเปิดอีกครั้ง")
        return 1
    refresh_stale_db()
    banner()
    if not no_browser:
        threading.Thread(target=open_when_ready, daemon=True).start()
    # ถ้าตัวนี้ถูกปิด (Ctrl+C, SIGTERM) ให้ปิด Flask ตามไปด้วย ไม่ให้ค้างพอร์ต 5050
    signal.signal(signal.SIGTERM, lambda *_: sys.exit(0))
    server = subprocess.Popen([str(VENV_PY), "-m", "flask", "--app", "app", "run", "--port", str(PORT)], cwd=WEB)
    try:
        return server.wait()
    except KeyboardInterrupt:
        return 0
    finally:
        if server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()


if __name__ == "__main__":
    sys.exit(main())

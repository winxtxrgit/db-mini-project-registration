"""ฟังก์ชันกลางที่ทุกส่วนใช้: เชื่อมต่อฐานข้อมูล ทำรายการพร้อมระบุผู้ทำรายการ ตรวจสิทธิ์"""
import sqlite3
from functools import wraps
from pathlib import Path

from flask import abort, flash, g, redirect, request, url_for

BASE = Path(__file__).resolve().parent
PROJECT = BASE.parent
DB_PATH = BASE / "registration.db"

DAYS = {1: "จ.", 2: "อ.", 3: "พ.", 4: "พฤ.", 5: "ศ.", 6: "ส.", 7: "อา."}
ROLE_NAME = {"student": "นักศึกษา", "admin": "ฝ่ายทะเบียน", "scheduler": "ผู้จัดตาราง"}
HOME = {"student": "student.home", "admin": "admin.dashboard", "scheduler": "scheduler.home"}


# ------------------------------------------------------------------ ฐานข้อมูล
def build_db() -> None:
    """สร้างฐานข้อมูลใหม่จาก schema.sql + seed.sql (ไม่รัน demo.sql)"""
    if DB_PATH.exists():
        DB_PATH.unlink()
    con = sqlite3.connect(DB_PATH)
    try:
        for name in ("schema.sql", "seed.sql"):
            con.executescript((PROJECT / name).read_text(encoding="utf-8"))
        con.commit()
    finally:
        con.close()


def db() -> sqlite3.Connection:
    if "db" not in g:
        if not DB_PATH.exists():
            build_db()
        con = sqlite3.connect(DB_PATH)
        con.row_factory = sqlite3.Row
        con.execute("PRAGMA foreign_keys = ON")
        g.db = con
    return g.db


def close_db(_exc=None):
    con = g.pop("db", None)
    if con is not None:
        con.close()


def rows(sql: str, **params):
    return db().execute(sql, params).fetchall()


def one(sql: str, **params):
    return db().execute(sql, params).fetchone()


_FRIENDLY = (
    ("CHECK constraint failed", "ข้อมูลไม่ถูกต้อง (ตรวจรูปแบบเวลา HH:MM วันที่ และตัวเลข)"),
    ("UNIQUE constraint failed", "ข้อมูลซ้ำกับที่มีอยู่แล้ว"),
    ("FOREIGN KEY constraint failed", "อ้างอิงข้อมูลที่ไม่มีอยู่ หรือยังมีข้อมูลอื่นอ้างถึงอยู่"),
    ("NOT NULL constraint failed", "กรอกข้อมูลไม่ครบ"),
)


def _message(exc: Exception) -> str:
    text = str(exc)
    for key, friendly in _FRIENDLY:
        if key in text:
            return friendly
    return text  # ข้อความจาก RAISE(ABORT, ...) ใน trigger เป็นภาษาไทยอยู่แล้ว


def write(steps, ok_msg: str | None = None) -> bool:
    """ทำหลายคำสั่งใน transaction เดียว พร้อมบอกฐานข้อมูลว่าใครเป็นผู้ทำรายการ

    steps: list ของ (sql, params) หรือ callable(con) สำหรับงานที่ต้องวนซ้ำ
    ถ้า trigger ปฏิเสธ ทุกอย่างใน transaction จะ rollback แล้วแสดงเหตุผลให้ผู้ใช้เห็น
    """
    con = db()
    try:
        with con:
            con.execute("INSERT OR REPLACE INTO app_session (id, user_id) VALUES (1, ?)", (g.user["user_id"],))
            for step in steps:
                if callable(step):
                    step(con)
                else:
                    con.execute(*step)
            con.execute("DELETE FROM app_session")
    except (sqlite3.DatabaseError, ValueError) as exc:
        flash(f"ไม่สำเร็จ: {_message(exc)}", "error")
        return False
    if ok_msg:
        flash(ok_msg, "ok")
    return True


def promote_waitlist(section_id: int):
    """ขั้นตอนสำหรับ write(): เลื่อนคิวของ section นี้จนกว่าจะไม่มีคนที่ลงได้หรือที่นั่งหมด"""
    def step(con: sqlite3.Connection):
        promoted = []
        while True:
            nxt = con.execute("SELECT student_id FROM v_waitlist_next WHERE section_id = ?", (section_id,)).fetchone()
            if nxt is None:
                break
            con.execute("INSERT INTO enrollment (student_id, section_id) VALUES (?, ?)", (nxt[0], section_id))
            promoted.append(nxt[0])
        if promoted:
            flash(f"เลื่อนจากคิวสำรอง: {', '.join(promoted)}", "info")
    return step


def section_label(section_id: int) -> str:
    r = one("SELECT s.course_code, c.name_th, s.section_no FROM section s "
            "JOIN course c ON c.course_code = s.course_code WHERE s.section_id = :sid", sid=section_id)
    return f"{r['course_code']} {r['name_th']} กลุ่ม {r['section_no']}" if r else str(section_id)


def form_int(name: str, default=None):
    value = request.form.get(name, "").strip()
    if value == "":
        if default is not None:
            return default
        raise ValueError(f"กรุณากรอก {name}")
    try:
        return int(value)
    except ValueError:
        raise ValueError(f"{name} ต้องเป็นตัวเลข") from None


def form_str(name: str, required: bool = True):
    value = request.form.get(name, "").strip()
    if required and not value:
        raise ValueError(f"กรุณากรอก {name}")
    return value or None


def require(*roles):
    """ต้อง login และมีบทบาทตามที่กำหนด"""
    def deco(view):
        @wraps(view)
        def wrapper(*args, **kwargs):
            if g.user is None:
                return redirect(url_for("login", next=request.path))
            if roles and g.user["role"] not in roles:
                abort(403)
            return view(*args, **kwargs)
        return wrapper
    return deco


# ------------------------------------------------------------------ ตารางเรียนรายสัปดาห์ (ใช้กับ macro ui.timetable)
def _minutes(hhmm: str) -> int:
    h, m = hhmm.split(":")
    return int(h) * 60 + int(m)


def timetable(meetings, sub_key: str = "room_code", tone_key: str = "course_code") -> dict:
    """แปลงคาบเรียนเป็นตำแหน่งบน CSS grid (ช่องละ 30 นาที)

    meetings: แถวที่มี day_of_week, start_time, end_time, course_code, name_th และคอลัมน์ตาม sub_key
    คืนค่า days, rows, lines (เส้นบอกเวลา), blocks (ตำแหน่งแต่ละคาบ + clash ถ้าทับกับคาบอื่นวันเดียวกัน)
    และ by_day (รายการเรียงตามวัน สำหรับจอแคบและ screen reader)
    """
    items = [dict(m) for m in meetings]
    if not items:
        return {"empty": True}
    start = min(_minutes(m["start_time"]) for m in items)
    end = max(_minutes(m["end_time"]) for m in items)
    start = min(8 * 60, start - start % 60)                 # อย่างน้อยเริ่ม 08:00
    end = max(17 * 60, end + (-end % 60))                   # อย่างน้อยถึง 17:00
    used = {m["day_of_week"] for m in items}
    days = [d for d in range(1, 8) if d <= 5 or d in used]  # จ.–ศ. เสมอ ส./อา. เมื่อมีคาบ
    col = {d: i + 2 for i, d in enumerate(days)}

    tones, blocks = {}, []
    for m in sorted(items, key=lambda x: (x["day_of_week"], x["start_time"])):
        s, e = _minutes(m["start_time"]), _minutes(m["end_time"])
        key = m.get(tone_key)
        tones.setdefault(key, len(tones) % 4)
        clash = any(o is not m and o["day_of_week"] == m["day_of_week"]
                    and _minutes(o["start_time"]) < e and s < _minutes(o["end_time"])
                    and o.get("section_id") != m.get("section_id")
                    and o["course_code"] != m["course_code"]     # กลุ่มของวิชาเดียวกันเรียนรวมได้ (ตามกฎห้องใน trigger)
                    for o in items)
        blocks.append({
            "dow": m["day_of_week"], "col": col[m["day_of_week"]],
            "row": (s - start) // 30 + 2, "span": max(1, (e - s + 29) // 30),
            "code": m["course_code"] + (f" ({m['section_no']})" if m.get("section_no") else ""),
            "title": m.get("name_th") or "", "sub": m.get(sub_key) or "",
            "time": f"{m['start_time']}–{m['end_time']}", "clash": clash, "tone": tones[key],
        })
    rows_ = (end - start) // 30
    lines = [(i + 2, f"{(start + i * 30) // 60:02d}:00", i % 2 == 1) for i in range(rows_)]
    by_day = [(DAYS[d], [b for b in blocks if b["dow"] == d]) for d in days if d in used]
    return {"empty": False, "days": [(d, DAYS[d]) for d in days], "rows": rows_,
            "lines": lines, "blocks": blocks, "by_day": by_day}

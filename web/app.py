"""หน้าเว็บของระบบลงทะเบียนตามแผนการเรียน (Flask + SQLite)

กฎการลงทะเบียนทั้งหมดอยู่ใน trigger ของ schema.sql หน้าเว็บแค่ส่ง INSERT/DELETE
แล้วแสดงข้อความ error จาก RAISE(ABORT, ...) ให้ผู้ใช้เห็น

รัน:  python web/app.py   แล้วเปิด http://127.0.0.1:5000
"""
import sqlite3
from pathlib import Path

from flask import Flask, flash, g, redirect, render_template, request, url_for

import reports as R

BASE = Path(__file__).resolve().parent
PROJECT = BASE.parent
DB_PATH = BASE / "registration.db"

app = Flask(__name__)
app.secret_key = "mini-project-plan-a"  # ใช้กับ flash message เท่านั้น


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


@app.teardown_appcontext
def close_db(_exc):
    con = g.pop("db", None)
    if con is not None:
        con.close()


def rows(sql: str, **params):
    return db().execute(sql, params).fetchall()


def run_write(sql: str, params: tuple, ok_msg: str) -> None:
    """INSERT/DELETE ใน transaction เดียว ถ้า trigger ปฏิเสธก็ rollback แล้วแสดงเหตุผล"""
    con = db()
    try:
        with con:
            con.execute(sql, params)
        flash(ok_msg, "ok")
    except sqlite3.DatabaseError as exc:  # RAISE(ABORT) มาเป็น IntegrityError
        flash(f"ไม่สำเร็จ: {exc}", "error")


def section_label(section_id: int) -> str:
    r = db().execute(
        "SELECT s.course_code, c.name_th, s.section_no FROM section s "
        "JOIN course c ON c.course_code = s.course_code WHERE s.section_id = ?",
        (section_id,),
    ).fetchone()
    return f"{r['course_code']} {r['name_th']} กลุ่ม {r['section_no']}" if r else str(section_id)


# ------------------------------------------------------------------ หน้าเว็บ
@app.route("/")
def index():
    students = rows(
        """SELECT s.student_id, s.first_name, s.last_name, s.curriculum_id, lv.year_level
           FROM student s JOIN v_student_level lv ON lv.student_id = s.student_id
           WHERE s.curriculum_id <> 'EXT'
           ORDER BY s.curriculum_id = 'CPE63' DESC, s.curriculum_id, s.student_id"""
    )
    return render_template("index.html", students=students)


@app.route("/go")
def go():
    sid = request.args.get("sid", "").strip()
    return redirect(url_for("student", sid=sid)) if sid else redirect(url_for("index"))


@app.route("/student/<sid>")
def student(sid):
    info = db().execute(R.STUDENT_INFO, {"sid": sid}).fetchone()
    if info is None:
        flash(f"ไม่พบนักศึกษารหัส {sid}", "error")
        return redirect(url_for("index"))
    return render_template(
        "student.html",
        s=info,
        plan=rows(R.R1_PLAN_STATUS, sid=sid),
        why=rows(R.R2_WHY_NOT, sid=sid),
        exams=rows(R.R3_EXAMS, sid=sid),
        backlog=rows(R.R6_BACKLOG_CLASH, sid=sid),
        sections=rows(R.SECTIONS_FOR_STUDENT, sid=sid),
        waits=rows("SELECT * FROM (" + R.WAITLIST_RANK + ") WHERE student_id = :sid", sid=sid),
    )


@app.post("/student/<sid>/enroll/<int:section_id>")
def enroll(sid, section_id):
    run_write("INSERT INTO enrollment (student_id, section_id) VALUES (?, ?)",
              (sid, section_id), f"ลงทะเบียน {section_label(section_id)} แล้ว")
    return redirect(url_for("student", sid=sid) + "#register")


@app.post("/student/<sid>/drop/<int:section_id>")
def drop(sid, section_id):
    before = {r[0] for r in db().execute(
        "SELECT student_id FROM enrollment WHERE section_id = ?", (section_id,))}
    run_write("DELETE FROM enrollment WHERE student_id = ? AND section_id = ?",
              (sid, section_id), f"ถอน {section_label(section_id)} แล้ว")
    promoted = [r[0] for r in db().execute(
        "SELECT student_id FROM enrollment WHERE section_id = ?", (section_id,)) if r[0] not in before]
    if promoted:
        flash(f"ระบบเลื่อน {', '.join(promoted)} จากคิวสำรองขึ้นมาแทนอัตโนมัติ", "info")
    return redirect(url_for("student", sid=sid) + "#register")


@app.post("/student/<sid>/waitlist/<int:section_id>")
def join_waitlist(sid, section_id):
    run_write("INSERT INTO waitlist (student_id, section_id) VALUES (?, ?)",
              (sid, section_id), f"เข้าคิวสำรอง {section_label(section_id)} แล้ว")
    return redirect(url_for("student", sid=sid) + "#register")


@app.post("/student/<sid>/unwait/<int:section_id>")
def leave_waitlist(sid, section_id):
    run_write("DELETE FROM waitlist WHERE student_id = ? AND section_id = ?",
              (sid, section_id), f"ออกจากคิว {section_label(section_id)} แล้ว")
    return redirect(url_for("student", sid=sid) + "#register")


@app.route("/registrar")
def registrar():
    return render_template(
        "registrar.html",
        demand=rows(R.R4_SEAT_DEMAND),
        locked=rows(R.R5_QUOTA_LOCKED),
        seats=rows(R.SECTION_SEATS),
        queue=rows(R.WAITLIST_RANK),
    )


@app.route("/log")
def log():
    sid = request.args.get("sid", "").strip()
    action = request.args.get("action", "").strip()
    return render_template("log.html", logs=rows(R.LOG, sid=sid, action=action), sid=sid, action=action)


@app.post("/reset")
def reset():
    close_db(None)
    build_db()
    flash("รีเซ็ตฐานข้อมูลกลับเป็นข้อมูลตั้งต้นแล้ว", "ok")
    return redirect(request.referrer or url_for("index"))


if __name__ == "__main__":
    app.run(debug=True)

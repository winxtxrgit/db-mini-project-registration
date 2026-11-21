"""นักศึกษา: ดูแผนการเรียนและลง/ถอน/เข้าคิวของตัวเอง

หน้าลงทะเบียนกับการทำรายการเขียนเป็นฟังก์ชันกลาง เพื่อให้ฝ่ายทะเบียนใช้ทำรายการแทนนักศึกษาได้
(กฎทุกข้อยังตรวจใน trigger เหมือนกัน ต่างกันแค่ฝ่ายทะเบียนไม่ติดช่วงลงทะเบียน)
"""
from flask import Blueprint, abort, flash, g, redirect, render_template, request, url_for

import reports as R
from core import one, require, rows, section_label, write

bp = Blueprint("student", __name__, url_prefix="/me")


# ------------------------------------------------------------------ ฟังก์ชันกลาง (ใช้ร่วมกับ admin)
def render_registration(sid: str, endpoint_prefix: str, url_kwargs: dict):
    info = one(R.STUDENT_INFO, sid=sid)
    if info is None:
        abort(404)
    return render_template(
        "registration.html",
        s=info,
        plan=rows(R.R1_PLAN_STATUS, sid=sid),
        why=rows(R.R2_WHY_NOT, sid=sid),
        exams=rows(R.R3_EXAMS, sid=sid),
        backlog=rows(R.R6_BACKLOG_CLASH, sid=sid),
        sections=rows(R.SECTIONS_FOR_STUDENT, sid=sid),
        waits=rows("SELECT * FROM (" + R.WAITLIST_RANK + ") WHERE student_id = :sid", sid=sid),
        ep=endpoint_prefix,
        ukw=url_kwargs,
    )


def do_enroll(sid: str, section_id: int):
    write([("INSERT INTO enrollment (student_id, section_id) VALUES (?, ?)", (sid, section_id))],
          f"ลงทะเบียน {section_label(section_id)} แล้ว")


def do_drop(sid: str, section_id: int):
    before = {r[0] for r in rows("SELECT student_id FROM enrollment WHERE section_id = :s", s=section_id)}
    if write([("DELETE FROM enrollment WHERE student_id = ? AND section_id = ?", (sid, section_id))],
             f"ถอน {section_label(section_id)} แล้ว"):
        after = {r[0] for r in rows("SELECT student_id FROM enrollment WHERE section_id = :s", s=section_id)}
        promoted = sorted(after - before)
        if promoted:
            flash(f"ระบบเลื่อน {', '.join(promoted)} จากคิวสำรองขึ้นมาแทนอัตโนมัติ", "info")


def do_waitlist(sid: str, section_id: int):
    write([("INSERT INTO waitlist (student_id, section_id) VALUES (?, ?)", (sid, section_id))],
          f"เข้าคิวสำรอง {section_label(section_id)} แล้ว")


def do_unwait(sid: str, section_id: int):
    write([("DELETE FROM waitlist WHERE student_id = ? AND section_id = ?", (sid, section_id))],
          f"ออกจากคิว {section_label(section_id)} แล้ว")


ACTIONS = {"enroll": do_enroll, "drop": do_drop, "waitlist": do_waitlist, "unwait": do_unwait}


# ------------------------------------------------------------------ หน้าของนักศึกษาเอง
@bp.route("/")
@require("student")
def home():
    return render_registration(g.user["student_id"], "student", {})


@bp.post("/<action>/<int:section_id>")
@require("student")
def act(action, section_id):
    if action not in ACTIONS:
        abort(404)
    ACTIONS[action](g.user["student_id"], section_id)   # ทำได้เฉพาะของตัวเองเสมอ
    return redirect(url_for("student.home") + "#register")


@bp.route("/log")
@require("student")
def log():
    action = request.args.get("action", "").strip()
    return render_template("reg_log.html", logs=rows(R.REG_LOG, sid=g.user["student_id"], action=action),
                           sid=g.user["student_id"], action=action, lock_sid=True)

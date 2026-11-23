"""ฝ่ายทะเบียน (admin): ภาคเรียน กลุ่มเรียนและโควตา คิวสำรอง นักศึกษา บัญชีผู้ใช้ รายงาน"""
import re

from flask import Blueprint, abort, flash, g, redirect, render_template, request, url_for
from werkzeug.security import generate_password_hash

import reports as R
from core import (build_db, close_db, form_int, form_str, one, promote_waitlist,
                  require, rows, section_label, write)
from views_student import ACTIONS, render_registration

bp = Blueprint("admin", __name__, url_prefix="/admin")

MIN_PASSWORD = 8
DATETIME_RE = re.compile(r"^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$")


def back(default_endpoint: str, **kwargs):
    return redirect(url_for(default_endpoint, **kwargs))


# ------------------------------------------------------------------ ภาพรวม
@bp.route("/")
@require("admin")
def dashboard():
    return render_template(
        "admin/dashboard.html",
        term=one("SELECT * FROM v_term_status WHERE is_current = 1"),
        demand=rows(R.R4_SEAT_DEMAND),
        locked=rows(R.R5_QUOTA_LOCKED),
        queue=rows(R.WAITLIST_RANK),
    )


# ------------------------------------------------------------------ ภาคเรียน
@bp.route("/terms")
@require("admin")
def terms():
    return render_template("admin/terms.html", terms=rows(R.TERMS))


def _datetime_or_none(name: str):
    """รับค่าจาก <input type=datetime-local> (YYYY-MM-DDTHH:MM) แล้วเก็บเป็น 'YYYY-MM-DD HH:MM'"""
    value = (request.form.get(name) or "").strip().replace("T", " ")
    if not value:
        return None
    if not DATETIME_RE.match(value):
        raise ValueError("รูปแบบวันเวลาไม่ถูกต้อง")
    return value


@bp.post("/terms/<term_id>")
@require("admin")
def term_update(term_id):
    try:
        params = (_datetime_or_none("reg_open_at"), _datetime_or_none("reg_close_at"),
                  form_int("max_credits"), term_id)
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.terms")
    write([("UPDATE term SET reg_open_at = ?, reg_close_at = ?, max_credits = ? WHERE term_id = ?", params)],
          f"บันทึกภาคเรียน {term_id} แล้ว")
    return back("admin.terms")


@bp.post("/terms/<term_id>/current")
@require("admin")
def term_set_current(term_id):
    write([("UPDATE term SET is_current = 0 WHERE is_current = 1", ()),
           ("UPDATE term SET is_current = 1 WHERE term_id = ?", (term_id,))],
          f"ตั้ง {term_id} เป็นภาคเรียนปัจจุบันแล้ว")
    return back("admin.terms")


# ------------------------------------------------------------------ กลุ่มเรียน โควตา คิว
@bp.route("/sections")
@require("admin")
def sections():
    return render_template(
        "admin/sections.html",
        sections=rows(R.SECTIONS_ADMIN),
        courses=rows("SELECT course_code, name_th FROM course ORDER BY course_code"),
        curricula=rows("SELECT curriculum_id FROM curriculum ORDER BY curriculum_id"),
        queue=rows(R.WAITLIST_RANK),
        term=one("SELECT term_id FROM term WHERE is_current = 1"),
    )


@bp.post("/sections/new")
@require("admin")
def section_new():
    try:
        params = (form_str("course_code"), form_str("section_no"), form_int("capacity"))
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.sections")
    write([("INSERT INTO section (course_code, term_id, section_no, capacity) "
            "SELECT ?, term_id, ?, ? FROM term WHERE is_current = 1", params)],
          f"เปิดกลุ่มเรียน {params[0]} กลุ่ม {params[1]} แล้ว (ให้ผู้จัดตารางวางเวลาเรียนต่อ)")
    return back("admin.sections")


@bp.post("/sections/<int:section_id>/capacity")
@require("admin")
def section_capacity(section_id):
    try:
        cap = form_int("capacity")
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.sections", _anchor=f"sec{section_id}")
    write([("UPDATE section SET capacity = ? WHERE section_id = ?", (cap, section_id)),
           promote_waitlist(section_id)],
          f"ตั้งจำนวนรับ {section_label(section_id)} เป็น {cap} แล้ว")
    return back("admin.sections", _anchor=f"sec{section_id}")


@bp.post("/sections/<int:section_id>/quota")
@require("admin")
def section_quota(section_id):
    """กรอกจำนวน = ตั้งโควตา, เว้นว่าง = ยกเลิกโควตาของหลักสูตรนั้น"""
    try:
        curriculum = form_str("curriculum_id")
        seats = request.form.get("seats", "").strip()
        if seats == "":
            step = ("DELETE FROM section_quota WHERE section_id = ? AND curriculum_id = ?", (section_id, curriculum))
            msg = f"ยกเลิกโควตา {curriculum} ของ {section_label(section_id)} แล้ว"
        else:
            n = form_int("seats")
            step = ("INSERT INTO section_quota (section_id, curriculum_id, seats) VALUES (?, ?, ?) "
                    "ON CONFLICT (section_id, curriculum_id) DO UPDATE SET seats = excluded.seats",
                    (section_id, curriculum, n))
            msg = f"ตั้งโควตา {curriculum} ของ {section_label(section_id)} เป็น {n} ที่แล้ว"
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.sections", _anchor=f"sec{section_id}")
    write([step, promote_waitlist(section_id)], msg)
    return back("admin.sections", _anchor=f"sec{section_id}")


@bp.post("/sections/<int:section_id>/promote")
@require("admin")
def section_promote(section_id):
    write([promote_waitlist(section_id)], f"ตรวจคิวของ {section_label(section_id)} แล้ว")
    return back("admin.sections", _anchor=f"sec{section_id}")


@bp.post("/waitlist/<sid>/<int:section_id>/remove")
@require("admin")
def waitlist_remove(sid, section_id):
    write([("DELETE FROM waitlist WHERE student_id = ? AND section_id = ?", (sid, section_id))],
          f"เอา {sid} ออกจากคิว {section_label(section_id)} แล้ว")
    return back("admin.sections", _anchor=f"sec{section_id}")


# ------------------------------------------------------------------ นักศึกษา
@bp.route("/students")
@require("admin")
def students():
    q = request.args.get("q", "").strip()
    return render_template("admin/students.html", students=rows(R.STUDENT_LIST, q=q), q=q,
                           curricula=rows("SELECT curriculum_id FROM curriculum ORDER BY curriculum_id"))


@bp.post("/students/new")
@require("admin")
def student_new():
    try:
        sid = form_str("student_id")
        student = (sid, form_str("first_name"), form_str("last_name"),
                   form_str("curriculum_id"), form_int("entry_year"))
        password = request.form.get("password", "")
        steps = [("INSERT INTO student (student_id, first_name, last_name, curriculum_id, entry_year) "
                  "VALUES (?, ?, ?, ?, ?)", student)]
        if password:
            if len(password) < MIN_PASSWORD:
                raise ValueError(f"รหัสผ่านต้องยาวอย่างน้อย {MIN_PASSWORD} ตัวอักษร")
            steps.append(("INSERT INTO app_user (username, password_hash, role, student_id) VALUES (?, ?, 'student', ?)",
                          (sid, generate_password_hash(password), sid)))
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.students")
    write(steps, f"เพิ่มนักศึกษา {sid} แล้ว" + (" พร้อมบัญชีผู้ใช้" if password else ""))
    return back("admin.students", q=sid)


@bp.route("/students/<sid>")
@require("admin")
def student_view(sid):
    return render_registration(sid, "admin", {"sid": sid})


@bp.post("/students/<sid>/<action>/<int:section_id>")
@require("admin")
def student_act(sid, action, section_id):
    if action not in ACTIONS:
        abort(404)
    ACTIONS[action](sid, section_id)
    return redirect(url_for("admin.student_view", sid=sid, _anchor=f"sec{section_id}"))


@bp.route("/credits")
@require("admin")
def credits():
    q = request.args.get("q", "").strip()
    return render_template("admin/credits.html", rows_=rows(R.R7_CREDITS, q=q), q=q)


# ------------------------------------------------------------------ บัญชีผู้ใช้
@bp.route("/users")
@require("admin")
def users():
    q = request.args.get("q", "").strip()
    return render_template("admin/users.html", users=rows(R.USERS, q=q), q=q,
                           instructors=rows("SELECT instructor_id, full_name FROM instructor ORDER BY full_name"))


@bp.post("/users/new")
@require("admin")
def user_new():
    try:
        username = form_str("username")
        role = form_str("role")
        if role not in ("student", "admin", "scheduler"):
            raise ValueError("บทบาทไม่ถูกต้อง")
        password = request.form.get("password", "")
        if len(password) < MIN_PASSWORD:
            raise ValueError(f"รหัสผ่านต้องยาวอย่างน้อย {MIN_PASSWORD} ตัวอักษร")
        student_id = form_str("student_id", required=False) if role == "student" else None
        instructor_id = form_int("instructor_id", default=0) if role == "scheduler" else 0
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return back("admin.users")
    write([("INSERT INTO app_user (username, password_hash, role, student_id, instructor_id) VALUES (?, ?, ?, ?, ?)",
            (username, generate_password_hash(password), role, student_id, instructor_id or None))],
          f"สร้างบัญชี {username} แล้ว")
    return back("admin.users")


@bp.post("/users/<int:user_id>/password")
@require("admin")
def user_password(user_id):
    password = request.form.get("password", "")
    if len(password) < MIN_PASSWORD:
        flash(f"ไม่สำเร็จ: รหัสผ่านต้องยาวอย่างน้อย {MIN_PASSWORD} ตัวอักษร", "error")
        return back("admin.users")
    write([("UPDATE app_user SET password_hash = ? WHERE user_id = ?", (generate_password_hash(password), user_id))],
          "ตั้งรหัสผ่านใหม่แล้ว")
    return back("admin.users")


@bp.post("/users/<int:user_id>/toggle")
@require("admin")
def user_toggle(user_id):
    if user_id == g.user["user_id"]:
        flash("ไม่สำเร็จ: ปิดบัญชีของตัวเองไม่ได้", "error")
        return back("admin.users")
    write([("UPDATE app_user SET is_active = 1 - is_active WHERE user_id = ?", (user_id,))], "เปลี่ยนสถานะบัญชีแล้ว")
    return back("admin.users")


# ------------------------------------------------------------------ ประวัติ และรีเซ็ตข้อมูลสาธิต
@bp.route("/log")
@require("admin")
def log():
    sid = request.args.get("sid", "").strip()
    action = request.args.get("action", "").strip()
    return render_template("reg_log.html", logs=rows(R.REG_LOG, sid=sid, action=action),
                           sid=sid, action=action, lock_sid=False)


@bp.post("/reset")
@require("admin")
def reset():
    if request.form.get("confirm", "").strip() != "รีเซ็ต":     # กันกดโดยไม่ตั้งใจ (หน้าเว็บบังคับไว้แล้วอีกชั้น)
        flash("ไม่สำเร็จ: พิมพ์คำว่า รีเซ็ต เพื่อยืนยันก่อน", "error")
        return back("admin.dashboard")
    close_db()
    build_db()
    flash("รีเซ็ตฐานข้อมูลกลับเป็นข้อมูลตั้งต้นแล้ว", "ok")
    return back("admin.dashboard")

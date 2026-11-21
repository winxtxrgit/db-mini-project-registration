"""อาจารย์ผู้จัดตาราง (scheduler): เวลาเรียน ห้อง อาจารย์ผู้สอน เวลาสอบ

ฝ่ายทะเบียนเปิดดูหน้าเหล่านี้ได้แต่แก้ไม่ได้ (ปุ่มแก้ไขแสดงเฉพาะผู้จัดตาราง)
กฎห้องซ้ำ อาจารย์ซ้ำ นักศึกษาที่ลงแล้วเรียน/สอบชน และห้องสอบจุไม่พอ ตรวจใน trigger ทั้งหมด
"""
from collections import defaultdict

from flask import Blueprint, flash, redirect, render_template, url_for

import reports as R
from core import form_int, form_str, one, require, rows, section_label, write

bp = Blueprint("scheduler", __name__, url_prefix="/schedule")

VIEW = ("scheduler", "admin")   # ดูได้
EDIT = ("scheduler",)           # แก้ได้


def back():
    return redirect(url_for("scheduler.home"))


def _fail(exc: Exception):
    flash(f"ไม่สำเร็จ: {exc}", "error")
    return back()


@bp.route("/")
@require(*VIEW)
def home():
    meetings, exams, teachers = defaultdict(list), defaultdict(list), defaultdict(list)
    for m in rows(R.SCHED_MEETINGS):
        meetings[m["section_id"]].append(m)
    for x in rows(R.SCHED_EXAMS):
        exams[x["section_id"]].append(x)
    for t in rows(R.SCHED_INSTRUCTORS):
        teachers[t["section_id"]].append(t)
    return render_template(
        "scheduler/home.html",
        sections=rows(R.SCHED_SECTIONS), meetings=meetings, exams=exams, teachers=teachers,
        rooms=rows("SELECT room_code, capacity FROM room ORDER BY room_code"),
        instructors=rows("SELECT instructor_id, full_name FROM instructor ORDER BY full_name"),
        term=one("SELECT term_id FROM term WHERE is_current = 1"),
    )


# ------------------------------------------------------------------ เวลาเรียน
def _meeting_form():
    day = form_int("day_of_week")
    if not 1 <= day <= 7:
        raise ValueError("วันต้องอยู่ระหว่าง 1 (จันทร์) ถึง 7 (อาทิตย์)")
    return day, form_str("start_time"), form_str("end_time"), form_str("room_code", required=False)


@bp.post("/sections/<int:section_id>/meetings")
@require(*EDIT)
def meeting_add(section_id):
    try:
        day, start, end, room = _meeting_form()
    except ValueError as exc:
        return _fail(exc)
    write([("INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) "
            "VALUES (?, ?, ?, ?, ?)", (section_id, day, start, end, room))],
          f"เพิ่มเวลาเรียน {section_label(section_id)} แล้ว")
    return back()


@bp.post("/meetings/<int:meeting_id>")
@require(*EDIT)
def meeting_edit(meeting_id):
    try:
        day, start, end, room = _meeting_form()
    except ValueError as exc:
        return _fail(exc)
    write([("UPDATE class_meeting SET day_of_week = ?, start_time = ?, end_time = ?, room_code = ? "
            "WHERE meeting_id = ?", (day, start, end, room, meeting_id))], "แก้เวลาเรียนแล้ว")
    return back()


@bp.post("/meetings/<int:meeting_id>/delete")
@require(*EDIT)
def meeting_delete(meeting_id):
    write([("DELETE FROM class_meeting WHERE meeting_id = ?", (meeting_id,))], "ลบเวลาเรียนแล้ว")
    return back()


# ------------------------------------------------------------------ อาจารย์ผู้สอน
@bp.post("/sections/<int:section_id>/instructors")
@require(*EDIT)
def instructor_add(section_id):
    try:
        iid = form_int("instructor_id")
    except ValueError as exc:
        return _fail(exc)
    write([("INSERT INTO section_instructor (section_id, instructor_id) VALUES (?, ?)", (section_id, iid))],
          f"มอบหมายอาจารย์ให้ {section_label(section_id)} แล้ว")
    return back()


@bp.post("/sections/<int:section_id>/instructors/<int:instructor_id>/delete")
@require(*EDIT)
def instructor_remove(section_id, instructor_id):
    write([("DELETE FROM section_instructor WHERE section_id = ? AND instructor_id = ?",
            (section_id, instructor_id))], "ถอดอาจารย์ผู้สอนแล้ว")
    return back()


# ------------------------------------------------------------------ เวลาสอบ
def _exam_form():
    return form_str("exam_date"), form_str("start_time"), form_str("end_time"), form_str("room_code", required=False)


@bp.post("/sections/<int:section_id>/exams")
@require(*EDIT)
def exam_add(section_id):
    try:
        exam_type = form_str("exam_type")
        if exam_type not in ("MIDTERM", "FINAL"):
            raise ValueError("ประเภทสอบไม่ถูกต้อง")
        date, start, end, room = _exam_form()
    except ValueError as exc:
        return _fail(exc)
    write([("INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time, room_code) "
            "VALUES (?, ?, ?, ?, ?, ?)", (section_id, exam_type, date, start, end, room))],
          f"เพิ่มเวลาสอบ {section_label(section_id)} แล้ว")
    return back()


@bp.post("/exams/<int:exam_id>")
@require(*EDIT)
def exam_edit(exam_id):
    try:
        date, start, end, room = _exam_form()
    except ValueError as exc:
        return _fail(exc)
    write([("UPDATE exam SET exam_date = ?, start_time = ?, end_time = ?, room_code = ? WHERE exam_id = ?",
            (date, start, end, room, exam_id))], "แก้เวลาสอบแล้ว")
    return back()


@bp.post("/exams/<int:exam_id>/delete")
@require(*EDIT)
def exam_delete(exam_id):
    write([("DELETE FROM exam WHERE exam_id = ?", (exam_id,))], "ลบเวลาสอบแล้ว")
    return back()


# ------------------------------------------------------------------ ห้อง อาจารย์ ประวัติ
@bp.route("/rooms")
@require(*VIEW)
def rooms():
    usage = defaultdict(list)
    for u in rows(R.R8_ROOM_USAGE):
        usage[u["room_code"]].append(u)
    return render_template("scheduler/rooms.html", usage=usage,
                           rooms=rows("SELECT room_code, capacity FROM room ORDER BY room_code"))


@bp.post("/rooms")
@require(*EDIT)
def room_save():
    try:
        code = form_str("room_code")
        cap = form_int("capacity", default=0) or None
    except ValueError as exc:
        flash(f"ไม่สำเร็จ: {exc}", "error")
        return redirect(url_for("scheduler.rooms"))
    write([("INSERT INTO room (room_code, capacity) VALUES (?, ?) "
            "ON CONFLICT (room_code) DO UPDATE SET capacity = excluded.capacity", (code, cap))],
          f"บันทึกห้อง {code} แล้ว")
    return redirect(url_for("scheduler.rooms"))


@bp.route("/instructors")
@require(*VIEW)
def instructors():
    return render_template("scheduler/instructors.html", load=rows(R.R9_INSTRUCTOR_LOAD))


@bp.route("/log")
@require(*VIEW)
def log():
    return render_template("scheduler/log.html", logs=rows(R.SCHEDULE_LOG))

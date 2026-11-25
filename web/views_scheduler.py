"""อาจารย์ผู้จัดตาราง (scheduler): เวลาเรียน ห้อง อาจารย์ผู้สอน เวลาสอบ และการล็อกตาราง

ฝ่ายทะเบียนเปิดดูหน้าเหล่านี้ได้แต่แก้ไม่ได้ (ปุ่มแก้ไขแสดงเฉพาะผู้จัดตาราง)
กฎห้องซ้ำ อาจารย์ซ้ำ นักศึกษาที่ลงแล้วเรียน/สอบชน ห้องสอบจุไม่พอ และการล็อกตาราง ตรวจใน trigger ทั้งหมด
หน้าเว็บแค่ซ่อนฟอร์มของกลุ่มที่ล็อกแล้ว ถ้ามีคนส่งฟอร์มมาเอง trigger จะปฏิเสธและแสดงข้อความ error
"""
from collections import defaultdict

from flask import Blueprint, flash, redirect, render_template, request, url_for

import reports as R
from core import form_int, form_str, one, require, rows, section_label, timetable, write

bp = Blueprint("scheduler", __name__, url_prefix="/schedule")

VIEW = ("scheduler", "admin")   # ดูได้
EDIT = ("scheduler",)           # แก้ได้


def back(section_id=None):
    """กลับไปหน้าจัดตาราง โดยเปิดกลุ่มเรียนที่เพิ่งแก้ค้างไว้ (?open=) และเลื่อนไปที่กลุ่มนั้น (#sec)"""
    if section_id is None:
        return redirect(url_for("scheduler.home"))
    return redirect(url_for("scheduler.home", open=section_id, _anchor=f"sec{section_id}"))


def _fail(exc: Exception, section_id=None):
    flash(f"ไม่สำเร็จ: {exc}", "error")
    return back(section_id)


def _section_of(table: str, key: str, value: int):
    """หา section_id ของคาบเรียนหรือเวลาสอบ (table/key มาจากโค้ดเท่านั้น ไม่ได้มาจากผู้ใช้)"""
    r = one(f"SELECT section_id FROM {table} WHERE {key} = :v", v=value)
    return r["section_id"] if r else None


@bp.route("/")
@require(*VIEW)
def home():
    meetings, exams, teachers = defaultdict(list), defaultdict(list), defaultdict(list)
    exam_rooms = {}
    for m in rows(R.SCHED_MEETINGS):
        meetings[m["section_id"]].append(m)
    for x in rows(R.SCHED_EXAMS):
        exams[x["section_id"]].append(x)
        exam_rooms[x["exam_id"]] = rows(
            R.R13_EXAM_ROOMS,
            section_id=x["section_id"],
            exam_date=x["exam_date"],
            start_time=x["start_time"],
            end_time=x["end_time"],
        )
    for t in rows(R.SCHED_INSTRUCTORS):
        teachers[t["section_id"]].append(t)
    progress = rows(R.R11_SCHEDULE_PROGRESS)
    return render_template(
        "scheduler/home.html",
        sections=rows(R.SCHED_SECTIONS), meetings=meetings, exams=exams, teachers=teachers,
        exam_rooms=exam_rooms,
        progress=progress, progress_by_id={p["section_id"]: p for p in progress},
        # วิชาส่วนกลางที่วางคาบแล้วแต่ยังไม่ล็อก: ระหว่างนี้ trigger ไม่ให้วางคาบวิชาอื่น (R11)
        service_pending=[p for p in progress
                         if p["course_category"] == "service" and p["hours_placed"] and not p["is_locked"]],
        exam_same_day=rows(R.R16_EXAM_SAME_DAY),
        rooms=rows("SELECT room_code, capacity FROM room ORDER BY room_code"),
        instructors=rows("SELECT instructor_id, full_name FROM instructor ORDER BY full_name"),
        term=one("SELECT term_id FROM term WHERE is_current = 1"),
        open_id=request.args.get("open", type=int),
    )


@bp.route("/overview")
@require(*VIEW)
def overview():
    curricula = rows(
        "SELECT c.curriculum_id, p.program_name "
        "FROM curriculum c JOIN program p ON p.program_code = c.program_code "
        "WHERE EXISTS (SELECT 1 FROM study_plan sp WHERE sp.curriculum_id = c.curriculum_id) "
        "ORDER BY c.curriculum_id"
    )
    selected_curr = request.args.get("curriculum") or (curricula[0]["curriculum_id"] if curricula else "CPE63")
    year_level = request.args.get("year", type=int)
    if year_level not in (1, 2, 3, 4):
        year_level = None
    grid = rows(R.R12_SCHEDULE_OVERVIEW, curriculum_id=selected_curr)
    filtered = rows(R.R12_SCHEDULE_OVERVIEW_FILTERED, curriculum_id=selected_curr, year_level=year_level) if year_level else []
    return render_template(
        "scheduler/overview.html",
        curricula=curricula,
        selected_curr=selected_curr,
        year_level=year_level,
        grid=grid,
        filtered=filtered,
        retake_conflicts=rows(R.R14_RETAKE_CONFLICT, curriculum_id=selected_curr),
        cohort_conflicts=rows(R.R14_COHORT_CONFLICT, curriculum_id=selected_curr),
        exam_same_day=rows(R.R16_EXAM_SAME_DAY),
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
        return _fail(exc, section_id)
    write([("INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) "
            "VALUES (?, ?, ?, ?, ?)", (section_id, day, start, end, room))],
          f"เพิ่มเวลาเรียน {section_label(section_id)} แล้ว")
    return back(section_id)


@bp.post("/meetings/<int:meeting_id>")
@require(*EDIT)
def meeting_edit(meeting_id):
    sid = _section_of("class_meeting", "meeting_id", meeting_id)
    try:
        day, start, end, room = _meeting_form()
    except ValueError as exc:
        return _fail(exc, sid)
    write([("UPDATE class_meeting SET day_of_week = ?, start_time = ?, end_time = ?, room_code = ? "
            "WHERE meeting_id = ?", (day, start, end, room, meeting_id))], "แก้เวลาเรียนแล้ว")
    return back(sid)


@bp.post("/meetings/<int:meeting_id>/delete")
@require(*EDIT)
def meeting_delete(meeting_id):
    sid = _section_of("class_meeting", "meeting_id", meeting_id)
    write([("DELETE FROM class_meeting WHERE meeting_id = ?", (meeting_id,))], "ลบเวลาเรียนแล้ว")
    return back(sid)


# ------------------------------------------------------------------ อาจารย์ผู้สอน
@bp.post("/sections/<int:section_id>/instructors")
@require(*EDIT)
def instructor_add(section_id):
    try:
        iid = form_int("instructor_id")
    except ValueError as exc:
        return _fail(exc, section_id)
    write([("INSERT INTO section_instructor (section_id, instructor_id) VALUES (?, ?)", (section_id, iid))],
          f"มอบหมายอาจารย์ให้ {section_label(section_id)} แล้ว")
    return back(section_id)


@bp.post("/sections/<int:section_id>/instructors/<int:instructor_id>/delete")
@require(*EDIT)
def instructor_remove(section_id, instructor_id):
    write([("DELETE FROM section_instructor WHERE section_id = ? AND instructor_id = ?",
            (section_id, instructor_id))], "ถอดอาจารย์ผู้สอนแล้ว")
    return back(section_id)


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
        return _fail(exc, section_id)
    write([("INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time, room_code) "
            "VALUES (?, ?, ?, ?, ?, ?)", (section_id, exam_type, date, start, end, room))],
          f"เพิ่มเวลาสอบ {section_label(section_id)} แล้ว")
    return back(section_id)


@bp.post("/exams/<int:exam_id>")
@require(*EDIT)
def exam_edit(exam_id):
    sid = _section_of("exam", "exam_id", exam_id)
    try:
        date, start, end, room = _exam_form()
    except ValueError as exc:
        return _fail(exc, sid)
    write([("UPDATE exam SET exam_date = ?, start_time = ?, end_time = ?, room_code = ? WHERE exam_id = ?",
            (date, start, end, room, exam_id))], "แก้เวลาสอบแล้ว")
    return back(sid)


@bp.post("/exams/<int:exam_id>/delete")
@require(*EDIT)
def exam_delete(exam_id):
    sid = _section_of("exam", "exam_id", exam_id)
    write([("DELETE FROM exam WHERE exam_id = ?", (exam_id,))], "ลบเวลาสอบแล้ว")
    return back(sid)


# ------------------------------------------------------------------ ล็อกตาราง
@bp.post("/sections/<int:section_id>/lock")
@require(*EDIT)
def section_lock(section_id):
    reason = form_str("lock_reason", required=False)
    # มีแถวอยู่แล้ว = UPDATE (trigger ตรวจว่ามีคาบแล้ว ใส่เวลา/ผู้ล็อก และบันทึกประวัติ) / ยังไม่มี = INSERT
    write([("INSERT INTO scheduling_priority (section_id, is_locked, lock_reason) VALUES (?, 1, ?) "
            "ON CONFLICT (section_id) DO UPDATE SET is_locked = 1, lock_reason = excluded.lock_reason",
            (section_id, reason))],
          f"ล็อกตาราง {section_label(section_id)} แล้ว")
    return back(section_id)


@bp.post("/sections/<int:section_id>/unlock")
@require(*EDIT)
def section_unlock(section_id):
    write([("UPDATE scheduling_priority SET is_locked = 0 WHERE section_id = ?", (section_id,))],
          f"ปลดล็อก {section_label(section_id)} แล้ว")
    return back(section_id)


# ------------------------------------------------------------------ ห้อง อาจารย์ ประวัติ
@bp.route("/rooms")
@require(*VIEW)
def rooms():
    usage = defaultdict(list)
    for u in rows(R.R8_ROOM_USAGE):
        usage[u["room_code"]].append(u)
    room_list = rows("SELECT room_code, capacity FROM room ORDER BY room_code")
    selected = request.args.get("room") or next((r["room_code"] for r in room_list if usage[r["room_code"]]), None)
    tt = timetable(rows(R.ROOM_MEETINGS, room=selected), sub_key="teachers") if selected else {"empty": True}
    free_day = request.args.get("day", type=int)
    free_start = (request.args.get("start") or "").strip()
    free_end = (request.args.get("end") or "").strip()
    min_cap = request.args.get("min_cap", type=int) or 0
    free_rooms = None
    if free_day and 1 <= free_day <= 7 and free_start and free_end:
        free_rooms = rows(
            R.R15_FREE_ROOMS,
            day_of_week=free_day,
            start_time=free_start,
            end_time=free_end,
            min_capacity=min_cap,
        )
    return render_template(
        "scheduler/rooms.html",
        usage=usage, rooms=room_list, selected=selected, tt=tt,
        free_day=free_day, free_start=free_start, free_end=free_end, min_cap=min_cap,
        free_rooms=free_rooms,
    )


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
    load = rows(R.R9_INSTRUCTOR_LOAD)
    selected = request.args.get("instructor", type=int) or next((r["instructor_id"] for r in load if r["sections"]), None)
    tt = timetable(rows(R.INSTRUCTOR_MEETINGS, iid=selected)) if selected else {"empty": True}
    return render_template("scheduler/instructors.html", load=load, selected=selected, tt=tt)


@bp.route("/log")
@require(*VIEW)
def log():
    return render_template("scheduler/log.html", logs=rows(R.SCHEDULE_LOG))

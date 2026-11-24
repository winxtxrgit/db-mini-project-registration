"""ทดสอบหน้าเว็บทั้ง 3 บทบาท: สิทธิ์ CSRF และกฎทางธุรกิจที่มาจาก trigger

รัน (จากโฟลเดอร์ Mini_Project_PlanA):  python -m unittest discover -s web -v
ใช้ฐานข้อมูลชั่วคราว ไม่แตะ web/registration.db
"""
import re
import sqlite3
import tempfile
import unittest
from pathlib import Path

import core

_tmp = tempfile.TemporaryDirectory()
core.DB_PATH = Path(_tmp.name) / "test.db"

from app import app  # noqa: E402  (ต้อง import หลังเปลี่ยน DB_PATH)

PASSWORD = "demo1234"   # รหัสผ่านทดสอบจาก seed.sql


def flashes(resp):
    return re.findall(r'class="flash (\w+)">([^<]*)<', resp.get_data(as_text=True))


class Base(unittest.TestCase):
    def setUp(self):
        core.build_db()
        app.config["TESTING"] = True
        self.c = app.test_client()

    def sql(self, query, *params):
        con = sqlite3.connect(core.DB_PATH)
        try:
            with con:
                return con.execute(query, params).fetchall()
        finally:
            con.close()

    def csrf(self):
        with self.c.session_transaction() as s:
            s.setdefault("csrf", "test-token")
            return s["csrf"]

    def login(self, username):
        r = self.c.post("/login", data={"username": username, "password": PASSWORD, "csrf_token": self.csrf()})
        self.assertEqual(r.status_code, 302, f"login {username} failed")

    def post(self, url, **data):
        data["csrf_token"] = self.csrf()
        return self.c.post(url, data=data, follow_redirects=True)


class AuthTests(Base):
    def test_requires_login(self):
        for url in ("/me/", "/admin/", "/schedule/"):
            r = self.c.get(url)
            self.assertEqual(r.status_code, 302)
            self.assertIn("/login", r.headers["Location"])

    def test_wrong_password(self):
        r = self.c.post("/login", data={"username": "admin", "password": "wrong", "csrf_token": self.csrf()})
        self.assertIn(("error", "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง"), flashes(r))

    def test_unknown_user_same_message(self):
        r = self.c.post("/login", data={"username": "nobody", "password": "x", "csrf_token": self.csrf()})
        self.assertIn(("error", "ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง"), flashes(r))

    def test_csrf_required(self):
        self.login("6799000001")
        r = self.c.post("/me/enroll/10", data={})
        self.assertEqual(r.status_code, 400)

    def test_open_redirect_blocked(self):
        r = self.c.post("/login?next=//evil.example", data={"username": "admin", "password": PASSWORD,
                                                             "csrf_token": self.csrf()})
        self.assertFalse(r.headers["Location"].startswith("//"))

    def test_role_isolation(self):
        self.login("6799000001")
        self.assertEqual(self.c.get("/admin/").status_code, 403)
        self.assertEqual(self.c.get("/schedule/").status_code, 403)
        self.c.post("/logout", data={"csrf_token": self.csrf()})
        self.login("scheduler")
        self.assertEqual(self.c.get("/admin/").status_code, 403)
        self.assertEqual(self.c.get("/me/").status_code, 403)

    def test_admin_can_view_but_not_edit_schedule(self):
        self.login("admin")
        self.assertEqual(self.c.get("/schedule/").status_code, 200)
        r = self.post("/schedule/meetings/1/delete")
        self.assertEqual(r.status_code, 403)

    def test_deactivated_user_cannot_login(self):
        self.sql("UPDATE app_user SET is_active = 0 WHERE username = '6799000002'")
        r = self.c.post("/login", data={"username": "6799000002", "password": PASSWORD, "csrf_token": self.csrf()})
        self.assertEqual(r.status_code, 200)   # อยู่หน้า login เดิม

    def test_all_pages_render(self):
        pages = {"6799000001": ["/me/", "/me/log"],
                 "admin": ["/admin/", "/admin/terms", "/admin/sections", "/admin/students", "/admin/students/6799000001",
                           "/admin/credits", "/admin/users", "/admin/log", "/schedule/", "/schedule/rooms"],
                 "scheduler": ["/schedule/", "/schedule/rooms", "/schedule/instructors", "/schedule/log"]}
        for user, urls in pages.items():
            self.c = app.test_client()
            self.login(user)
            for url in urls:
                self.assertEqual(self.c.get(url).status_code, 200, url)


class StudentTests(Base):
    def setUp(self):
        super().setUp()
        self.login("6799000001")

    def test_clash_rejected(self):
        r = self.post("/me/enroll/10")
        self.assertIn(("error", "ไม่สำเร็จ: เวลาเรียนชนกับวิชาที่ลงไว้แล้ว"), flashes(r))

    def test_only_own_record(self):
        # URL ไม่มีรหัสนักศึกษาให้ปลอม: ทำรายการได้เฉพาะของคนที่ login อยู่
        self.post("/me/drop/2")
        self.assertEqual(self.sql("SELECT COUNT(*) FROM enrollment WHERE student_id='6799000001' AND section_id=2")[0][0], 0)
        self.assertEqual(self.sql("SELECT COUNT(*) FROM enrollment WHERE student_id='6799000002' AND section_id=2")[0][0], 1)

    def test_window_closed(self):
        self.sql("UPDATE term SET reg_close_at = '2000-01-02 00:00', reg_open_at = '2000-01-01 00:00' WHERE is_current = 1")
        r = self.post("/me/drop/2")
        self.assertIn(("error", "ไม่สำเร็จ: ไม่อยู่ในช่วงลงทะเบียนหรือช่วงลดวิชาของภาคเรียนนี้"), flashes(r))

    def test_log_has_actor(self):
        self.post("/me/drop/2")
        actor = self.sql("SELECT u.username FROM registration_log l JOIN app_user u ON u.user_id = l.actor_user_id "
                         "ORDER BY l.log_id DESC LIMIT 1")
        self.assertEqual(actor[0][0], "6799000001")
        self.assertEqual(self.sql("SELECT COUNT(*) FROM app_session")[0][0], 0)   # ไม่ค้างหลังทำรายการ

    def test_waitlist_and_unwait(self):
        # section 7 (310-3313) เต็มแล้ว 21/21
        # 6799000005 มีสิทธิ์ลงและยังไม่เคยลงวิชานี้ จึงสามารถเข้าคิวสำรองได้
        self.login("6799000005")
        r = self.post("/me/waitlist/7")
        self.assertTrue(any(lvl == "ok" and "เข้าคิวสำรอง" in msg and "310-3313" in msg for lvl, msg in flashes(r)))
        self.assertEqual(self.sql("SELECT COUNT(*) FROM waitlist WHERE student_id='6799000005' AND section_id=7")[0][0], 1)

        # ออกจากคิว (unwait)
        r = self.post("/me/unwait/7")
        self.assertTrue(any(lvl == "ok" and "ออกจากคิว" in msg and "310-3313" in msg for lvl, msg in flashes(r)))
        self.assertEqual(self.sql("SELECT COUNT(*) FROM waitlist WHERE student_id='6799000005' AND section_id=7")[0][0], 0)

    def test_missing_prerequisite_rejected(self):
        # 6799000005 ต้องการลง 310-3416 (section 5) ซึ่งมีวิชาบังคับก่อนคือ 310-2101
        # เมื่อลบวิชาบังคับก่อนออกจาก transcript จะต้องถูกปฏิเสธ
        self.login("6799000005")
        self.sql("DELETE FROM transcript WHERE student_id = '6799000005' AND course_code = '310-2101'")
        r = self.post("/me/enroll/5")
        self.assertIn(("error", "ไม่สำเร็จ: ยังไม่ผ่านวิชาบังคับก่อน"), flashes(r))

    def test_max_credits_rejected_web(self):
        # 6799000005 ลงอยู่แล้ว 6 หน่วยกิต (section 2 และ 3)
        # เมื่อลดเพดานเป็น 6 แล้วพยายามลงเพิ่มใน section 4 (3 หน่วยกิต) จะต้องถูกปฏิเสธ
        self.login("6799000005")
        self.sql("UPDATE term SET max_credits = 6 WHERE is_current = 1")
        r = self.post("/me/enroll/4")
        self.assertIn(("error", "ไม่สำเร็จ: หน่วยกิตรวมเกินเพดานที่ลงได้ในภาคเรียนนี้"), flashes(r))

    def test_invalid_action_404(self):
        r = self.post("/me/invalid_action/1")
        self.assertEqual(r.status_code, 404)


class AdminTests(Base):
    def setUp(self):
        super().setUp()
        self.login("admin")

    def test_admin_ignores_window_but_not_rules(self):
        self.sql("UPDATE term SET reg_close_at = '2000-01-02 00:00', reg_open_at = '2000-01-01 00:00' WHERE is_current = 1")
        r = self.post("/admin/students/6799000005/drop/2")
        self.assertIn("ok", [c for c, _ in flashes(r)])
        r = self.post("/admin/students/6799000001/enroll/10")
        self.assertIn(("error", "ไม่สำเร็จ: เวลาเรียนชนกับวิชาที่ลงไว้แล้ว"), flashes(r))

    def test_capacity_rules_and_promote(self):
        # เติม 310-2205 ให้เต็ม แล้วให้ F0290 เข้าคิว
        self.sql("INSERT INTO enrollment (student_id, section_id) VALUES ('F0287',1),('F0288',1),('F0289',1)")
        self.sql("INSERT INTO waitlist (student_id, section_id) VALUES ('F0290', 1)")
        r = self.post("/admin/sections/1/capacity", capacity="40")
        self.assertIn(("error", "ไม่สำเร็จ: จำนวนรับต้องไม่น้อยกว่าจำนวนที่ลงทะเบียนแล้ว"), flashes(r))
        r = self.post("/admin/sections/1/capacity", capacity="51")
        self.assertIn(("info", "เลื่อนจากคิวสำรอง: F0290"), flashes(r))

    def test_quota_release_promotes(self):
        self.sql("INSERT INTO waitlist (student_id, section_id) VALUES ('B6907', 9)")
        r = self.post("/admin/sections/9/quota", curriculum_id="BBA69", seats="7")
        self.assertIn(("info", "เลื่อนจากคิวสำรอง: B6907"), flashes(r))

    def test_term_window_and_current(self):
        r = self.post("/admin/terms/2569-2", reg_open_at="2026-10-01T08:00", reg_close_at="2026-09-01T08:00",
                      max_credits="22")
        self.assertIn("error", [c for c, _ in flashes(r)])            # ปิดก่อนเปิดไม่ได้ (CHECK)
        r = self.post("/admin/terms/2569-1/current")
        self.assertEqual(self.sql("SELECT term_id FROM term WHERE is_current = 1")[0][0], "2569-1")

    def test_create_student_and_account(self):
        r = self.post("/admin/students/new", student_id="6999000001", first_name="ทดสอบ", last_name="ใหม่",
                      curriculum_id="CPE63", entry_year="2569", password="short")
        self.assertIn("error", [c for c, _ in flashes(r)])
        self.post("/admin/students/new", student_id="6999000001", first_name="ทดสอบ", last_name="ใหม่",
                  curriculum_id="CPE63", entry_year="2569", password="longenough1")
        self.assertEqual(self.sql("SELECT role FROM app_user WHERE username = '6999000001'")[0][0], "student")

    def test_cannot_disable_self(self):
        uid = self.sql("SELECT user_id FROM app_user WHERE username = 'admin'")[0][0]
        r = self.post(f"/admin/users/{uid}/toggle")
        self.assertIn(("error", "ไม่สำเร็จ: ปิดบัญชีของตัวเองไม่ได้"), flashes(r))


class SchedulerTests(Base):
    def setUp(self):
        super().setUp()
        self.login("scheduler")

    def test_room_clash(self):
        r = self.post("/schedule/sections/2/meetings", day_of_week="3", start_time="09:00", end_time="10:00",
                      room_code="15208")
        self.assertIn(("error", "ไม่สำเร็จ: ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว"), flashes(r))

    def test_move_meeting_clashes_students(self):
        mid = self.sql("SELECT meeting_id FROM class_meeting WHERE section_id = 6")[0][0]
        r = self.post(f"/schedule/meetings/{mid}", day_of_week="2", start_time="13:00", end_time="16:00",
                      room_code="15309")
        self.assertIn(("error", "ไม่สำเร็จ: มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้"), flashes(r))

    def test_real_case_fix_and_log(self):
        # ย้าย 310-2205 ไปวันศุกร์ (กรณีจริงใน README) ผ่าน และมีประวัติพร้อมผู้ทำ
        mid = self.sql("SELECT meeting_id FROM class_meeting WHERE section_id = 1")[0][0]
        r = self.post(f"/schedule/meetings/{mid}", day_of_week="5", start_time="09:00", end_time="12:00",
                      room_code="15208")
        self.assertIn(("ok", "แก้เวลาเรียนแล้ว"), flashes(r))
        log = self.sql("SELECT l.action, u.username FROM schedule_log l JOIN app_user u ON u.user_id = l.actor_user_id")
        self.assertEqual(log, [("CHANGE", "scheduler")])

    def test_bad_time_format(self):
        r = self.post("/schedule/sections/2/meetings", day_of_week="5", start_time="9am", end_time="12:00",
                      room_code="")
        self.assertIn("error", [c for c, _ in flashes(r)])

    def test_instructor_clash(self):
        r = self.post("/schedule/sections/10/instructors", instructor_id="1")
        self.assertIn(("error", "ไม่สำเร็จ: อาจารย์ท่านนี้มีคาบสอนวิชาอื่นในเวลาเดียวกับกลุ่มเรียนนี้"), flashes(r))

    def test_exam_room_capacity(self):
        self.post("/schedule/rooms", room_code="R-SMALL", capacity="10")
        eid = self.sql("SELECT exam_id FROM exam WHERE section_id = 10")[0][0]
        r = self.post(f"/schedule/exams/{eid}", exam_date="2027-03-08", start_time="09:00", end_time="12:00",
                      room_code="R-SMALL")
        self.assertIn(("error", "ไม่สำเร็จ: ห้องสอบจุไม่พอสำหรับจำนวนนักศึกษาที่ลงทะเบียน"), flashes(r))


class UITests(Base):
    """โครงหน้าเว็บที่ออกแบบใหม่: การเข้าถึง และการกลับมาที่แถว/กลุ่มเดิมหลังทำรายการ"""

    def test_skip_link_and_current_nav(self):
        self.login("admin")
        html = self.c.get("/admin/sections").get_data(as_text=True)
        self.assertIn('class="skip" href="#main"', html)
        self.assertIn('id="main"', html)
        self.assertRegex(html, r'href="/admin/sections"\s+aria-current="page"')

    def test_student_action_returns_to_row(self):
        self.login("6799000001")
        r = self.c.post("/me/enroll/10", data={"csrf_token": self.csrf()})
        self.assertEqual(r.status_code, 302)
        self.assertTrue(r.headers["Location"].endswith("/me/#sec10"))

    def test_scheduler_edit_reopens_section(self):
        self.login("scheduler")
        mid = self.sql("SELECT meeting_id FROM class_meeting WHERE section_id = 1")[0][0]
        r = self.c.post(f"/schedule/meetings/{mid}", data={"csrf_token": self.csrf(), "day_of_week": "5",
                                                            "start_time": "09:00", "end_time": "12:00",
                                                            "room_code": "15208"})
        self.assertTrue(r.headers["Location"].endswith("/schedule/?open=1#sec1"))
        html = self.c.get("/schedule/?open=1").get_data(as_text=True)
        self.assertRegex(html, r'id="sec1"\s+open')

    def test_student_timetable_rendered(self):
        self.login("6799000001")
        html = self.c.get("/me/").get_data(as_text=True)
        self.assertIn('class="tt"', html)
        self.assertIn("tt-block", html)

    def test_reset_requires_confirmation(self):
        self.login("admin")
        self.sql("DELETE FROM enrollment WHERE student_id = '6799000001'")
        r = self.post("/admin/reset")
        self.assertIn("error", [c for c, _ in flashes(r)])
        self.assertEqual(self.sql("SELECT COUNT(*) FROM enrollment WHERE student_id = '6799000001'")[0][0], 0)
        r = self.post("/admin/reset", confirm="รีเซ็ต")
        self.assertIn("ok", [c for c, _ in flashes(r)])
        self.assertGreater(self.sql("SELECT COUNT(*) FROM enrollment WHERE student_id = '6799000001'")[0][0], 0)


class CalendarTests(Base):
    """ช่วงเพิ่ม/ลดวิชาแยกจากช่วงลงทะเบียน (ตามปฏิทินการศึกษาจริงของ reg)"""

    def drop_only(self):
        self.sql("UPDATE term SET reg_open_at = '2000-01-01 00:00', reg_close_at = '2000-01-02 00:00', "
                 "drop_open_at = '2000-01-01 00:00', drop_close_at = '2099-12-31 23:59' WHERE is_current = 1")

    def test_drop_only_window(self):
        self.drop_only()
        self.login("6799000005")
        r = self.post("/me/drop/3")
        self.assertIn("ok", [c for c, _ in flashes(r)])
        r = self.post("/me/enroll/3")
        self.assertIn(("error", "ไม่สำเร็จ: ไม่อยู่ในช่วงลงทะเบียนหรือช่วงเพิ่มวิชาของภาคเรียนนี้"), flashes(r))
        self.assertIn("ช่วงลดวิชา", r.get_data(as_text=True))

    def test_add_window_allows_enroll_not_drop(self):
        self.sql("UPDATE term SET reg_open_at = '2000-01-01 00:00', reg_close_at = '2000-01-02 00:00', "
                 "add_open_at = '2000-01-01 00:00', add_close_at = '2099-12-31 23:59' WHERE is_current = 1")
        self.login("6799000005")
        r = self.post("/me/drop/3")
        self.assertIn(("error", "ไม่สำเร็จ: ไม่อยู่ในช่วงลงทะเบียนหรือช่วงลดวิชาของภาคเรียนนี้"), flashes(r))

    def test_drop_promotes_waitlist_even_when_add_closed(self):
        # เดิมกฎช่วงเวลาตรวจทุกการลง ทำให้การเลื่อนคิวให้คนอื่นตอนถอนในช่วงลดวิชาล้มทั้ง transaction
        self.drop_only()
        self.sql("INSERT INTO enrollment (student_id, section_id) VALUES ('F0287',1),('F0288',1),('F0289',1)")
        self.sql("INSERT INTO waitlist (student_id, section_id) VALUES ('F0290', 1)")
        self.login("6799000001")
        r = self.post("/me/drop/1")
        self.assertIn("ok", [c for c, _ in flashes(r)])
        self.assertEqual(self.sql("SELECT COUNT(*) FROM enrollment WHERE student_id = 'F0290' AND section_id = 1")[0][0], 1)

    def test_admin_sets_windows(self):
        self.login("admin")
        self.post("/admin/terms/2569-2", reg_open_at="2026-10-29T09:00", reg_close_at="2026-11-04T15:30",
                  add_open_at="2026-11-09T09:00", add_close_at="2026-11-20T15:30",
                  drop_open_at="2026-11-09T09:00", drop_close_at="2026-12-04T15:30", max_credits="22")
        row = self.sql("SELECT add_open_at, drop_close_at FROM term WHERE term_id = '2569-2'")[0]
        self.assertEqual(row, ("2026-11-09 09:00", "2026-12-04 15:30"))


class CourseAndDisplayTests(Base):
    def test_course_page_all_roles(self):
        for user in ("6799000001", "admin", "scheduler"):
            self.c = app.test_client()
            self.login(user)
            html = self.c.get("/courses/310-3419").get_data(as_text=True)
            self.assertIn("310-3419", html)
            self.assertIn("กลุ่มเรียนในภาคปัจจุบัน", html)
        self.assertEqual(self.c.get("/courses/NOPE").status_code, 404)

    def test_course_page_shows_prerequisite_status(self):
        self.login("6799000001")
        html = self.c.get("/courses/310-3416").get_data(as_text=True)
        self.assertIn("310-2101", html)

    def test_thai_dates(self):
        self.assertEqual(core.thai_datetime("2027-01-15 23:59"), "15 ม.ค. 2570 23:59 น.")
        self.assertEqual(core.thai_date("2027-03-01 09:00-12:00"), "1 มี.ค. 2570 09:00-12:00")
        self.assertEqual(core.thai_date(None), "")

    def test_student_list_shows_teacher_and_credit_pattern(self):
        self.login("6799000001")
        html = self.c.get("/me/").get_data(as_text=True)
        self.assertIn("3(3-0-6)", html)
        self.assertIn('data-filter-select', html)


if __name__ == "__main__":
    unittest.main()

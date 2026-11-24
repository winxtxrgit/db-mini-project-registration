"""Automated Test Suite สำหรับตรวจสอบ Database Triggers & Business Rules (D1 - D19)
รันเดี่ยวๆ: python -m unittest discover -s tests -v
"""
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent


class TriggerBusinessRulesTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.NamedTemporaryFile(suffix=".db", delete=False)
        self.db_path = Path(self.tmp.name)
        self.con = sqlite3.connect(self.db_path)
        self.con.execute("PRAGMA foreign_keys = ON")

        schema = (ROOT / "schema.sql").read_text(encoding="utf-8")
        seed = (ROOT / "seed.sql").read_text(encoding="utf-8")
        self.con.executescript(schema)
        self.con.executescript(seed)
        self.con.commit()

    def tearDown(self):
        self.con.close()
        try:
            self.tmp.close()
        except Exception:
            pass
        if self.db_path.exists():
            try:
                self.db_path.unlink()
            except Exception:
                pass

    def set_actor(self, username: str):
        with self.con:
            self.con.execute("DELETE FROM app_session")
            uid = self.con.execute("SELECT user_id FROM app_user WHERE username = ?", (username,)).fetchone()[0]
            self.con.execute("INSERT INTO app_session (id, user_id) VALUES (1, ?)", (uid,))

    def clear_actor(self):
        with self.con:
            self.con.execute("DELETE FROM app_session")

    # D1 & D2: Class time clash
    def test_d1_class_time_clash(self):
        """D1: ลง 310-3419 (พ. 09:00-12:00) ชนกับ 310-2205 (วิชาค้าง) ต้องล้มเหลวด้วย Trigger"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('6799000001', 10)")
        self.assertIn("เวลาเรียนชน", str(ctx.exception))

    def test_d2_second_class_time_clash(self):
        """D2: ลง 312-3302 (จ. 09:00-12:00) ชนกับ 310-3313 ต้องล้มเหลว"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('6799000001', 6)")
        self.assertIn("เวลาเรียนชน", str(ctx.exception))

    # D3 & D4: Exam clash and Exam multi-test same day warning
    def test_d3_exam_time_clash(self):
        """D3: เวลาสอบชน: เปิดกลุ่ม 02 ที่มีสอบตรงกับวิชาที่ลงไว้แล้ว ต้องล้มเหลว"""
        with self.con:
            self.con.execute("INSERT INTO section (section_id, course_code, term_id, section_no, capacity) VALUES (11, '310-3313', '2569-2', '02', 10)")
            self.con.execute("INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) VALUES (11, 5, '13:00', '16:00', '15303')")
            self.con.execute("INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time) VALUES (11, 'FINAL', '2027-03-09', '09:00', '12:00')")

        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('6799000003', 11)")
        self.assertIn("เวลาสอบชน", str(ctx.exception))

    def test_d4_multiple_exams_same_day_allowed_if_no_overlap(self):
        """D4: สอบหลายวิชาวันเดียวกัน แต่คนละช่วงเวลา ต้องลงได้"""
        with self.con:
            self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 6)")
        count = self.con.execute("SELECT COUNT(*) FROM enrollment WHERE student_id = '6799000005' AND section_id = 6").fetchone()[0]
        self.assertEqual(count, 1)

    # D5: Curriculum Quota
    def test_d5_curriculum_quota_exceeded(self):
        """D5: โควตาหลักสูตรเต็ม แม้ที่นั่งห้องรวมยังเหลือ ต้องไม่อนุญาตให้ลง"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('B6907', 9)")
        self.assertIn("โควตา", str(ctx.exception))

    # D6: Missing Prerequisite
    def test_d6_missing_prerequisite(self):
        """D6: ลงวิชาที่ยังไม่ผ่านวิชาบังคับก่อน ต้องล้มเหลว"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('F0300', 5)")
        self.assertIn("ยังไม่ผ่านวิชาบังคับก่อน", str(ctx.exception))

    # D7 & D8 & D9 & D10: Waitlist rules and promotion
    def test_d8_waitlist_priority_backlog_over_regular(self):
        """D8: นักศึกษาที่มีวิชาค้างได้ priority สูงกว่านักศึกษาปกติในคิวสำรอง"""
        with self.con:
            # เติมที่นั่งกลุ่ม 1 ให้เต็ม
            self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('F0287', 1), ('F0288', 1), ('F0289', 1)")
            # สร้างนักศึกษาที่มีวิชาค้าง (เกรด F)
            self.con.execute("INSERT INTO student VALUES ('6799000006', 'เอฟ', 'สมมุติ', 'CPE63', 2566)")
            self.con.execute("INSERT INTO transcript VALUES ('6799000006', '310-2205', '2568-2', 'F')")
            # เข้าคิว
            self.con.execute("INSERT INTO waitlist (student_id, section_id, requested_at) VALUES ('F0290', 1, '2026-11-09 08:00:00')")
            self.con.execute("INSERT INTO waitlist (student_id, section_id, requested_at) VALUES ('6799000006', 1, '2026-11-09 10:00:00')")

        rows = self.con.execute("SELECT student_id, priority FROM v_waitlist_rank WHERE section_id = 1 ORDER BY priority, requested_at").fetchall()
        # priority น้อยกว่าคือได้ก่อน (priority 1 = วิชาค้าง, priority 3 = ปกติ)
        self.assertEqual(rows[0][0], "6799000006")
        self.assertLess(rows[0][1], rows[1][1])

    def test_d9_waitlist_when_seat_available_fails(self):
        """D9: เข้าคิว section ที่ยังมีที่นั่งว่าง ต้องไม่อนุญาต"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO waitlist (student_id, section_id) VALUES ('F0291', 2)")
        self.assertIn("ยังมีที่นั่ง", str(ctx.exception))

    def test_d10_auto_promote_on_drop(self):
        """D10: เมื่อมีคนถอน ระบบเลื่อนคนแรกในคิวขึ้นมาเป็น enrollment อัตโนมัติและบันทึก log"""
        with self.con:
            self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('F0287', 1), ('F0288', 1), ('F0289', 1)")
            self.con.execute("INSERT INTO waitlist (student_id, section_id, requested_at) VALUES ('F0290', 1, '2026-11-09 08:00:00')")
            # ถอน
            self.con.execute("DELETE FROM enrollment WHERE student_id = 'F0001' AND section_id = 1")

        enrolled = self.con.execute("SELECT COUNT(*) FROM enrollment WHERE student_id = 'F0290' AND section_id = 1").fetchone()[0]
        self.assertEqual(enrolled, 1)

        log = self.con.execute("SELECT action FROM registration_log WHERE student_id = 'F0290' AND section_id = 1 ORDER BY log_id DESC LIMIT 1").fetchone()[0]
        self.assertEqual(log, "PROMOTE")

    # D11: Registration Window RBAC
    def test_d11_window_closed_blocks_student_allows_admin(self):
        """D11: ช่วงลงทะเบียนปิด นักศึกษาถอนไม่ได้ แต่ Admin ถอนแทนได้"""
        with self.con:
            self.con.execute("UPDATE term SET reg_close_at = '2026-11-01 00:00' WHERE term_id = '2569-2'")

        # นักศึกษาทำรายการ -> ล้มเหลว
        self.set_actor("6799000005")
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("DELETE FROM enrollment WHERE student_id = '6799000005' AND section_id = 2")
        self.assertIn("ไม่อยู่ในช่วงลงทะเบียน", str(ctx.exception))

        # Admin ทำรายการ -> สำเร็จ
        self.set_actor("admin")
        with self.con:
            self.con.execute("DELETE FROM enrollment WHERE student_id = '6799000005' AND section_id = 2")
        self.clear_actor()

        rem = self.con.execute("SELECT COUNT(*) FROM enrollment WHERE student_id = '6799000005' AND section_id = 2").fetchone()[0]
        self.assertEqual(rem, 0)

    # D12: Maximum credits limit
    def test_d12_max_credits_limit(self):
        """D12: หน่วยกิตรวมเกินเพดาน term.max_credits ต้องไม่อนุญาต"""
        with self.con:
            self.con.execute("UPDATE term SET max_credits = 8 WHERE term_id = '2569-2'")
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 4)")
        self.assertIn("หน่วยกิตรวมเกินเพดาน", str(ctx.exception))

    # D13: Room clash
    def test_d13_room_clash(self):
        """D13: จัดห้องเรียนชนกับกลุ่มอื่นในวันเวลาเดียวกัน ต้องไม่อนุญาต"""
        self.set_actor("scheduler")
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) VALUES (2, 3, '09:00', '10:00', '15208')")
        self.clear_actor()
        self.assertIn("ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว", str(ctx.exception))

    # D14: Instructor clash
    def test_d14_instructor_clash(self):
        """D14: มอบหมายอาจารย์สอน 2 กลุ่มในเวลาชนกัน ต้องไม่อนุญาต"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("INSERT INTO section_instructor VALUES (10, 1)")
        self.assertIn("อาจารย์ท่านนี้มีคาบสอนวิชาอื่นในเวลาเดียวกับกลุ่มเรียนนี้", str(ctx.exception))

    # D15: Rescheduling meeting clashes enrolled students
    def test_d15_reschedule_meeting_clashes_students(self):
        """D15: ย้ายคาบไปชนกับวิชาที่นักศึกษาลงทะเบียนไว้แล้ว ต้องไม่อนุญาต"""
        self.set_actor("scheduler")
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("UPDATE class_meeting SET day_of_week = 2, start_time = '13:00', end_time = '16:00' WHERE section_id = 6")
        self.clear_actor()
        self.assertIn("มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้", str(ctx.exception))

    # D16: Exam room capacity check
    def test_d16_exam_room_capacity(self):
        """D16: กำหนดห้องสอบที่ความจุน้อยกว่าจำนวนนักศึกษาที่ลงทะเบียน ต้องไม่อนุญาต"""
        self.set_actor("scheduler")
        with self.con:
            self.con.execute("INSERT INTO room (room_code, capacity) VALUES ('R-SMALL', 10)")
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("UPDATE exam SET room_code = 'R-SMALL' WHERE section_id = 10")
        self.clear_actor()
        self.assertIn("ห้องสอบจุไม่พอ", str(ctx.exception))

    # D17: Section capacity decrease below enrolled count
    def test_d17_capacity_below_enrolled(self):
        """D17: ลดจำนวนรับต่ำกว่าจำนวนคนที่ลงทะเบียนไว้แล้ว ต้องไม่อนุญาต"""
        with self.assertRaises(sqlite3.IntegrityError) as ctx:
            with self.con:
                self.con.execute("UPDATE section SET capacity = 10 WHERE section_id = 10")
        self.assertIn("จำนวนรับต้องไม่น้อยกว่าจำนวนที่ลงทะเบียนแล้ว", str(ctx.exception))

    # D18: Ineligible waitlist candidate is skipped
    def test_d18_ineligible_waitlist_skipped(self):
        """D18: คนในคิวที่ไม่มีสิทธิ์ลง (หน่วยกิตจะเกิน) จะถูกข้าม และเลื่อนคนที่ eligible คนถัดไปแทน"""
        with self.con:
            # เติม section 1 ให้เต็ม 50/50 ก่อนเข้าคิว
            self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('F0287', 1), ('F0288', 1), ('F0289', 1)")
            self.con.execute("INSERT INTO enrollment (student_id, section_id) VALUES ('F0290', 10), ('F0290', 8)")
            self.con.execute("INSERT INTO waitlist (student_id, section_id) VALUES ('F0290', 1), ('F0291', 1)")
            self.con.execute("UPDATE term SET max_credits = 6 WHERE term_id = '2569-2'")
            # ถอน F0002 ออกจากกลุ่ม 1 -> F0290 จะเกิน 6 หน่วยกิต -> ข้ามไปเลื่อน F0291
            self.con.execute("DELETE FROM enrollment WHERE student_id = 'F0002' AND section_id = 1")

        f0290_enrolled = self.con.execute("SELECT COUNT(*) FROM enrollment WHERE student_id = 'F0290' AND section_id = 1").fetchone()[0]
        f0291_enrolled = self.con.execute("SELECT COUNT(*) FROM enrollment WHERE student_id = 'F0291' AND section_id = 1").fetchone()[0]
        self.assertEqual(f0290_enrolled, 0)
        self.assertEqual(f0291_enrolled, 1)


if __name__ == "__main__":
    unittest.main()

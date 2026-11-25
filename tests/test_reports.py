"""Automated Test Suite สำหรับรายงานจัดตาราง R11 - R16
รันเดี่ยวๆ: python -m unittest discover -s tests -v
"""
import sqlite3
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "web"))

import reports as R  # noqa: E402


class SchedulerReportsTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.con = sqlite3.connect(":memory:")
        cls.con.row_factory = sqlite3.Row
        cls.con.execute("PRAGMA foreign_keys = ON")
        cls.con.executescript((ROOT / "schema.sql").read_text(encoding="utf-8"))
        cls.con.executescript((ROOT / "seed.sql").read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        cls.con.close()

    def test_r11_schedule_progress(self):
        """R11: เรียงตามลำดับการจัด วิชาส่วนกลางที่ล็อกแล้วอยู่บนสุด และชั่วโมงตามหน่วยกิตถูกต้อง"""
        rows = self.con.execute(R.R11_SCHEDULE_PROGRESS).fetchall()
        self.assertEqual(len(rows), 10)
        self.assertEqual([r["priority"] for r in rows], sorted(r["priority"] for r in rows))
        first = rows[0]
        self.assertEqual((first["course_code"], first["course_category"], first["is_locked"], first["locked_by"]),
                         ("910-1116", "service", 1, "scheduler"))
        cloud = next(r for r in rows if r["course_code"] == "310-2311")   # 3(3-0-6) วาง 3 คาบ คาบละ 1 ชม.
        self.assertEqual((cloud["hours_placed"], cloud["hours_required"], cloud["progress"]), (3.0, 3, "ครบ"))
        self.assertTrue(all(r["is_locked"] == 0 for r in rows[1:]))

    def test_r11_progress_short_and_unplaced(self):
        """R11: กลุ่มที่วางไม่ครบขึ้น "ขาด" และกลุ่มที่ยังไม่มีคาบขึ้น "ยังไม่วางคาบ" (ใช้ฐานข้อมูลแยก)"""
        con = sqlite3.connect(":memory:")
        con.row_factory = sqlite3.Row
        con.executescript((ROOT / "schema.sql").read_text(encoding="utf-8"))
        con.executescript((ROOT / "seed.sql").read_text(encoding="utf-8"))
        with con:
            con.execute("UPDATE class_meeting SET end_time = '11:00' WHERE section_id = 1")
            con.execute("INSERT INTO section (section_id, course_code, term_id, section_no, capacity) "
                        "VALUES (11, '310-3313', '2569-2', '02', 10)")
        rows = {(r["course_code"], r["section_no"]): r for r in con.execute(R.R11_SCHEDULE_PROGRESS)}
        con.close()
        self.assertEqual(rows[("310-2205", "01")]["progress"], "ขาด 1 ชม.")
        self.assertEqual(rows[("310-3313", "02")]["progress"], "ยังไม่วางคาบ")
        self.assertEqual(rows[("310-3313", "02")]["priority"], 50)   # ไม่มีแถวใน scheduling_priority = 50

    def test_r12_schedule_overview_and_filter(self):
        """R12: ตารางเรียนข้ามชั้นปีของ CPE63 และกรองเฉพาะชั้นปี"""
        rows = self.con.execute(R.R12_SCHEDULE_OVERVIEW, {"curriculum_id": "CPE63"}).fetchall()
        self.assertTrue(len(rows) > 0)
        wed_morning = [r for r in rows if r["day_of_week"] == 3 and r["time"] == "09:00-12:00"]
        self.assertEqual(len(wed_morning), 1)
        self.assertIn("310-2205", wed_morning[0]["year_2"])
        self.assertIn("310-3419", wed_morning[0]["year_3"])

        filtered = self.con.execute(
            R.R12_SCHEDULE_OVERVIEW_FILTERED, {"curriculum_id": "CPE63", "year_level": 3}
        ).fetchall()
        self.assertTrue(len(filtered) > 0)
        self.assertTrue(all(r["year_level"] == 3 for r in filtered))

    def test_r14_retake_and_cohort_conflicts(self):
        """R14: เจอกรณีจริง 310-2205 (ปี 2) ชนกับ 310-3419 (บังคับปี 3) วันพุธ 09:00-12:00"""
        retake = self.con.execute(R.R14_RETAKE_CONFLICT, {"curriculum_id": "CPE63"}).fetchall()
        match = [
            r for r in retake
            if r["retake_course"] == "310-2205"
            and r["required_course"] == "310-3419"
            and r["day_of_week"] == 3
        ]
        self.assertEqual(len(match), 1)
        self.assertEqual(match[0]["retake_time"], "09:00-12:00")
        self.assertEqual(match[0]["required_time"], "09:00-12:00")
        self.assertEqual(match[0]["retake_year"], 2)
        self.assertEqual(match[0]["senior_year"], 3)

        cohort = self.con.execute(R.R14_COHORT_CONFLICT, {"curriculum_id": "CPE63"}).fetchall()
        self.assertEqual(len(cohort), 0)

    def test_r13_exam_rooms_availability_and_null_capacity(self):
        """R13: ห้องสอบที่ว่างและจุพอ เรียงจากพอดีที่สุด และแสดง 'ไม่ทราบความจุ' เมื่อ capacity เป็น NULL"""
        sec_id = self.con.execute(
            "SELECT s.section_id FROM section s JOIN term t ON t.term_id = s.term_id "
            "WHERE t.is_current = 1 AND s.course_code = '310-2205' LIMIT 1"
        ).fetchone()[0]
        rows = self.con.execute(
            R.R13_EXAM_ROOMS,
            {"section_id": sec_id, "exam_date": "2027-03-01", "start_time": "09:00", "end_time": "12:00"},
        ).fetchall()
        self.assertTrue(len(rows) > 0)
        # ห้องที่ capacity เป็น NULL ต้องแสดงคำว่า ไม่ทราบความจุ
        null_cap = [r for r in rows if r["capacity"] is None]
        if null_cap:
            self.assertTrue(any("ไม่ทราบความจุ" in r["result"] or "ไม่ว่าง" in r["result"] for r in null_cap))
        # ห้องที่ใช้ได้และรู้ความจุต้องมาก่อนห้องที่ไม่ว่าง/จุไม่พอ
        usable_known = [r for r in rows if r["usable"] and r["capacity"] is not None]
        caps = [r["capacity"] for r in usable_known]
        self.assertEqual(caps, sorted(caps))

    def test_r15_free_rooms(self):
        """R15: ค้นหาห้องเรียนว่างตามวัน เวลา และจำนวนคน"""
        # วันพุธ 09:00-12:00 ห้อง 15208 ถูกใช้อยู่ (310-2205) จึงต้องไม่ติดในรายการห้องว่าง
        rows = self.con.execute(
            R.R15_FREE_ROOMS,
            {"day_of_week": 3, "start_time": "09:00", "end_time": "12:00", "min_capacity": 0},
        ).fetchall()
        room_codes = {r["room_code"] for r in rows}
        self.assertNotIn("15208", room_codes)

        # วันศุกร์ 09:00-12:00
        fri = self.con.execute(
            R.R15_FREE_ROOMS,
            {"day_of_week": 5, "start_time": "09:00", "end_time": "12:00", "min_capacity": 47},
        ).fetchall()
        self.assertTrue(all(r["capacity"] is None or r["capacity"] >= 47 for r in fri))
        self.assertTrue(all(r["capacity_label"] == "ไม่ทราบความจุ" for r in fri if r["capacity"] is None))

    def test_r16_exam_same_day_real_cases(self):
        """R16: เจอกรณีจริงสอบหลายวิชาวันเดียวกัน 04/03/70 (2027-03-04) และ 09/03/70 (2027-03-09)"""
        rows = self.con.execute(R.R16_EXAM_SAME_DAY).fetchall()
        pairs = {(r["exam_date"], frozenset([r["course_1"], r["course_2"]])): r["students"] for r in rows}
        self.assertIn(("2027-03-04", frozenset(["310-2311", "910-1116"])), pairs)
        self.assertIn(("2027-03-09", frozenset(["310-2309", "312-3302"])), pairs)
        self.assertGreater(pairs[("2027-03-04", frozenset(["310-2311", "910-1116"]))], 0)
        self.assertGreater(pairs[("2027-03-09", frozenset(["310-2309", "312-3302"]))], 0)


if __name__ == "__main__":
    unittest.main()

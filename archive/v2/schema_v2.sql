-- =====================================================================
-- Mini Project Plan A (ส่วนขยาย v2): สนับสนุนฝ่ายจัดตารางเรียนและจัดสอบ
-- รันต่อจาก schema.sql + seed.sql (ดู run_v2.sql)
-- เพิ่ม 2 ตาราง, 8 view, 8 trigger และคอลัมน์ใหม่ใน room, course
-- รวมทั้งระบบ = 20 ตาราง, 16 view, 13 trigger
--
-- 4 ฟีเจอร์ตาม HANDOFF.md
--   1) เวลาว่างของอาจารย์          instructor_availability, v_instructor_busy
--   2) ห้องเรียน/ห้องสอบไม่ซ้ำ      trigger บน class_meeting และ exam, v_room_usage
--   3) ภาพรวมตารางข้ามชั้นปี         v_schedule_overview, v_cohort_conflict, v_retake_conflict
--   4) ตารางสอบไม่ชน                trigger บน exam, v_student_exam_clash, v_exam_schedule_full
-- ขั้นตอนจัดตาราง: ล็อกวิชาส่วนกลางก่อน แล้วจึงวางวิชาสาขา (scheduling_priority)
-- =====================================================================

PRAGMA foreign_keys = ON;

------------------------------------------------------------------
-- 1) คอลัมน์ใหม่ของ room และ course
------------------------------------------------------------------
ALTER TABLE room ADD COLUMN room_name TEXT;
ALTER TABLE room ADD COLUMN building  TEXT;
ALTER TABLE room ADD COLUMN floor_no  INTEGER;
ALTER TABLE room ADD COLUMN room_type TEXT NOT NULL DEFAULT 'lecture'
    CHECK (room_type IN ('lecture', 'lab', 'computer', 'exam_hall', 'multipurpose'));
ALTER TABLE room ADD COLUMN is_exam_room INTEGER NOT NULL DEFAULT 0 CHECK (is_exam_room IN (0, 1));

-- service = วิชาส่วนกลางที่เรียนร่วมหลายสาขา (ต้องจัดและล็อกก่อน), core = วิชาบังคับสาขา, elective = วิชาเลือก
ALTER TABLE course ADD COLUMN course_category TEXT NOT NULL DEFAULT 'regular'
    CHECK (course_category IN ('service', 'core', 'elective', 'regular'));

------------------------------------------------------------------
-- 2) เวลาว่าง/ไม่ว่างที่อาจารย์ส่งก่อนเปิดภาค
------------------------------------------------------------------
CREATE TABLE instructor_availability (
  avail_id      INTEGER PRIMARY KEY,
  instructor_id INTEGER NOT NULL REFERENCES instructor(instructor_id),
  term_id       TEXT    NOT NULL REFERENCES term(term_id),
  day_of_week   INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),   -- 1 = จันทร์ ... 7 = อาทิตย์
  start_time    TEXT    NOT NULL CHECK (start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  end_time      TEXT    NOT NULL CHECK (end_time   GLOB '[0-2][0-9]:[0-5][0-9]'),
  status        TEXT    NOT NULL DEFAULT 'available'
                CHECK (status IN ('available', 'preferred', 'unavailable', 'locked')),
                -- preferred = อยากสอนช่วงนี้, unavailable = ไม่ว่าง, locked = ฝ่ายจัดตารางกันเวลาไว้
  note          TEXT,
  submitted_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M', 'now', 'localtime')),
  UNIQUE (instructor_id, term_id, day_of_week, start_time, end_time),
  CHECK (start_time < end_time)
);

------------------------------------------------------------------
-- 3) ลำดับการจัดและการล็อกตาราง
--    ไม่เก็บ term_id ซ้ำ เพราะ section ระบุภาคเรียนอยู่แล้ว (3NF)
------------------------------------------------------------------
CREATE TABLE scheduling_priority (
  section_id  INTEGER PRIMARY KEY REFERENCES section(section_id) ON DELETE CASCADE,
  priority    INTEGER NOT NULL DEFAULT 50 CHECK (priority BETWEEN 1 AND 99),
              -- 1-10 = วิชาส่วนกลาง, 11-30 = วิชาบังคับสาขา, 31-99 = วิชาเลือก/อื่นๆ
  is_locked   INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1)),
  lock_reason TEXT,
  locked_by   TEXT,
  locked_at   TEXT
);

------------------------------------------------------------------
-- 4) VIEW
------------------------------------------------------------------

-- ช่วงเวลาที่อาจารย์ไม่ว่าง: มีคาบสอนแล้ว หรือแจ้งว่าไม่ว่าง
CREATE VIEW v_instructor_busy AS
SELECT s.term_id, si.instructor_id, i.full_name,
       cm.day_of_week, cm.start_time, cm.end_time,
       'teaching' AS busy_type, s.section_id, s.course_code, s.section_no, NULL AS note
FROM section_instructor si
JOIN class_meeting cm ON cm.section_id = si.section_id
JOIN section s        ON s.section_id = si.section_id
JOIN instructor i     ON i.instructor_id = si.instructor_id
UNION ALL
SELECT ia.term_id, ia.instructor_id, i.full_name,
       ia.day_of_week, ia.start_time, ia.end_time,
       ia.status, NULL, NULL, NULL, ia.note
FROM instructor_availability ia
JOIN instructor i ON i.instructor_id = ia.instructor_id
WHERE ia.status IN ('unavailable', 'locked');

-- การใช้ห้องเรียนรายคาบ (ใช้หาห้องว่าง)
CREATE VIEW v_room_usage AS
SELECT s.term_id, cm.room_code, cm.day_of_week, cm.start_time, cm.end_time,
       s.section_id, s.course_code, s.section_no
FROM class_meeting cm
JOIN section s ON s.section_id = cm.section_id
WHERE cm.room_code IS NOT NULL;

-- section ของแต่ละวิชาอยู่ในแผนของหลักสูตรใด ชั้นปีใด (วิชานอกแผนได้ค่า NULL)
CREATE VIEW v_section_plan AS
SELECT s.section_id, s.course_code, s.term_id, sp.curriculum_id, sp.year_level,
       sp.semester AS plan_semester, sp.is_required
FROM section s
LEFT JOIN study_plan sp ON sp.course_code = s.course_code;

-- ภาพรวมตารางเรียนของภาคปัจจุบัน หนึ่งแถวต่อคาบต่อ (หลักสูตร, ชั้นปี) ใช้ทำตารางข้ามชั้นปี
CREATE VIEW v_schedule_overview AS
SELECT cm.day_of_week, cm.start_time, cm.end_time,
       s.section_id, s.course_code, c.name_th AS course_name, c.course_category, s.section_no,
       cm.room_code,
       (SELECT group_concat(i.full_name, ', ')
          FROM section_instructor si JOIN instructor i ON i.instructor_id = si.instructor_id
         WHERE si.section_id = s.section_id)                                       AS instructor_name,
       pl.curriculum_id, pl.year_level, pl.plan_semester, pl.is_required,
       (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id)       AS enrolled_count,
       s.capacity,
       COALESCE((SELECT p.is_locked FROM scheduling_priority p WHERE p.section_id = s.section_id), 0) AS is_locked
FROM class_meeting cm
JOIN section s         ON s.section_id = cm.section_id
JOIN course c          ON c.course_code = s.course_code
JOIN term t            ON t.term_id = s.term_id AND t.is_current = 1
LEFT JOIN v_section_plan pl ON pl.section_id = s.section_id;

-- วิชาบังคับของชั้นปีเดียวกัน ภาคเดียวกัน ที่เวลาเรียนทับกัน (นักศึกษาเรียนตามแผนไม่ได้)
CREATE VIEW v_cohort_conflict AS
SELECT a.curriculum_id, a.year_level, a.day_of_week,
       a.course_code AS course_a, a.start_time || '-' || a.end_time AS time_a,
       b.course_code AS course_b, b.start_time || '-' || b.end_time AS time_b
FROM v_schedule_overview a
JOIN v_schedule_overview b
  ON b.curriculum_id = a.curriculum_id AND b.year_level = a.year_level
 AND b.plan_semester = a.plan_semester AND b.day_of_week = a.day_of_week
 AND a.course_code < b.course_code
 AND a.start_time < b.end_time AND b.start_time < a.end_time
JOIN term t ON t.is_current = 1 AND t.semester = a.plan_semester
WHERE a.is_required = 1 AND b.is_required = 1;

-- วิชาของชั้นปีต่ำกว่า (ที่รุ่นพี่อาจต้องลงเรียนซ้ำ) ซึ่งเวลาทับกับวิชาบังคับตามแผนของรุ่นพี่
-- affected_students = นักศึกษาชั้นปีของรุ่นพี่ที่ยังไม่ผ่านวิชานั้น
CREATE VIEW v_retake_conflict AS
SELECT lo.curriculum_id, lo.day_of_week,
       lo.course_code AS retake_course, lo.year_level AS retake_year,
       lo.start_time || '-' || lo.end_time AS retake_time,
       hi.course_code AS required_course, hi.year_level AS senior_year,
       hi.start_time || '-' || hi.end_time AS required_time,
       (SELECT COUNT(*) FROM v_student_level lv
         WHERE lv.curriculum_id = lo.curriculum_id AND lv.year_level = hi.year_level
           AND NOT EXISTS (SELECT 1 FROM v_passed p
                            WHERE p.student_id = lv.student_id AND p.course_code = lo.course_code)) AS affected_students
FROM v_schedule_overview lo
JOIN v_schedule_overview hi
  ON hi.curriculum_id = lo.curriculum_id AND hi.year_level > lo.year_level
 AND hi.day_of_week = lo.day_of_week
 AND lo.start_time < hi.end_time AND hi.start_time < lo.end_time
JOIN term t ON t.is_current = 1 AND t.semester = hi.plan_semester
WHERE hi.is_required = 1;

-- ตารางสอบของภาคปัจจุบัน พร้อมห้อง ความจุ และจำนวนผู้เข้าสอบ
CREATE VIEW v_exam_schedule_full AS
SELECT ex.exam_id, ex.exam_date, ex.start_time, ex.end_time, ex.exam_type,
       s.section_id, s.course_code, c.name_th AS course_name, s.section_no,
       ex.room_code, r.capacity AS room_capacity,
       (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id) AS student_count,
       (SELECT group_concat(i.full_name, ', ')
          FROM section_instructor si JOIN instructor i ON i.instructor_id = si.instructor_id
         WHERE si.section_id = s.section_id)                                 AS instructor_name
FROM exam ex
JOIN section s   ON s.section_id = ex.section_id
JOIN course c    ON c.course_code = s.course_code
JOIN term t      ON t.term_id = s.term_id AND t.is_current = 1
LEFT JOIN room r ON r.room_code = ex.room_code;

-- นักศึกษาที่สอบมากกว่า 1 วิชาในวันเดียวกัน: CLASH = เวลาทับกัน (ห้ามเกิด), SAME_DAY = วันเดียวกันแต่ไม่ทับ (เตือน)
CREATE VIEW v_student_exam_clash AS
SELECT e1.student_id, x1.exam_date,
       s1.course_code AS course_1, x1.start_time || '-' || x1.end_time AS time_1,
       s2.course_code AS course_2, x2.start_time || '-' || x2.end_time AS time_2,
       CASE WHEN x1.start_time < x2.end_time AND x2.start_time < x1.end_time
            THEN 'CLASH' ELSE 'SAME_DAY' END AS severity
FROM enrollment e1
JOIN enrollment e2 ON e2.student_id = e1.student_id AND e1.section_id < e2.section_id
JOIN section s1    ON s1.section_id = e1.section_id
JOIN section s2    ON s2.section_id = e2.section_id AND s2.term_id = s1.term_id
JOIN term t        ON t.term_id = s1.term_id AND t.is_current = 1
JOIN exam x1       ON x1.section_id = e1.section_id
JOIN exam x2       ON x2.section_id = e2.section_id AND x2.exam_date = x1.exam_date;

------------------------------------------------------------------
-- 5) TRIGGER: การวางและย้ายคาบเรียน
--    ตรวจตามลำดับ: ล็อก -> ขั้นตอนจัดตาราง -> ห้อง -> อาจารย์ -> นักศึกษาที่ลงแล้ว
--    กลุ่มเรียนของ "วิชาเดียวกัน" ใช้ห้องและเวลาเดียวกันได้ (เรียนร่วม)
------------------------------------------------------------------
CREATE TRIGGER trg_meeting_v2_before_insert
BEFORE INSERT ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'วิชานี้ล็อกตารางแล้ว ต้องปลดล็อกก่อนจึงแก้คาบเรียนได้')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p WHERE p.section_id = NEW.section_id AND p.is_locked = 1);

  SELECT RAISE(ABORT, 'ต้องล็อกวิชาส่วนกลางของภาคเรียนนี้ให้ครบก่อน จึงวางวิชาอื่นได้')
  WHERE (SELECT c.course_category FROM section s JOIN course c ON c.course_code = s.course_code
          WHERE s.section_id = NEW.section_id) <> 'service'
    AND EXISTS (SELECT 1 FROM section ns
                JOIN section sv ON sv.term_id = ns.term_id
                JOIN course cv  ON cv.course_code = sv.course_code AND cv.course_category = 'service'
                WHERE ns.section_id = NEW.section_id
                  AND NOT EXISTS (SELECT 1 FROM scheduling_priority p
                                   WHERE p.section_id = sv.section_id AND p.is_locked = 1));

  SELECT RAISE(ABORT, 'ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM v_room_usage u
                JOIN section ns ON ns.section_id = NEW.section_id
                WHERE u.room_code = NEW.room_code AND u.term_id = ns.term_id
                  AND u.day_of_week = NEW.day_of_week
                  AND u.start_time < NEW.end_time AND NEW.start_time < u.end_time
                  AND u.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนมีคาบสอนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id
                  AND b.busy_type = 'teaching' AND b.course_code <> ns.course_code
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนแจ้งว่าไม่ว่างในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id
                  AND b.busy_type <> 'teaching'
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN section ns     ON ns.section_id = NEW.section_id
                JOIN enrollment oth ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN section os     ON os.section_id = oth.section_id AND os.term_id = ns.term_id
                JOIN class_meeting cm ON cm.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND cm.day_of_week = NEW.day_of_week
                  AND cm.start_time < NEW.end_time AND NEW.start_time < cm.end_time);
END;

CREATE TRIGGER trg_meeting_v2_before_update
BEFORE UPDATE OF section_id, day_of_week, start_time, end_time, room_code ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'วิชานี้ล็อกตารางแล้ว ต้องปลดล็อกก่อนจึงแก้คาบเรียนได้')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p
                WHERE p.section_id IN (OLD.section_id, NEW.section_id) AND p.is_locked = 1);

  SELECT RAISE(ABORT, 'ต้องล็อกวิชาส่วนกลางของภาคเรียนนี้ให้ครบก่อน จึงวางวิชาอื่นได้')
  WHERE (SELECT c.course_category FROM section s JOIN course c ON c.course_code = s.course_code
          WHERE s.section_id = NEW.section_id) <> 'service'
    AND EXISTS (SELECT 1 FROM section ns
                JOIN section sv ON sv.term_id = ns.term_id
                JOIN course cv  ON cv.course_code = sv.course_code AND cv.course_category = 'service'
                WHERE ns.section_id = NEW.section_id
                  AND NOT EXISTS (SELECT 1 FROM scheduling_priority p
                                   WHERE p.section_id = sv.section_id AND p.is_locked = 1));

  SELECT RAISE(ABORT, 'ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM class_meeting cm
                JOIN section os ON os.section_id = cm.section_id
                JOIN section ns ON ns.section_id = NEW.section_id
                WHERE cm.meeting_id <> NEW.meeting_id
                  AND cm.room_code = NEW.room_code AND os.term_id = ns.term_id
                  AND cm.day_of_week = NEW.day_of_week
                  AND cm.start_time < NEW.end_time AND NEW.start_time < cm.end_time
                  AND os.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนมีคาบสอนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id
                  AND b.busy_type = 'teaching' AND b.course_code <> ns.course_code
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนแจ้งว่าไม่ว่างในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id
                  AND b.busy_type <> 'teaching'
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN section ns     ON ns.section_id = NEW.section_id
                JOIN enrollment oth ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN section os     ON os.section_id = oth.section_id AND os.term_id = ns.term_id
                JOIN class_meeting cm ON cm.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND cm.day_of_week = NEW.day_of_week
                  AND cm.start_time < NEW.end_time AND NEW.start_time < cm.end_time);
END;

CREATE TRIGGER trg_meeting_v2_before_delete
BEFORE DELETE ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'วิชานี้ล็อกตารางแล้ว ต้องปลดล็อกก่อนจึงแก้คาบเรียนได้')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p WHERE p.section_id = OLD.section_id AND p.is_locked = 1);
END;

-- มอบหมายอาจารย์ให้กลุ่มเรียนที่วางคาบแล้ว: อาจารย์ต้องไม่ติดสอนและไม่ได้แจ้งว่าไม่ว่าง
CREATE TRIGGER trg_section_instructor_v2_before_insert
BEFORE INSERT ON section_instructor
BEGIN
  SELECT RAISE(ABORT, 'อาจารย์ท่านนี้มีคาบสอนวิชาอื่นในเวลาเดียวกับกลุ่มเรียนนี้')
  WHERE EXISTS (SELECT 1 FROM class_meeting cm
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = NEW.instructor_id AND b.term_id = ns.term_id
                WHERE cm.section_id = NEW.section_id
                  AND b.busy_type = 'teaching' AND b.course_code <> ns.course_code
                  AND b.day_of_week = cm.day_of_week
                  AND b.start_time < cm.end_time AND cm.start_time < b.end_time);

  SELECT RAISE(ABORT, 'อาจารย์ท่านนี้แจ้งว่าไม่ว่างในเวลาของกลุ่มเรียนนี้')
  WHERE EXISTS (SELECT 1 FROM class_meeting cm
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = NEW.instructor_id AND b.term_id = ns.term_id
                WHERE cm.section_id = NEW.section_id
                  AND b.busy_type <> 'teaching'
                  AND b.day_of_week = cm.day_of_week
                  AND b.start_time < cm.end_time AND cm.start_time < b.end_time);
END;

------------------------------------------------------------------
-- 6) TRIGGER: การจัดสอบ
--    ห้องสอบต้องไม่ซ้ำ ต้องเป็นห้องที่ใช้สอบได้ ต้องจุพอ และนักศึกษาต้องไม่สอบสองวิชาพร้อมกัน
------------------------------------------------------------------
CREATE TRIGGER trg_exam_v2_before_insert
BEFORE INSERT ON exam
BEGIN
  SELECT RAISE(ABORT, 'ห้องนี้ไม่ได้กำหนดให้ใช้เป็นห้องสอบ')
  WHERE NEW.room_code IS NOT NULL
    AND (SELECT is_exam_room FROM room WHERE room_code = NEW.room_code) = 0;

  SELECT RAISE(ABORT, 'ห้องสอบจุไม่พอสำหรับจำนวนนักศึกษาที่ลงทะเบียน')
  WHERE NEW.room_code IS NOT NULL
    AND (SELECT capacity FROM room WHERE room_code = NEW.room_code)
        < (SELECT COUNT(*) FROM enrollment WHERE section_id = NEW.section_id);

  SELECT RAISE(ABORT, 'ห้องสอบนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM exam ex
                JOIN section os ON os.section_id = ex.section_id
                JOIN section ns ON ns.section_id = NEW.section_id
                WHERE ex.room_code = NEW.room_code AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time
                  AND os.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ต้องสอบวิชาอื่นในเวลาเดียวกัน')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN enrollment oth ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN exam ex        ON ex.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time);
END;

CREATE TRIGGER trg_exam_v2_before_update
BEFORE UPDATE OF section_id, exam_date, start_time, end_time, room_code ON exam
BEGIN
  SELECT RAISE(ABORT, 'ห้องนี้ไม่ได้กำหนดให้ใช้เป็นห้องสอบ')
  WHERE NEW.room_code IS NOT NULL
    AND (SELECT is_exam_room FROM room WHERE room_code = NEW.room_code) = 0;

  SELECT RAISE(ABORT, 'ห้องสอบจุไม่พอสำหรับจำนวนนักศึกษาที่ลงทะเบียน')
  WHERE NEW.room_code IS NOT NULL
    AND (SELECT capacity FROM room WHERE room_code = NEW.room_code)
        < (SELECT COUNT(*) FROM enrollment WHERE section_id = NEW.section_id);

  SELECT RAISE(ABORT, 'ห้องสอบนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM exam ex
                JOIN section os ON os.section_id = ex.section_id
                JOIN section ns ON ns.section_id = NEW.section_id
                WHERE ex.exam_id <> NEW.exam_id
                  AND ex.room_code = NEW.room_code AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time
                  AND os.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ต้องสอบวิชาอื่นในเวลาเดียวกัน')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN enrollment oth ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN exam ex        ON ex.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND ex.exam_id <> NEW.exam_id
                  AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time);
END;

------------------------------------------------------------------
-- 7) TRIGGER: การล็อกตาราง (ล็อกได้เฉพาะกลุ่มเรียนที่วางคาบแล้ว)
------------------------------------------------------------------
CREATE TRIGGER trg_priority_v2_before_insert
BEFORE INSERT ON scheduling_priority
WHEN NEW.is_locked = 1
BEGIN
  SELECT RAISE(ABORT, 'ล็อกได้เฉพาะกลุ่มเรียนที่วางคาบเรียนแล้ว')
  WHERE NOT EXISTS (SELECT 1 FROM class_meeting WHERE section_id = NEW.section_id);
END;

CREATE TRIGGER trg_priority_v2_before_update
BEFORE UPDATE OF is_locked ON scheduling_priority
WHEN NEW.is_locked = 1 AND OLD.is_locked = 0
BEGIN
  SELECT RAISE(ABORT, 'ล็อกได้เฉพาะกลุ่มเรียนที่วางคาบเรียนแล้ว')
  WHERE NOT EXISTS (SELECT 1 FROM class_meeting WHERE section_id = NEW.section_id);
END;

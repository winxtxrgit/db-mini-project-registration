-- Mini Project: ระบบวางแผนและตรวจสอบการลงทะเบียนตามแผนการเรียน (Study Plan–Aware Registration System)
-- โครงสร้างตาราง + view + trigger (SQLite 3.25+)
-- รันทั้งชุดจากโฟลเดอร์ Mini_Project_PlanA: sqlite3 :memory: ".read run.sql"

PRAGMA foreign_keys = ON;

------------------------------------------------------------------
-- 1) หลักสูตรและนักศึกษา
------------------------------------------------------------------
-- ชื่อสาขาขึ้นกับรหัสสาขา ไม่ได้ขึ้นกับปีหลักสูตร จึงแยกเป็นตารางของตัวเอง (3NF)
CREATE TABLE program (
  program_code TEXT PRIMARY KEY,                 -- รหัสสาขา เช่น '6313301'
  program_name TEXT NOT NULL
);

CREATE TABLE curriculum (
  curriculum_id   TEXT PRIMARY KEY,              -- เช่น 'CPE63'
  program_code    TEXT NOT NULL REFERENCES program(program_code),
  curriculum_year INTEGER NOT NULL,              -- ปีหลักสูตร (พ.ศ.) เช่น 2563
  UNIQUE (program_code, curriculum_year)
);

CREATE TABLE student (
  student_id    TEXT PRIMARY KEY,
  first_name    TEXT NOT NULL,
  last_name     TEXT NOT NULL,
  curriculum_id TEXT NOT NULL REFERENCES curriculum(curriculum_id),
  entry_year    INTEGER NOT NULL                 -- ปีการศึกษาที่เข้า (พ.ศ.)
);

------------------------------------------------------------------
-- 2) รายวิชา วิชาบังคับก่อน และแผนการเรียน
------------------------------------------------------------------
CREATE TABLE course (
  course_code    TEXT PRIMARY KEY,               -- '310-2309'
  name_th        TEXT NOT NULL,
  name_en        TEXT,
  credits        INTEGER NOT NULL CHECK (credits >= 0),
  credit_pattern TEXT                            -- '3(3-0-6)' ใช้แสดงผลเท่านั้น
);

CREATE TABLE prerequisite (
  course_code TEXT NOT NULL REFERENCES course(course_code),
  prereq_code TEXT NOT NULL REFERENCES course(course_code),
  PRIMARY KEY (course_code, prereq_code),
  CHECK (course_code <> prereq_code)
);

-- วิชาหนึ่งอยู่ในแผนของหลักสูตรหนึ่งได้ครั้งเดียว
CREATE TABLE study_plan (
  curriculum_id TEXT    NOT NULL REFERENCES curriculum(curriculum_id),
  course_code   TEXT    NOT NULL REFERENCES course(course_code),
  year_level    INTEGER NOT NULL CHECK (year_level BETWEEN 1 AND 8),
  semester      INTEGER NOT NULL CHECK (semester IN (1, 2, 3)),
  is_required   INTEGER NOT NULL DEFAULT 1 CHECK (is_required IN (0, 1)),
  PRIMARY KEY (curriculum_id, course_code)
);

------------------------------------------------------------------
-- 3) ภาคการศึกษา ห้อง อาจารย์ section
------------------------------------------------------------------
CREATE TABLE term (
  term_id       TEXT PRIMARY KEY,                -- '2569-2'
  academic_year INTEGER NOT NULL,
  semester      INTEGER NOT NULL CHECK (semester IN (1, 2, 3)),
  is_current    INTEGER NOT NULL DEFAULT 0 CHECK (is_current IN (0, 1)),
  UNIQUE (academic_year, semester)
);
-- มีภาคปัจจุบันได้ภาคเดียว
CREATE UNIQUE INDEX ux_term_one_current ON term(is_current) WHERE is_current = 1;

CREATE TABLE instructor (
  instructor_id INTEGER PRIMARY KEY,
  full_name     TEXT NOT NULL UNIQUE
);

CREATE TABLE room (
  room_code TEXT PRIMARY KEY,
  capacity  INTEGER CHECK (capacity > 0)
);

CREATE TABLE section (
  section_id  INTEGER PRIMARY KEY,
  course_code TEXT    NOT NULL REFERENCES course(course_code),
  term_id     TEXT    NOT NULL REFERENCES term(term_id),
  section_no  TEXT    NOT NULL,
  capacity    INTEGER NOT NULL CHECK (capacity > 0),
  UNIQUE (course_code, term_id, section_no)
);

-- โควตาที่นั่งแยกตามหลักสูตร (ถ้า section ไม่มีแถวในตารางนี้ = ไม่จำกัดหลักสูตร)
CREATE TABLE section_quota (
  section_id    INTEGER NOT NULL REFERENCES section(section_id) ON DELETE CASCADE,
  curriculum_id TEXT    NOT NULL REFERENCES curriculum(curriculum_id),
  seats         INTEGER NOT NULL CHECK (seats >= 0),
  PRIMARY KEY (section_id, curriculum_id)
);

CREATE TABLE section_instructor (
  section_id    INTEGER NOT NULL REFERENCES section(section_id) ON DELETE CASCADE,
  instructor_id INTEGER NOT NULL REFERENCES instructor(instructor_id),
  PRIMARY KEY (section_id, instructor_id)
);

-- เวลาเรียน 1 section มีได้หลายช่วง (เช่น จ./อ./พฤ. 08:00-09:00)
CREATE TABLE class_meeting (
  meeting_id  INTEGER PRIMARY KEY,
  section_id  INTEGER NOT NULL REFERENCES section(section_id) ON DELETE CASCADE,
  day_of_week INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7),  -- 1=จันทร์ ... 7=อาทิตย์
  start_time  TEXT    NOT NULL CHECK (start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  end_time    TEXT    NOT NULL CHECK (end_time   GLOB '[0-2][0-9]:[0-5][0-9]'),
  room_code   TEXT    REFERENCES room(room_code),
  CHECK (start_time < end_time)
);

CREATE TABLE exam (
  exam_id    INTEGER PRIMARY KEY,
  section_id INTEGER NOT NULL REFERENCES section(section_id) ON DELETE CASCADE,
  exam_type  TEXT    NOT NULL CHECK (exam_type IN ('MIDTERM', 'FINAL')),
  exam_date  TEXT    NOT NULL CHECK (exam_date GLOB '[0-9][0-9][0-9][0-9]-[0-1][0-9]-[0-3][0-9]'), -- ค.ศ.
  start_time TEXT    NOT NULL,
  end_time   TEXT    NOT NULL,
  room_code  TEXT    REFERENCES room(room_code),   -- NULL = ยังไม่ระบุห้อง (N/A)
  UNIQUE (section_id, exam_type),
  CHECK (start_time < end_time)
);

------------------------------------------------------------------
-- 4) ผลการเรียน การลงทะเบียน คิวสำรอง และประวัติ
------------------------------------------------------------------
CREATE TABLE transcript (
  student_id  TEXT NOT NULL REFERENCES student(student_id),
  course_code TEXT NOT NULL REFERENCES course(course_code),
  term_id     TEXT NOT NULL REFERENCES term(term_id),
  grade       TEXT NOT NULL CHECK (grade IN ('A','B+','B','C+','C','D+','D','F','W','I','S','U')),
  PRIMARY KEY (student_id, course_code, term_id)
);

-- สถานะปัจจุบัน: มีแถว = ลงอยู่ / ถอน = DELETE (ประวัติเก็บใน registration_log)
CREATE TABLE enrollment (
  student_id  TEXT    NOT NULL REFERENCES student(student_id),
  section_id  INTEGER NOT NULL REFERENCES section(section_id),
  enrolled_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
  PRIMARY KEY (student_id, section_id)
);
CREATE INDEX ix_enrollment_section ON enrollment(section_id);

CREATE TABLE waitlist (
  student_id   TEXT    NOT NULL REFERENCES student(student_id),
  section_id   INTEGER NOT NULL REFERENCES section(section_id),
  requested_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now')),
  PRIMARY KEY (student_id, section_id)
);

CREATE TABLE registration_log (
  log_id     INTEGER PRIMARY KEY,
  student_id TEXT    NOT NULL REFERENCES student(student_id),
  section_id INTEGER NOT NULL REFERENCES section(section_id),
  action     TEXT    NOT NULL CHECK (action IN ('ADD', 'DROP', 'WAITLIST', 'PROMOTE')),
  logged_at  TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now'))
);

------------------------------------------------------------------
-- 5) VIEW
------------------------------------------------------------------
-- ชั้นปีและเทอมของนักศึกษาในภาคปัจจุบัน
CREATE VIEW v_student_level AS
SELECT s.student_id, s.curriculum_id, t.term_id, t.semester,
       t.academic_year - s.entry_year + 1 AS year_level
FROM student s CROSS JOIN term t
WHERE t.is_current = 1;

CREATE VIEW v_passed AS
SELECT DISTINCT student_id, course_code
FROM transcript
WHERE grade NOT IN ('F', 'W', 'I', 'U');

CREATE VIEW v_section_seat AS
SELECT sec.section_id, sec.course_code, sec.term_id, sec.section_no, sec.capacity,
       COUNT(e.student_id)                AS enrolled,
       sec.capacity - COUNT(e.student_id) AS available
FROM section sec LEFT JOIN enrollment e ON e.section_id = sec.section_id
GROUP BY sec.section_id;

CREATE VIEW v_quota_seat AS
SELECT q.section_id, q.curriculum_id, q.seats,
       COUNT(e.student_id)           AS used,
       q.seats - COUNT(e.student_id) AS quota_left
FROM section_quota q
LEFT JOIN student s    ON s.curriculum_id = q.curriculum_id
LEFT JOIN enrollment e ON e.section_id = q.section_id AND e.student_id = s.student_id
GROUP BY q.section_id, q.curriculum_id;

-- ที่นั่งที่ "นักศึกษาคนนี้" ลงได้จริงใน section นี้ (คิดทั้ง capacity และโควตาหลักสูตร)
CREATE VIEW v_seat_for_student AS
SELECT s.student_id, ss.section_id,
       CASE
         WHEN NOT EXISTS (SELECT 1 FROM section_quota q WHERE q.section_id = ss.section_id)
           THEN ss.available
         ELSE MIN(ss.available, COALESCE(
                (SELECT qs.quota_left FROM v_quota_seat qs
                  WHERE qs.section_id = ss.section_id AND qs.curriculum_id = s.curriculum_id), 0))
       END AS seats_left
FROM student s CROSS JOIN v_section_seat ss;

-- ช่วงเวลาที่ section ใช้ (เรียน = ผูกกับวัน, สอบ = ผูกกับวันที่)
CREATE VIEW v_section_slot AS
SELECT m.section_id, 'CLASS' AS kind, CAST(m.day_of_week AS TEXT) AS slot_key,
       m.start_time, m.end_time
FROM class_meeting m
UNION ALL
SELECT x.section_id, 'EXAM', x.exam_date, x.start_time, x.end_time
FROM exam x;

-- ช่วงเวลาที่นักศึกษาแต่ละคนมีอยู่แล้วจากวิชาที่ลง
CREATE VIEW v_student_slot AS
SELECT e.student_id, sec.term_id, sec.course_code, sl.*
FROM enrollment e
JOIN section sec       ON sec.section_id = e.section_id
JOIN v_section_slot sl ON sl.section_id = e.section_id;

-- คิวสำรองเรียงลำดับ: 1 = วิชาบังคับที่ค้างจากเทอมก่อน, 2 = วิชาบังคับตามแผนเทอมนี้, 3 = อื่นๆ
CREATE VIEW v_waitlist_rank AS
SELECT w.student_id, w.section_id, sec.course_code, w.requested_at,
       CASE
         WHEN sp.is_required = 1 AND (sp.year_level < lv.year_level
              OR (sp.year_level = lv.year_level AND sp.semester < lv.semester)) THEN 1
         WHEN sp.is_required = 1 AND sp.year_level = lv.year_level
              AND sp.semester = lv.semester                                   THEN 2
         ELSE 3
       END AS priority,
       NOT EXISTS (
         SELECT 1 FROM v_section_slot c
         JOIN v_student_slot m
           ON m.student_id = w.student_id AND m.term_id = sec.term_id
          AND m.kind = c.kind AND m.slot_key = c.slot_key
          AND m.start_time < c.end_time AND c.start_time < m.end_time
         WHERE c.section_id = w.section_id
       ) AS no_conflict,
       (SELECT sf.seats_left FROM v_seat_for_student sf
         WHERE sf.student_id = w.student_id AND sf.section_id = w.section_id) AS seats_left
FROM waitlist w
JOIN section sec         ON sec.section_id = w.section_id
JOIN v_student_level lv  ON lv.student_id = w.student_id
LEFT JOIN study_plan sp  ON sp.curriculum_id = lv.curriculum_id AND sp.course_code = sec.course_code;

------------------------------------------------------------------
-- 6) TRIGGER: กฎการลงทะเบียน (ตรวจตามลำดับ ข้อแรกที่ผิดจะหยุดทันที)
------------------------------------------------------------------
CREATE TRIGGER trg_enrollment_rules
BEFORE INSERT ON enrollment
BEGIN
  -- ลงวิชาเดียวกันซ้ำในเทอมเดียวกัน (คนละ section)
  SELECT RAISE(ABORT, 'ลงวิชานี้ไว้แล้วใน section อื่น')
  WHERE EXISTS (
    SELECT 1 FROM enrollment e
    JOIN section es ON es.section_id = e.section_id
    JOIN section ns ON ns.section_id = NEW.section_id
    WHERE e.student_id = NEW.student_id
      AND es.term_id = ns.term_id AND es.course_code = ns.course_code);

  -- สอบผ่านแล้ว
  SELECT RAISE(ABORT, 'สอบผ่านวิชานี้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM v_passed p JOIN section ns ON ns.course_code = p.course_code
    WHERE ns.section_id = NEW.section_id AND p.student_id = NEW.student_id);

  -- ยังไม่ผ่านวิชาบังคับก่อน
  SELECT RAISE(ABORT, 'ยังไม่ผ่านวิชาบังคับก่อน')
  WHERE EXISTS (
    SELECT 1 FROM prerequisite pr JOIN section ns ON ns.course_code = pr.course_code
    WHERE ns.section_id = NEW.section_id
      AND NOT EXISTS (SELECT 1 FROM v_passed p
                       WHERE p.student_id = NEW.student_id AND p.course_code = pr.prereq_code));

  -- เวลาเรียนชน
  SELECT RAISE(ABORT, 'เวลาเรียนชนกับวิชาที่ลงไว้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM v_section_slot c
    JOIN section ns ON ns.section_id = c.section_id
    JOIN v_student_slot m
      ON m.student_id = NEW.student_id AND m.term_id = ns.term_id
     AND m.kind = c.kind AND m.slot_key = c.slot_key
     AND m.start_time < c.end_time AND c.start_time < m.end_time
    WHERE c.section_id = NEW.section_id AND c.kind = 'CLASS');

  -- เวลาสอบชน
  SELECT RAISE(ABORT, 'เวลาสอบชนกับวิชาที่ลงไว้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM v_section_slot c
    JOIN section ns ON ns.section_id = c.section_id
    JOIN v_student_slot m
      ON m.student_id = NEW.student_id AND m.term_id = ns.term_id
     AND m.kind = c.kind AND m.slot_key = c.slot_key
     AND m.start_time < c.end_time AND c.start_time < m.end_time
    WHERE c.section_id = NEW.section_id AND c.kind = 'EXAM');

  -- ที่นั่งเต็ม
  SELECT RAISE(ABORT, 'section นี้ที่นั่งเต็มแล้ว')
  WHERE (SELECT available FROM v_section_seat WHERE section_id = NEW.section_id) <= 0;

  -- โควตาของหลักสูตรตัวเองเต็ม (แม้ section ยังมีที่ว่าง)
  SELECT RAISE(ABORT, 'โควตาสำหรับหลักสูตรของคุณเต็มแล้ว')
  WHERE (SELECT seats_left FROM v_seat_for_student
          WHERE student_id = NEW.student_id AND section_id = NEW.section_id) <= 0;
END;

-- หลังลงสำเร็จ: บันทึกประวัติ แล้วเอาออกจากคิวของวิชานั้นทุก section
CREATE TRIGGER trg_enrollment_after_add
AFTER INSERT ON enrollment
BEGIN
  INSERT INTO registration_log (student_id, section_id, action)
  VALUES (NEW.student_id, NEW.section_id,
          CASE WHEN EXISTS (SELECT 1 FROM waitlist
                             WHERE student_id = NEW.student_id AND section_id = NEW.section_id)
               THEN 'PROMOTE' ELSE 'ADD' END);

  DELETE FROM waitlist
  WHERE student_id = NEW.student_id
    AND section_id IN (SELECT s2.section_id FROM section s2
                       JOIN section ns ON ns.section_id = NEW.section_id
                       WHERE s2.course_code = ns.course_code AND s2.term_id = ns.term_id);
END;

-- ถอนวิชา: บันทึกประวัติ แล้วเลื่อนคนแรกในคิวที่ลงได้จริง (ไม่ชน + มีที่นั่งตามโควตา)
CREATE TRIGGER trg_enrollment_after_drop
AFTER DELETE ON enrollment
BEGIN
  INSERT INTO registration_log (student_id, section_id, action)
  VALUES (OLD.student_id, OLD.section_id, 'DROP');

  INSERT INTO enrollment (student_id, section_id)
  SELECT student_id, section_id FROM v_waitlist_rank
  WHERE section_id = OLD.section_id AND no_conflict = 1 AND seats_left > 0
  ORDER BY priority, requested_at
  LIMIT 1;
END;

-- เข้าคิวได้เฉพาะตอนที่ section เต็มสำหรับหลักสูตรของตัวเอง
CREATE TRIGGER trg_waitlist_rules
BEFORE INSERT ON waitlist
BEGIN
  SELECT RAISE(ABORT, 'ยังมีที่นั่ง ลงทะเบียนได้เลยไม่ต้องเข้าคิว')
  WHERE (SELECT seats_left FROM v_seat_for_student
          WHERE student_id = NEW.student_id AND section_id = NEW.section_id) > 0;

  SELECT RAISE(ABORT, 'ลงวิชานี้ไว้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM enrollment e
    JOIN section es ON es.section_id = e.section_id
    JOIN section ns ON ns.section_id = NEW.section_id
    WHERE e.student_id = NEW.student_id
      AND es.term_id = ns.term_id AND es.course_code = ns.course_code);
END;

CREATE TRIGGER trg_waitlist_after_add
AFTER INSERT ON waitlist
BEGIN
  INSERT INTO registration_log (student_id, section_id, action)
  VALUES (NEW.student_id, NEW.section_id, 'WAITLIST');
END;

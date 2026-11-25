-- Mini Project: ระบบวางแผนและตรวจสอบการลงทะเบียนตามแผนการเรียน (Study Plan–Aware Registration System)
-- โครงสร้างตาราง + view + trigger (SQLite 3.25+)
-- รันทั้งชุดจากโฟลเดอร์ Mini_Project_PlanA: sqlite3 :memory: ".read run.sql"
--
-- ผู้ใช้ 3 บทบาท: นักศึกษา (student), ฝ่ายทะเบียน (admin), อาจารย์ผู้จัดตาราง (scheduler)
-- กฎทางธุรกิจอยู่ใน trigger ทั้งหมด ส่วนสิทธิ์ว่าใครทำอะไรได้ตรวจในแอป
-- แอปเขียนผู้ทำรายการลง app_session ในทุก transaction ที่แก้ข้อมูล (ไม่มีแถว = รันจาก sqlite3 โดยตรง)
-- เวลาทั้งหมดเก็บเป็นเวลาท้องถิ่น รูปแบบ 'YYYY-MM-DD HH:MM'

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
  credit_pattern TEXT,                           -- '3(3-0-6)' ใช้แสดงผลเท่านั้น
  -- หมวดวิชาสำหรับลำดับการจัดตาราง: service = วิชาส่วนกลางที่เรียนร่วมหลายสาขา (จัดและล็อกก่อน),
  -- core = วิชาบังคับสาขา, elective = วิชาเลือก, regular = อื่นๆ
  course_category TEXT NOT NULL DEFAULT 'regular'
                  CHECK (course_category IN ('service', 'core', 'elective', 'regular'))
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
  reg_open_at   TEXT,                            -- ช่วงลงทะเบียนปกติ: นักศึกษาลง/ถอน/เข้าคิวเองได้ (NULL = ยังไม่เปิด)
  reg_close_at  TEXT,
  add_open_at   TEXT,                            -- ช่วงเพิ่มวิชา (รวมลงทะเบียนล่าช้า): ลงและเข้าคิวได้ แต่ถอนไม่ได้
  add_close_at  TEXT,
  drop_open_at  TEXT,                            -- ช่วงลดวิชา: ถอนได้ แต่ลงเพิ่มไม่ได้
  drop_close_at TEXT,
  max_credits   INTEGER NOT NULL DEFAULT 22 CHECK (max_credits > 0),  -- หน่วยกิตสูงสุดต่อภาค
  UNIQUE (academic_year, semester),
  CHECK (reg_open_at  IS NULL OR reg_close_at  IS NULL OR reg_open_at  < reg_close_at),
  CHECK (add_open_at  IS NULL OR add_close_at  IS NULL OR add_open_at  < add_close_at),
  CHECK (drop_open_at IS NULL OR drop_close_at IS NULL OR drop_open_at < drop_close_at)
);
-- มีภาคปัจจุบันได้ภาคเดียว
CREATE UNIQUE INDEX ux_term_one_current ON term(is_current) WHERE is_current = 1;

CREATE TABLE instructor (
  instructor_id INTEGER PRIMARY KEY,
  full_name     TEXT NOT NULL UNIQUE
);

CREATE TABLE room (
  room_code TEXT PRIMARY KEY,
  capacity  INTEGER CHECK (capacity > 0)        -- NULL = ไม่ทราบความจุ
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
  start_time TEXT    NOT NULL CHECK (start_time GLOB '[0-2][0-9]:[0-5][0-9]'),
  end_time   TEXT    NOT NULL CHECK (end_time   GLOB '[0-2][0-9]:[0-5][0-9]'),
  room_code  TEXT    REFERENCES room(room_code),   -- NULL = ยังไม่ระบุห้อง (N/A)
  UNIQUE (section_id, exam_type),
  CHECK (start_time < end_time)
);

------------------------------------------------------------------
-- 4) ผู้ใช้ระบบ
------------------------------------------------------------------
-- นักศึกษาต้องผูกกับ student_id, ผู้จัดตารางผูกกับ instructor_id ได้ (ไม่บังคับ), admin ไม่ผูก
CREATE TABLE app_user (
  user_id       INTEGER PRIMARY KEY,
  username      TEXT    NOT NULL UNIQUE,
  password_hash TEXT    NOT NULL,
  role          TEXT    NOT NULL CHECK (role IN ('student', 'admin', 'scheduler')),
  student_id    TEXT    UNIQUE REFERENCES student(student_id),
  instructor_id INTEGER UNIQUE REFERENCES instructor(instructor_id),
  is_active     INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1)),
  created_at    TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%S', 'now', 'localtime')),
  CHECK ((role = 'student') = (student_id IS NOT NULL)),
  CHECK (role = 'scheduler' OR instructor_id IS NULL)
);

-- ผู้ทำรายการใน transaction ปัจจุบัน: แอปใส่แถวนี้ก่อนแก้ข้อมูลและลบออกก่อน commit
-- SQLite เขียนได้ทีละ transaction จึงมีผู้ทำรายการได้ทีละคนเสมอ
CREATE TABLE app_session (
  id      INTEGER PRIMARY KEY CHECK (id = 1),
  user_id INTEGER NOT NULL REFERENCES app_user(user_id)
);

-- ลำดับการจัดและการล็อกตารางของแต่ละกลุ่มเรียน (ไม่มีแถว = ยังไม่กำหนดลำดับและไม่ได้ล็อก)
-- ไม่เก็บ term_id ซ้ำ เพราะ section ระบุภาคเรียนอยู่แล้ว (3NF)
-- locked_at และ locked_by_user_id ให้ trigger ใส่เองตอนล็อก (ผู้ทำรายการอ่านจาก app_session)
CREATE TABLE scheduling_priority (
  section_id        INTEGER PRIMARY KEY REFERENCES section(section_id) ON DELETE CASCADE,
  priority          INTEGER NOT NULL DEFAULT 50 CHECK (priority BETWEEN 1 AND 99),
                    -- 1-10 = วิชาส่วนกลาง, 11-30 = วิชาบังคับสาขา, 31-99 = วิชาเลือก/อื่นๆ
  is_locked         INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0, 1)),
  lock_reason       TEXT,
  locked_at         TEXT,
  locked_by_user_id INTEGER REFERENCES app_user(user_id)    -- NULL = ระบบ / sqlite3
);

------------------------------------------------------------------
-- 5) ผลการเรียน การลงทะเบียน คิวสำรอง และประวัติ
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
  enrolled_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime')),
  PRIMARY KEY (student_id, section_id)
);
CREATE INDEX ix_enrollment_section ON enrollment(section_id);

CREATE TABLE waitlist (
  student_id   TEXT    NOT NULL REFERENCES student(student_id),
  section_id   INTEGER NOT NULL REFERENCES section(section_id),
  requested_at TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime')),
  PRIMARY KEY (student_id, section_id)
);

CREATE TABLE registration_log (
  log_id        INTEGER PRIMARY KEY,
  student_id    TEXT    NOT NULL REFERENCES student(student_id),
  section_id    INTEGER NOT NULL REFERENCES section(section_id),
  action        TEXT    NOT NULL CHECK (action IN ('ADD', 'DROP', 'WAITLIST', 'PROMOTE')),
  actor_user_id INTEGER REFERENCES app_user(user_id),        -- NULL = ระบบ / sqlite3
  logged_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))
);

-- ประวัติการแก้ตาราง: เวลาเรียน เวลาสอบ อาจารย์ผู้สอน และการล็อกตาราง (บันทึกด้วย trigger เท่านั้น)
-- entity = 'LOCK': action ADD = ล็อก, REMOVE = ปลดล็อก
CREATE TABLE schedule_log (
  log_id        INTEGER PRIMARY KEY,
  section_id    INTEGER NOT NULL REFERENCES section(section_id),
  entity        TEXT    NOT NULL CHECK (entity IN ('MEETING', 'EXAM', 'INSTRUCTOR', 'LOCK')),
  action        TEXT    NOT NULL CHECK (action IN ('ADD', 'CHANGE', 'REMOVE')),
  detail        TEXT    NOT NULL,
  actor_user_id INTEGER REFERENCES app_user(user_id),
  logged_at     TEXT    NOT NULL DEFAULT (strftime('%Y-%m-%d %H:%M:%f', 'now', 'localtime'))
);

------------------------------------------------------------------
-- 6) VIEW
------------------------------------------------------------------
-- ผู้ทำรายการปัจจุบัน (ว่าง = ระบบ)
CREATE VIEW v_actor AS
SELECT u.user_id, u.role, u.student_id
FROM app_session s JOIN app_user u ON u.user_id = s.user_id;

-- ช่วงต่างๆ ของแต่ละภาค เปิดอยู่หรือไม่ ณ ตอนนี้ (ตามปฏิทินการศึกษา: ลงทะเบียนปกติ / เพิ่มวิชา / ลดวิชา)
-- can_add  = ลงหรือเข้าคิวได้ (ช่วงลงทะเบียนปกติ หรือช่วงเพิ่มวิชา)
-- can_drop = ถอนได้ (ช่วงลงทะเบียนปกติ หรือช่วงลดวิชา)
CREATE VIEW v_term_status AS
SELECT w.*, (w.reg_is_open OR w.add_is_open) AS can_add, (w.reg_is_open OR w.drop_is_open) AS can_drop
FROM (
  SELECT t.*,
         COALESCE(n.now >= t.reg_open_at  AND n.now < t.reg_close_at,  0) AS reg_is_open,
         COALESCE(n.now >= t.add_open_at  AND n.now < t.add_close_at,  0) AS add_is_open,
         COALESCE(n.now >= t.drop_open_at AND n.now < t.drop_close_at, 0) AS drop_is_open
  FROM term t CROSS JOIN (SELECT strftime('%Y-%m-%d %H:%M', 'now', 'localtime') AS now) n
) w;

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

-- หน่วยกิตที่ลงไว้แล้วในแต่ละภาค
CREATE VIEW v_student_credits AS
SELECT e.student_id, s.term_id, SUM(c.credits) AS credits, COUNT(*) AS courses
FROM enrollment e
JOIN section s ON s.section_id = e.section_id
JOIN course c  ON c.course_code = s.course_code
GROUP BY e.student_id, s.term_id;

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
-- eligible = ลงได้จริงตอนนี้ตามกฎของ trg_enrollment_rules ทุกข้อ (ใช้ตัดสินว่าจะเลื่อนใครขึ้นมา)
CREATE VIEW v_waitlist_rank AS
SELECT r.*,
       (r.no_conflict AND r.seats_left > 0 AND r.credits_ok AND r.prereq_ok
        AND NOT r.already_passed AND NOT r.already_enrolled) AS eligible
FROM (
  SELECT w.student_id, w.section_id, sec.course_code, sec.term_id, w.requested_at,
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
           WHERE sf.student_id = w.student_id AND sf.section_id = w.section_id) AS seats_left,
         COALESCE((SELECT cr.credits FROM v_student_credits cr
                    WHERE cr.student_id = w.student_id AND cr.term_id = sec.term_id), 0)
           + c.credits <= t.max_credits AS credits_ok,
         NOT EXISTS (SELECT 1 FROM prerequisite pr
                      WHERE pr.course_code = sec.course_code
                        AND NOT EXISTS (SELECT 1 FROM v_passed p
                                         WHERE p.student_id = w.student_id AND p.course_code = pr.prereq_code)
         ) AS prereq_ok,
         EXISTS (SELECT 1 FROM v_passed p
                  WHERE p.student_id = w.student_id AND p.course_code = sec.course_code) AS already_passed,
         EXISTS (SELECT 1 FROM enrollment e JOIN section es ON es.section_id = e.section_id
                  WHERE e.student_id = w.student_id AND es.term_id = sec.term_id
                    AND es.course_code = sec.course_code) AS already_enrolled
  FROM waitlist w
  JOIN section sec         ON sec.section_id = w.section_id
  JOIN course c            ON c.course_code = sec.course_code
  JOIN term t              ON t.term_id = sec.term_id
  JOIN v_student_level lv  ON lv.student_id = w.student_id
  LEFT JOIN study_plan sp  ON sp.curriculum_id = lv.curriculum_id AND sp.course_code = sec.course_code
) r;

-- คนถัดไปที่จะถูกเลื่อนขึ้นจากคิวของแต่ละ section (เฉพาะคนที่ลงได้จริง)
CREATE VIEW v_waitlist_next AS
SELECT student_id, section_id
FROM (SELECT student_id, section_id,
             ROW_NUMBER() OVER (PARTITION BY section_id ORDER BY priority, requested_at) AS rn
      FROM v_waitlist_rank WHERE eligible)
WHERE rn = 1;

-- การใช้ห้องเรียนและภาระสอนของอาจารย์ (ใช้ทั้งใน trigger จัดตารางและในรายงาน)
CREATE VIEW v_room_usage AS
SELECT cm.room_code, s.term_id, cm.day_of_week, cm.start_time, cm.end_time,
       s.section_id, s.course_code, s.section_no, cm.meeting_id
FROM class_meeting cm JOIN section s ON s.section_id = cm.section_id
WHERE cm.room_code IS NOT NULL;

CREATE VIEW v_instructor_busy AS
SELECT si.instructor_id, s.term_id, cm.day_of_week, cm.start_time, cm.end_time,
       s.section_id, s.course_code, s.section_no, cm.meeting_id
FROM section_instructor si
JOIN section s        ON s.section_id = si.section_id
JOIN class_meeting cm ON cm.section_id = si.section_id;

-- section ของแต่ละวิชาอยู่ในแผนของหลักสูตรใด ชั้นปีใด (วิชานอกแผนได้ค่า NULL)
CREATE VIEW v_section_plan AS
SELECT s.section_id, s.course_code, s.term_id, sp.curriculum_id, sp.year_level,
       sp.semester AS plan_semester, sp.is_required
FROM section s
LEFT JOIN study_plan sp ON sp.course_code = s.course_code;

-- ภาพรวมตารางเรียนของภาคปัจจุบัน หนึ่งแถวต่อคาบต่อ (หลักสูตร, ชั้นปี) ใช้ทำตารางข้ามชั้นปี
CREATE VIEW v_schedule_overview AS
SELECT cm.day_of_week, cm.start_time, cm.end_time,
       s.section_id, s.course_code, c.name_th AS course_name, s.section_no,
       cm.room_code,
       (SELECT group_concat(i.full_name, ', ')
          FROM section_instructor si JOIN instructor i ON i.instructor_id = si.instructor_id
         WHERE si.section_id = s.section_id)                                       AS instructor_name,
       pl.curriculum_id, pl.year_level, pl.plan_semester, pl.is_required,
       (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id)       AS enrolled_count,
       s.capacity
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
-- 7) TRIGGER: กฎการลงทะเบียน (ตรวจตามลำดับ ข้อแรกที่ผิดจะหยุดทันที)
------------------------------------------------------------------
CREATE TRIGGER trg_enrollment_rules
BEFORE INSERT ON enrollment
BEGIN
  -- นักศึกษาลงเองได้เฉพาะช่วงลงทะเบียนปกติหรือช่วงเพิ่มวิชา (ฝ่ายทะเบียนและระบบไม่ติดกฎนี้
  -- รวมถึงการเลื่อนคนอื่นขึ้นจากคิวตอนนักศึกษาถอนในช่วงลดวิชา จึงตรวจเฉพาะเมื่อลงให้ตัวเอง)
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนหรือช่วงเพิ่มวิชาของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND NEW.student_id = (SELECT student_id FROM v_actor)
    AND NOT EXISTS (SELECT 1 FROM section ns JOIN v_term_status ts ON ts.term_id = ns.term_id
                     WHERE ns.section_id = NEW.section_id AND ts.can_add);

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

  -- หน่วยกิตรวมเกินเพดานของภาค
  SELECT RAISE(ABORT, 'หน่วยกิตรวมเกินเพดานที่ลงได้ในภาคเรียนนี้')
  WHERE (SELECT COALESCE(cr.credits, 0) + c.credits - t.max_credits
           FROM section ns
           JOIN course c ON c.course_code = ns.course_code
           JOIN term t   ON t.term_id = ns.term_id
           LEFT JOIN v_student_credits cr ON cr.student_id = NEW.student_id AND cr.term_id = ns.term_id
          WHERE ns.section_id = NEW.section_id) > 0;
END;

-- หลังลงสำเร็จ: บันทึกประวัติ แล้วเอาออกจากคิวของวิชานั้นทุก section
CREATE TRIGGER trg_enrollment_after_add
AFTER INSERT ON enrollment
BEGIN
  INSERT INTO registration_log (student_id, section_id, action, actor_user_id)
  VALUES (NEW.student_id, NEW.section_id,
          CASE WHEN EXISTS (SELECT 1 FROM waitlist
                             WHERE student_id = NEW.student_id AND section_id = NEW.section_id)
               THEN 'PROMOTE' ELSE 'ADD' END,
          (SELECT user_id FROM v_actor));

  DELETE FROM waitlist
  WHERE student_id = NEW.student_id
    AND section_id IN (SELECT s2.section_id FROM section s2
                       JOIN section ns ON ns.section_id = NEW.section_id
                       WHERE s2.course_code = ns.course_code AND s2.term_id = ns.term_id);
END;

-- นักศึกษาถอนเองได้เฉพาะช่วงลงทะเบียนปกติหรือช่วงลดวิชา
CREATE TRIGGER trg_enrollment_before_drop
BEFORE DELETE ON enrollment
BEGIN
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนหรือช่วงลดวิชาของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND OLD.student_id = (SELECT student_id FROM v_actor)
    AND NOT EXISTS (SELECT 1 FROM section os JOIN v_term_status ts ON ts.term_id = os.term_id
                     WHERE os.section_id = OLD.section_id AND ts.can_drop);
END;

-- ถอนวิชา: บันทึกประวัติ แล้วเลื่อนคนแรกในคิวที่ลงได้จริงขึ้นมา
CREATE TRIGGER trg_enrollment_after_drop
AFTER DELETE ON enrollment
BEGIN
  INSERT INTO registration_log (student_id, section_id, action, actor_user_id)
  VALUES (OLD.student_id, OLD.section_id, 'DROP', (SELECT user_id FROM v_actor));

  INSERT INTO enrollment (student_id, section_id)
  SELECT student_id, section_id FROM v_waitlist_next WHERE section_id = OLD.section_id;
END;

-- เข้าคิวได้เฉพาะคนที่มีสิทธิ์เรียนวิชานี้ และเฉพาะตอนที่ section เต็มสำหรับหลักสูตรของตัวเอง
CREATE TRIGGER trg_waitlist_rules
BEFORE INSERT ON waitlist
BEGIN
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนหรือช่วงเพิ่มวิชาของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND NEW.student_id = (SELECT student_id FROM v_actor)
    AND NOT EXISTS (SELECT 1 FROM section ns JOIN v_term_status ts ON ts.term_id = ns.term_id
                     WHERE ns.section_id = NEW.section_id AND ts.can_add);

  SELECT RAISE(ABORT, 'ลงวิชานี้ไว้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM enrollment e
    JOIN section es ON es.section_id = e.section_id
    JOIN section ns ON ns.section_id = NEW.section_id
    WHERE e.student_id = NEW.student_id
      AND es.term_id = ns.term_id AND es.course_code = ns.course_code);

  SELECT RAISE(ABORT, 'สอบผ่านวิชานี้แล้ว')
  WHERE EXISTS (
    SELECT 1 FROM v_passed p JOIN section ns ON ns.course_code = p.course_code
    WHERE ns.section_id = NEW.section_id AND p.student_id = NEW.student_id);

  SELECT RAISE(ABORT, 'ยังไม่ผ่านวิชาบังคับก่อน')
  WHERE EXISTS (
    SELECT 1 FROM prerequisite pr JOIN section ns ON ns.course_code = pr.course_code
    WHERE ns.section_id = NEW.section_id
      AND NOT EXISTS (SELECT 1 FROM v_passed p
                       WHERE p.student_id = NEW.student_id AND p.course_code = pr.prereq_code));

  SELECT RAISE(ABORT, 'ยังมีที่นั่ง ลงทะเบียนได้เลยไม่ต้องเข้าคิว')
  WHERE (SELECT seats_left FROM v_seat_for_student
          WHERE student_id = NEW.student_id AND section_id = NEW.section_id) > 0;
END;

CREATE TRIGGER trg_waitlist_after_add
AFTER INSERT ON waitlist
BEGIN
  INSERT INTO registration_log (student_id, section_id, action, actor_user_id)
  VALUES (NEW.student_id, NEW.section_id, 'WAITLIST', (SELECT user_id FROM v_actor));
END;

------------------------------------------------------------------
-- 8) TRIGGER: งานฝ่ายทะเบียน (ที่นั่งและโควตา)
------------------------------------------------------------------
CREATE TRIGGER trg_section_capacity
BEFORE UPDATE OF capacity ON section
BEGIN
  SELECT RAISE(ABORT, 'จำนวนรับต้องไม่น้อยกว่าจำนวนที่ลงทะเบียนแล้ว')
  WHERE NEW.capacity < (SELECT COUNT(*) FROM enrollment WHERE section_id = NEW.section_id);
END;

CREATE TRIGGER trg_quota_before_insert
BEFORE INSERT ON section_quota
BEGIN
  SELECT RAISE(ABORT, 'โควตาต้องไม่น้อยกว่าจำนวนนักศึกษาหลักสูตรนี้ที่ลงแล้ว')
  WHERE NEW.seats < (SELECT COUNT(*) FROM enrollment e JOIN student s ON s.student_id = e.student_id
                      WHERE e.section_id = NEW.section_id AND s.curriculum_id = NEW.curriculum_id);
END;

CREATE TRIGGER trg_quota_before_update
BEFORE UPDATE OF seats ON section_quota
BEGIN
  SELECT RAISE(ABORT, 'โควตาต้องไม่น้อยกว่าจำนวนนักศึกษาหลักสูตรนี้ที่ลงแล้ว')
  WHERE NEW.seats < (SELECT COUNT(*) FROM enrollment e JOIN student s ON s.student_id = e.student_id
                      WHERE e.section_id = NEW.section_id AND s.curriculum_id = NEW.curriculum_id);
END;

------------------------------------------------------------------
-- 9) TRIGGER: งานจัดตาราง (ตรวจตามลำดับ: ห้อง -> อาจารย์ -> นักศึกษาที่ลงแล้ว)
--    กลุ่มเรียนของ "วิชาเดียวกัน" ใช้ห้อง/อาจารย์/เวลาเดียวกันได้ (เรียนรวม)
------------------------------------------------------------------
CREATE TRIGGER trg_meeting_before_insert
BEFORE INSERT ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM v_room_usage u JOIN section ns ON ns.section_id = NEW.section_id
                WHERE u.room_code = NEW.room_code AND u.term_id = ns.term_id
                  AND u.day_of_week = NEW.day_of_week
                  AND u.start_time < NEW.end_time AND NEW.start_time < u.end_time
                  AND u.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนมีคาบสอนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id AND b.course_code <> ns.course_code
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN section ns       ON ns.section_id = NEW.section_id
                JOIN enrollment oth   ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN section os       ON os.section_id = oth.section_id AND os.term_id = ns.term_id
                JOIN class_meeting cm ON cm.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND cm.day_of_week = NEW.day_of_week
                  AND cm.start_time < NEW.end_time AND NEW.start_time < cm.end_time);
END;

CREATE TRIGGER trg_meeting_before_update
BEFORE UPDATE OF section_id, day_of_week, start_time, end_time, room_code ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'ห้องเรียนนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM v_room_usage u JOIN section ns ON ns.section_id = NEW.section_id
                WHERE u.meeting_id <> OLD.meeting_id
                  AND u.room_code = NEW.room_code AND u.term_id = ns.term_id
                  AND u.day_of_week = NEW.day_of_week
                  AND u.start_time < NEW.end_time AND NEW.start_time < u.end_time
                  AND u.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'อาจารย์ผู้สอนมีคาบสอนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM section_instructor mine
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = mine.instructor_id AND b.term_id = ns.term_id
                WHERE mine.section_id = NEW.section_id AND b.course_code <> ns.course_code
                  AND b.meeting_id <> OLD.meeting_id
                  AND b.day_of_week = NEW.day_of_week
                  AND b.start_time < NEW.end_time AND NEW.start_time < b.end_time);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ลงทะเบียนแล้วเรียนวิชาอื่นในเวลานี้')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN section ns       ON ns.section_id = NEW.section_id
                JOIN enrollment oth   ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN section os       ON os.section_id = oth.section_id AND os.term_id = ns.term_id
                JOIN class_meeting cm ON cm.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND cm.day_of_week = NEW.day_of_week
                  AND cm.start_time < NEW.end_time AND NEW.start_time < cm.end_time);
END;

-- มอบหมายอาจารย์ให้กลุ่มเรียนที่วางคาบแล้ว: อาจารย์ต้องไม่ติดสอนวิชาอื่นในเวลาเดียวกัน
CREATE TRIGGER trg_section_instructor_before_insert
BEFORE INSERT ON section_instructor
BEGIN
  SELECT RAISE(ABORT, 'อาจารย์ท่านนี้มีคาบสอนวิชาอื่นในเวลาเดียวกับกลุ่มเรียนนี้')
  WHERE EXISTS (SELECT 1 FROM class_meeting cm
                JOIN section ns ON ns.section_id = NEW.section_id
                JOIN v_instructor_busy b ON b.instructor_id = NEW.instructor_id AND b.term_id = ns.term_id
                WHERE cm.section_id = NEW.section_id AND b.course_code <> ns.course_code
                  AND b.day_of_week = cm.day_of_week
                  AND b.start_time < cm.end_time AND cm.start_time < b.end_time);
END;

-- เวลาสอบ: ห้องจุพอ ห้องไม่ซ้ำ และนักศึกษาที่ลงแล้วต้องไม่สอบสองวิชาพร้อมกัน
CREATE TRIGGER trg_exam_before_insert
BEFORE INSERT ON exam
BEGIN
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

CREATE TRIGGER trg_exam_before_update
BEFORE UPDATE OF section_id, exam_date, start_time, end_time, room_code ON exam
BEGIN
  SELECT RAISE(ABORT, 'ห้องสอบจุไม่พอสำหรับจำนวนนักศึกษาที่ลงทะเบียน')
  WHERE NEW.room_code IS NOT NULL
    AND (SELECT capacity FROM room WHERE room_code = NEW.room_code)
        < (SELECT COUNT(*) FROM enrollment WHERE section_id = NEW.section_id);

  SELECT RAISE(ABORT, 'ห้องสอบนี้ถูกใช้ในวันและเวลาเดียวกันแล้ว')
  WHERE NEW.room_code IS NOT NULL
    AND EXISTS (SELECT 1 FROM exam ex
                JOIN section os ON os.section_id = ex.section_id
                JOIN section ns ON ns.section_id = NEW.section_id
                WHERE ex.exam_id <> OLD.exam_id
                  AND ex.room_code = NEW.room_code AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time
                  AND os.course_code <> ns.course_code);

  SELECT RAISE(ABORT, 'มีนักศึกษาที่ต้องสอบวิชาอื่นในเวลาเดียวกัน')
  WHERE EXISTS (SELECT 1 FROM enrollment me
                JOIN enrollment oth ON oth.student_id = me.student_id AND oth.section_id <> NEW.section_id
                JOIN exam ex        ON ex.section_id = oth.section_id
                WHERE me.section_id = NEW.section_id
                  AND ex.exam_id <> OLD.exam_id
                  AND ex.exam_date = NEW.exam_date
                  AND ex.start_time < NEW.end_time AND NEW.start_time < ex.end_time);
END;

------------------------------------------------------------------
-- 10) TRIGGER: บันทึกประวัติการแก้ตาราง (วัน 1=จันทร์ ... 7=อาทิตย์)
------------------------------------------------------------------
CREATE TRIGGER trg_meeting_log_add AFTER INSERT ON class_meeting
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'MEETING', 'ADD',
          'วัน ' || NEW.day_of_week || ' ' || NEW.start_time || '-' || NEW.end_time
            || ' ห้อง ' || COALESCE(NEW.room_code, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_meeting_log_change AFTER UPDATE ON class_meeting
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'MEETING', 'CHANGE',
          'วัน ' || OLD.day_of_week || ' ' || OLD.start_time || '-' || OLD.end_time
            || ' ห้อง ' || COALESCE(OLD.room_code, '-') || ' → วัน ' || NEW.day_of_week || ' '
            || NEW.start_time || '-' || NEW.end_time || ' ห้อง ' || COALESCE(NEW.room_code, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_meeting_log_remove AFTER DELETE ON class_meeting
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (OLD.section_id, 'MEETING', 'REMOVE',
          'วัน ' || OLD.day_of_week || ' ' || OLD.start_time || '-' || OLD.end_time
            || ' ห้อง ' || COALESCE(OLD.room_code, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_exam_log_add AFTER INSERT ON exam
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'EXAM', 'ADD',
          NEW.exam_type || ' ' || NEW.exam_date || ' ' || NEW.start_time || '-' || NEW.end_time
            || ' ห้อง ' || COALESCE(NEW.room_code, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_exam_log_change AFTER UPDATE ON exam
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'EXAM', 'CHANGE',
          OLD.exam_type || ' ' || OLD.exam_date || ' ' || OLD.start_time || '-' || OLD.end_time
            || ' ห้อง ' || COALESCE(OLD.room_code, '-') || ' → ' || NEW.exam_date || ' '
            || NEW.start_time || '-' || NEW.end_time || ' ห้อง ' || COALESCE(NEW.room_code, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_exam_log_remove AFTER DELETE ON exam
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (OLD.section_id, 'EXAM', 'REMOVE',
          OLD.exam_type || ' ' || OLD.exam_date || ' ' || OLD.start_time || '-' || OLD.end_time,
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_section_instructor_log_add AFTER INSERT ON section_instructor
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'INSTRUCTOR', 'ADD',
          (SELECT full_name FROM instructor WHERE instructor_id = NEW.instructor_id),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_section_instructor_log_remove AFTER DELETE ON section_instructor
BEGIN
  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (OLD.section_id, 'INSTRUCTOR', 'REMOVE',
          (SELECT full_name FROM instructor WHERE instructor_id = OLD.instructor_id),
          (SELECT user_id FROM v_actor));
END;

------------------------------------------------------------------
-- 11) TRIGGER: การล็อกตาราง
--     เขียนแยกจาก trg_meeting_before_insert/update เดิม (SQLite มี BEFORE trigger หลายตัวบนตารางเดียวได้)
------------------------------------------------------------------
-- กลุ่มที่ล็อกแล้ว เพิ่ม ย้าย หรือลบคาบเรียนไม่ได้ (ย้ายคาบข้ามกลุ่ม ตรวจทั้งกลุ่มเดิมและกลุ่มใหม่)
-- และต้องล็อกวิชาส่วนกลางให้ครบก่อนจึงเพิ่มหรือย้ายคาบของวิชาอื่นได้ (issue #17)
CREATE TRIGGER trg_meeting_lock_before_insert
BEFORE INSERT ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'กลุ่มเรียนนี้ล็อกตารางแล้ว ต้องปลดล็อกก่อน')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p
                WHERE p.section_id = NEW.section_id AND p.is_locked = 1);

  -- วิชาส่วนกลางต้องจัดและล็อกก่อน: ถ้ากลุ่มเรียนวิชาส่วนกลางในภาคเดียวกันที่วางคาบแล้วยังล็อกไม่ครบ
  -- ห้ามเพิ่มหรือย้ายคาบของวิชาอื่น (กลุ่มวิชาส่วนกลางที่ยังไม่มีคาบไม่นับ ไม่งั้นจะวางคาบอะไรไม่ได้เลย)
  SELECT RAISE(ABORT, 'ต้องล็อกวิชาส่วนกลางของภาคนี้ให้ครบก่อน')
  WHERE (SELECT c.course_category FROM section s JOIN course c ON c.course_code = s.course_code
          WHERE s.section_id = NEW.section_id) <> 'service'
    AND EXISTS (SELECT 1 FROM section ns
                JOIN section sv ON sv.term_id = ns.term_id AND sv.section_id <> ns.section_id
                JOIN course cv  ON cv.course_code = sv.course_code AND cv.course_category = 'service'
                WHERE ns.section_id = NEW.section_id
                  AND EXISTS (SELECT 1 FROM class_meeting m WHERE m.section_id = sv.section_id)
                  AND NOT EXISTS (SELECT 1 FROM scheduling_priority p
                                   WHERE p.section_id = sv.section_id AND p.is_locked = 1));
END;

CREATE TRIGGER trg_meeting_lock_before_update
BEFORE UPDATE OF section_id, day_of_week, start_time, end_time, room_code ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'กลุ่มเรียนนี้ล็อกตารางแล้ว ต้องปลดล็อกก่อน')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p
                WHERE p.section_id IN (OLD.section_id, NEW.section_id) AND p.is_locked = 1);

  -- วิชาส่วนกลางต้องจัดและล็อกก่อน: ถ้ากลุ่มเรียนวิชาส่วนกลางในภาคเดียวกันที่วางคาบแล้วยังล็อกไม่ครบ
  -- ห้ามเพิ่มหรือย้ายคาบของวิชาอื่น (กลุ่มวิชาส่วนกลางที่ยังไม่มีคาบไม่นับ ไม่งั้นจะวางคาบอะไรไม่ได้เลย)
  SELECT RAISE(ABORT, 'ต้องล็อกวิชาส่วนกลางของภาคนี้ให้ครบก่อน')
  WHERE (SELECT c.course_category FROM section s JOIN course c ON c.course_code = s.course_code
          WHERE s.section_id = NEW.section_id) <> 'service'
    AND EXISTS (SELECT 1 FROM section ns
                JOIN section sv ON sv.term_id = ns.term_id AND sv.section_id <> ns.section_id
                JOIN course cv  ON cv.course_code = sv.course_code AND cv.course_category = 'service'
                WHERE ns.section_id = NEW.section_id
                  AND EXISTS (SELECT 1 FROM class_meeting m WHERE m.section_id = sv.section_id)
                  AND NOT EXISTS (SELECT 1 FROM scheduling_priority p
                                   WHERE p.section_id = sv.section_id AND p.is_locked = 1));
END;

CREATE TRIGGER trg_meeting_lock_before_delete
BEFORE DELETE ON class_meeting
BEGIN
  SELECT RAISE(ABORT, 'กลุ่มเรียนนี้ล็อกตารางแล้ว ต้องปลดล็อกก่อน')
  WHERE EXISTS (SELECT 1 FROM scheduling_priority p
                WHERE p.section_id = OLD.section_id AND p.is_locked = 1);
END;

-- ล็อกได้เฉพาะกลุ่มที่วางคาบเรียนแล้วอย่างน้อย 1 คาบ
CREATE TRIGGER trg_priority_before_insert
BEFORE INSERT ON scheduling_priority
WHEN NEW.is_locked = 1
BEGIN
  SELECT RAISE(ABORT, 'ล็อกได้เฉพาะกลุ่มเรียนที่วางคาบเรียนแล้ว')
  WHERE NOT EXISTS (SELECT 1 FROM class_meeting WHERE section_id = NEW.section_id);
END;

CREATE TRIGGER trg_priority_before_update
BEFORE UPDATE OF is_locked ON scheduling_priority
WHEN NEW.is_locked = 1 AND OLD.is_locked = 0
BEGIN
  SELECT RAISE(ABORT, 'ล็อกได้เฉพาะกลุ่มเรียนที่วางคาบเรียนแล้ว')
  WHERE NOT EXISTS (SELECT 1 FROM class_meeting WHERE section_id = NEW.section_id);
END;

-- ล็อก: ใส่เวลาและผู้ล็อก (ถ้าไม่ได้ระบุมา) แล้วบันทึกประวัติ
-- UPDATE ข้างในแก้แค่ locked_at/locked_by_user_id จึงไม่ปลุก trigger UPDATE OF is_locked ซ้ำ
CREATE TRIGGER trg_priority_lock_after_insert
AFTER INSERT ON scheduling_priority
WHEN NEW.is_locked = 1
BEGIN
  UPDATE scheduling_priority
     SET locked_at         = COALESCE(NEW.locked_at, strftime('%Y-%m-%d %H:%M:%S', 'now', 'localtime')),
         locked_by_user_id = COALESCE(NEW.locked_by_user_id, (SELECT user_id FROM v_actor))
   WHERE section_id = NEW.section_id;

  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'LOCK', 'ADD', 'ล็อกตาราง: ' || COALESCE(NEW.lock_reason, '-'),
          (SELECT user_id FROM v_actor));
END;

CREATE TRIGGER trg_priority_lock_after_update
AFTER UPDATE OF is_locked ON scheduling_priority
WHEN NEW.is_locked = 1 AND OLD.is_locked = 0
BEGIN
  UPDATE scheduling_priority
     SET locked_at         = strftime('%Y-%m-%d %H:%M:%S', 'now', 'localtime'),
         locked_by_user_id = (SELECT user_id FROM v_actor)
   WHERE section_id = NEW.section_id;

  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'LOCK', 'ADD', 'ล็อกตาราง: ' || COALESCE(NEW.lock_reason, '-'),
          (SELECT user_id FROM v_actor));
END;

-- ปลดล็อก: ล้างเวลา ผู้ล็อก และเหตุผล แล้วบันทึกประวัติ
CREATE TRIGGER trg_priority_unlock_after_update
AFTER UPDATE OF is_locked ON scheduling_priority
WHEN NEW.is_locked = 0 AND OLD.is_locked = 1
BEGIN
  UPDATE scheduling_priority
     SET locked_at = NULL, locked_by_user_id = NULL, lock_reason = NULL
   WHERE section_id = NEW.section_id;

  INSERT INTO schedule_log (section_id, entity, action, detail, actor_user_id)
  VALUES (NEW.section_id, 'LOCK', 'REMOVE', 'ปลดล็อก (เหตุผลเดิม: ' || COALESCE(OLD.lock_reason, '-') || ')',
          (SELECT user_id FROM v_actor));
END;

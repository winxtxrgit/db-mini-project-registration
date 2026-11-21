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
  reg_open_at   TEXT,                            -- ช่วงที่นักศึกษาลง/ถอน/เข้าคิวเองได้ (NULL = ยังไม่เปิด)
  reg_close_at  TEXT,
  max_credits   INTEGER NOT NULL DEFAULT 22 CHECK (max_credits > 0),  -- หน่วยกิตสูงสุดต่อภาค
  UNIQUE (academic_year, semester),
  CHECK (reg_open_at IS NULL OR reg_close_at IS NULL OR reg_open_at < reg_close_at)
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

-- ประวัติการแก้ตาราง: เวลาเรียน เวลาสอบ อาจารย์ผู้สอน (บันทึกด้วย trigger เท่านั้น)
CREATE TABLE schedule_log (
  log_id        INTEGER PRIMARY KEY,
  section_id    INTEGER NOT NULL REFERENCES section(section_id),
  entity        TEXT    NOT NULL CHECK (entity IN ('MEETING', 'EXAM', 'INSTRUCTOR')),
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

-- ช่วงลงทะเบียนของแต่ละภาค เปิดอยู่หรือไม่ ณ ตอนนี้
CREATE VIEW v_term_status AS
SELECT t.*,
       (t.reg_open_at IS NOT NULL AND t.reg_close_at IS NOT NULL
        AND strftime('%Y-%m-%d %H:%M', 'now', 'localtime') >= t.reg_open_at
        AND strftime('%Y-%m-%d %H:%M', 'now', 'localtime') <  t.reg_close_at) AS reg_is_open
FROM term t;

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

------------------------------------------------------------------
-- 7) TRIGGER: กฎการลงทะเบียน (ตรวจตามลำดับ ข้อแรกที่ผิดจะหยุดทันที)
------------------------------------------------------------------
CREATE TRIGGER trg_enrollment_rules
BEFORE INSERT ON enrollment
BEGIN
  -- นักศึกษาทำรายการเองได้เฉพาะในช่วงลงทะเบียน (ฝ่ายทะเบียนและระบบไม่ติดกฎนี้)
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND NOT EXISTS (SELECT 1 FROM section ns JOIN v_term_status ts ON ts.term_id = ns.term_id
                     WHERE ns.section_id = NEW.section_id AND ts.reg_is_open);

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

-- ถอนได้เฉพาะในช่วงลงทะเบียน (สำหรับนักศึกษา)
CREATE TRIGGER trg_enrollment_before_drop
BEFORE DELETE ON enrollment
BEGIN
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND NOT EXISTS (SELECT 1 FROM section os JOIN v_term_status ts ON ts.term_id = os.term_id
                     WHERE os.section_id = OLD.section_id AND ts.reg_is_open);
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
  SELECT RAISE(ABORT, 'ไม่อยู่ในช่วงลงทะเบียนของภาคเรียนนี้')
  WHERE (SELECT role FROM v_actor) = 'student'
    AND NOT EXISTS (SELECT 1 FROM section ns JOIN v_term_status ts ON ts.term_id = ns.term_id
                     WHERE ns.section_id = NEW.section_id AND ts.reg_is_open);

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

"""SQL ของหน้าเว็บ: รายงาน R1–R9 (ชุดเดียวกับ queries.sql แต่รับพารามิเตอร์) และข้อมูลสำหรับหน้าจัดการ"""

DAY_NAME = "CASE {col} WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' " \
           "WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END"

# ------------------------------------------------------------------ นักศึกษา
STUDENT_INFO = """
SELECT s.student_id, s.first_name, s.last_name, s.curriculum_id, p.program_name,
       lv.year_level, lv.semester, lv.term_id,
       ts.reg_open_at, ts.reg_close_at, ts.reg_is_open, ts.max_credits,
       COALESCE(cr.credits, 0) AS credits
FROM student s
JOIN curriculum cu ON cu.curriculum_id = s.curriculum_id
JOIN program p     ON p.program_code = cu.program_code
JOIN v_student_level lv ON lv.student_id = s.student_id
JOIN v_term_status ts   ON ts.term_id = lv.term_id
LEFT JOIN v_student_credits cr ON cr.student_id = s.student_id AND cr.term_id = lv.term_id
WHERE s.student_id = :sid
"""

R1_PLAN_STATUS = """
WITH me AS (SELECT * FROM v_student_level WHERE student_id = :sid),
plan AS (
  SELECT sp.course_code, sp.year_level, sp.semester, me.student_id, me.term_id,
         (sp.year_level = me.year_level AND sp.semester = me.semester) AS is_now
  FROM study_plan sp JOIN me ON me.curriculum_id = sp.curriculum_id
  WHERE sp.is_required = 1
    AND (sp.year_level < me.year_level
         OR (sp.year_level = me.year_level AND sp.semester <= me.semester))
)
SELECT p.course_code, c.name_th, p.year_level || '/' || p.semester AS plan_term,
       CASE
         WHEN EXISTS (SELECT 1 FROM enrollment e JOIN section s ON s.section_id = e.section_id
                       WHERE e.student_id = p.student_id AND s.course_code = p.course_code AND s.term_id = p.term_id)
           THEN CASE WHEN p.is_now THEN 'ลงแล้ว' ELSE 'ลงแล้ว (วิชาค้าง)' END
         WHEN p.is_now THEN 'ยังไม่ได้ลง'
         ELSE 'ค้าง ยังไม่ได้ลง'
       END AS status
FROM plan p JOIN course c ON c.course_code = p.course_code
WHERE NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = p.student_id AND v.course_code = p.course_code)
ORDER BY p.year_level, p.semester, p.course_code
"""

R2_WHY_NOT = """
WITH me AS (SELECT * FROM v_student_level WHERE student_id = :sid),
todo AS (
  SELECT sp.course_code, me.student_id, me.term_id
  FROM study_plan sp JOIN me ON me.curriculum_id = sp.curriculum_id
  WHERE sp.is_required = 1
    AND (sp.year_level < me.year_level OR (sp.year_level = me.year_level AND sp.semester <= me.semester))
    AND NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = me.student_id AND v.course_code = sp.course_code)
    AND NOT EXISTS (SELECT 1 FROM enrollment e JOIN section s ON s.section_id = e.section_id
                     WHERE e.student_id = me.student_id AND s.course_code = sp.course_code AND s.term_id = me.term_id)
),
clash AS (
  SELECT c.section_id, m.student_id, c.kind, group_concat(DISTINCT m.course_code) AS with_course
  FROM v_section_slot c
  JOIN section ns ON ns.section_id = c.section_id
  JOIN v_student_slot m ON m.term_id = ns.term_id AND m.kind = c.kind AND m.slot_key = c.slot_key
                       AND m.start_time < c.end_time AND c.start_time < m.end_time
  WHERE m.student_id = :sid
  GROUP BY c.section_id, m.student_id, c.kind
),
judged AS (
  SELECT t.course_code, c.name_th, s.section_no AS sec,
         CASE
           WHEN s.section_id IS NULL        THEN 'ไม่เปิดสอนเทอมนี้'
           WHEN cc.with_course IS NOT NULL  THEN 'เวลาเรียนชนกับ ' || cc.with_course
           WHEN ce.with_course IS NOT NULL  THEN 'เวลาสอบชนกับ ' || ce.with_course
           WHEN sf.seats_left <= 0          THEN 'ที่นั่ง/โควตาเต็ม'
           WHEN COALESCE(cr.credits, 0) + c.credits > tm.max_credits
                                            THEN 'หน่วยกิตจะเกินเพดาน ' || tm.max_credits
           ELSE 'ลงได้ (เหลือ ' || sf.seats_left || ' ที่)'
         END AS result
  FROM todo t
  JOIN course c ON c.course_code = t.course_code
  JOIN term tm  ON tm.term_id = t.term_id
  LEFT JOIN section s ON s.course_code = t.course_code AND s.term_id = t.term_id
  LEFT JOIN clash cc ON cc.section_id = s.section_id AND cc.kind = 'CLASS'
  LEFT JOIN clash ce ON ce.section_id = s.section_id AND ce.kind = 'EXAM'
  LEFT JOIN v_seat_for_student sf ON sf.section_id = s.section_id AND sf.student_id = t.student_id
  LEFT JOIN v_student_credits cr ON cr.student_id = t.student_id AND cr.term_id = t.term_id
)
SELECT *, result LIKE 'ลงได้%' AS ok FROM judged ORDER BY course_code
"""

R3_EXAMS = """
SELECT x.exam_date, x.start_time || '-' || x.end_time AS time, s.course_code, c.name_th,
       COALESCE(x.room_code, '-') AS room,
       COUNT(*) OVER (PARTITION BY x.exam_date) > 1 AS multi
FROM enrollment e
JOIN section s ON s.section_id = e.section_id
JOIN course c  ON c.course_code = s.course_code
JOIN exam x    ON x.section_id = s.section_id
JOIN term t    ON t.term_id = s.term_id AND t.is_current = 1
WHERE e.student_id = :sid
ORDER BY x.exam_date, x.start_time
"""

R6_BACKLOG_CLASH = f"""
WITH me AS (SELECT * FROM v_student_level WHERE student_id = :sid),
todo AS (
  SELECT sp.course_code,
         CASE WHEN sp.year_level = me.year_level AND sp.semester = me.semester THEN 'NOW' ELSE 'BACKLOG' END AS due
  FROM study_plan sp JOIN me ON me.curriculum_id = sp.curriculum_id
  WHERE sp.is_required = 1
    AND (sp.year_level < me.year_level OR (sp.year_level = me.year_level AND sp.semester <= me.semester))
    AND NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = me.student_id AND v.course_code = sp.course_code)
)
SELECT b.course_code AS backlog_course, bs.section_no AS sec,
       n.course_code AS plan_course, ns.section_no AS plan_sec,
       CASE a.kind WHEN 'CLASS' THEN 'เวลาเรียน' ELSE 'เวลาสอบ' END AS clash,
       CASE WHEN a.kind = 'EXAM' THEN a.slot_key
            ELSE {DAY_NAME.format(col="CAST(a.slot_key AS INTEGER)")} END AS day_or_date,
       a.start_time || '-' || a.end_time AS backlog_time,
       c.start_time || '-' || c.end_time AS plan_time
FROM todo b
CROSS JOIN me
JOIN section bs       ON bs.course_code = b.course_code AND bs.term_id = me.term_id
JOIN v_section_slot a ON a.section_id = bs.section_id
JOIN todo n           ON n.due = 'NOW'
JOIN section ns       ON ns.course_code = n.course_code AND ns.term_id = me.term_id
JOIN v_section_slot c ON c.section_id = ns.section_id AND c.kind = a.kind AND c.slot_key = a.slot_key
                     AND a.start_time < c.end_time AND c.start_time < a.end_time
WHERE b.due = 'BACKLOG'
ORDER BY b.course_code, n.course_code, a.kind
"""

# ทุก section ของเทอมปัจจุบัน พร้อมสถานะสำหรับนักศึกษาคนนี้ (ใช้ในหน้าลงทะเบียน)
SECTIONS_FOR_STUDENT = f"""
WITH me AS (SELECT * FROM v_student_level WHERE student_id = :sid),
times AS (
  SELECT section_id,
         group_concat({DAY_NAME.format(col="day_of_week")} || ' ' || start_time || '-' || end_time
                      || COALESCE(' ' || room_code, ''), ', ') AS class_time
  FROM (SELECT * FROM class_meeting ORDER BY day_of_week, start_time)
  GROUP BY section_id
),
exams AS (
  SELECT section_id, group_concat(exam_date || ' ' || start_time || '-' || end_time, ', ') AS exam_time
  FROM exam GROUP BY section_id
)
SELECT s.section_id, s.course_code, c.name_th, c.credits, s.section_no,
       t.class_time, x.exam_time,
       ss.enrolled, ss.capacity, sf.seats_left,
       sp.year_level || '/' || sp.semester AS plan_term, sp.is_required,
       EXISTS (SELECT 1 FROM enrollment e WHERE e.student_id = :sid AND e.section_id = s.section_id) AS is_enrolled,
       EXISTS (SELECT 1 FROM waitlist w WHERE w.student_id = :sid AND w.section_id = s.section_id) AS is_waiting,
       -- วิชาที่ลงไว้แล้วซึ่งเวลาเรียน/เวลาสอบทับกับ section นี้ (เงื่อนไขเดียวกับ trg_enrollment_rules)
       (SELECT group_concat(DISTINCT m.course_code) FROM v_section_slot c
          JOIN v_student_slot m ON m.student_id = :sid AND m.term_id = s.term_id
           AND m.kind = c.kind AND m.slot_key = c.slot_key
           AND m.start_time < c.end_time AND c.start_time < m.end_time
         WHERE c.section_id = s.section_id AND c.kind = 'CLASS' AND m.section_id <> s.section_id) AS class_clash,
       (SELECT group_concat(DISTINCT m.course_code) FROM v_section_slot c
          JOIN v_student_slot m ON m.student_id = :sid AND m.term_id = s.term_id
           AND m.kind = c.kind AND m.slot_key = c.slot_key
           AND m.start_time < c.end_time AND c.start_time < m.end_time
         WHERE c.section_id = s.section_id AND c.kind = 'EXAM' AND m.section_id <> s.section_id) AS exam_clash,
       COALESCE((SELECT credits FROM v_student_credits cr
                  WHERE cr.student_id = :sid AND cr.term_id = s.term_id), 0) + c.credits > tm.max_credits AS over_credit
FROM section s
JOIN me ON me.term_id = s.term_id
JOIN term tm ON tm.term_id = s.term_id
JOIN course c ON c.course_code = s.course_code
JOIN v_section_seat ss ON ss.section_id = s.section_id
JOIN v_seat_for_student sf ON sf.section_id = s.section_id AND sf.student_id = :sid
LEFT JOIN times t ON t.section_id = s.section_id
LEFT JOIN exams x ON x.section_id = s.section_id
LEFT JOIN study_plan sp ON sp.curriculum_id = me.curriculum_id AND sp.course_code = s.course_code
ORDER BY (sp.course_code IS NULL), s.course_code, s.section_no
"""

WAITLIST_RANK = """
SELECT w.section_id, w.course_code, c.name_th, s.section_no, w.student_id,
       st.first_name || ' ' || st.last_name AS student_name, w.priority, w.requested_at,
       w.no_conflict, w.seats_left, w.credits_ok, w.prereq_ok, w.eligible,
       ROW_NUMBER() OVER (PARTITION BY w.section_id ORDER BY w.priority, w.requested_at) AS queue_no
FROM v_waitlist_rank w
JOIN section s ON s.section_id = w.section_id
JOIN course c  ON c.course_code = w.course_code
JOIN student st ON st.student_id = w.student_id
ORDER BY w.course_code, s.section_no, queue_no
"""

REG_LOG = """
SELECT l.log_id, substr(l.logged_at, 1, 19) AS logged_at, l.student_id,
       st.first_name || ' ' || st.last_name AS student_name,
       s.course_code, c.name_th, s.section_no, l.action,
       COALESCE(u.username, 'ระบบ') AS actor, u.role AS actor_role
FROM registration_log l
JOIN student st ON st.student_id = l.student_id
JOIN section s  ON s.section_id = l.section_id
JOIN course c   ON c.course_code = s.course_code
LEFT JOIN app_user u ON u.user_id = l.actor_user_id
WHERE (:sid = '' OR l.student_id = :sid)
  AND (:action = '' OR l.action = :action)
ORDER BY l.log_id DESC
LIMIT 300
"""

# ------------------------------------------------------------------ ฝ่ายทะเบียน
R4_SEAT_DEMAND = """
WITH need AS (
  SELECT sp.course_code, COUNT(*) AS students_need
  FROM v_student_level lv
  JOIN study_plan sp ON sp.curriculum_id = lv.curriculum_id AND sp.is_required = 1
  WHERE (sp.year_level < lv.year_level OR (sp.year_level = lv.year_level AND sp.semester <= lv.semester))
    AND NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = lv.student_id AND v.course_code = sp.course_code)
  GROUP BY sp.course_code
),
offer AS (
  SELECT s.course_code, COUNT(*) AS sections, SUM(ss.capacity) AS seats, SUM(ss.available) AS available
  FROM section s JOIN v_section_seat ss ON ss.section_id = s.section_id
  JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
  GROUP BY s.course_code
)
SELECT n.course_code, c.name_th, n.students_need,
       COALESCE(o.sections, 0) AS sections, COALESCE(o.seats, 0) AS seats, COALESCE(o.available, 0) AS available,
       CASE WHEN o.course_code IS NULL THEN 'ไม่เปิดสอน'
            WHEN o.available = 0      THEN 'เต็ม'
            ELSE '' END AS alert
FROM need n JOIN course c ON c.course_code = n.course_code
LEFT JOIN offer o ON o.course_code = n.course_code
ORDER BY (o.course_code IS NULL) DESC, n.course_code
"""

R5_QUOTA_LOCKED = """
SELECT s.section_id, s.course_code, c.name_th, s.section_no AS sec, q.curriculum_id, q.used, q.seats,
       ss.enrolled, ss.capacity, ss.available AS section_free
FROM v_quota_seat q
JOIN section s         ON s.section_id = q.section_id
JOIN course c          ON c.course_code = s.course_code
JOIN v_section_seat ss ON ss.section_id = q.section_id
JOIN term t            ON t.term_id = s.term_id AND t.is_current = 1
WHERE q.quota_left <= 0 AND ss.available > 0
"""

R7_CREDITS = """
SELECT s.student_id, s.first_name || ' ' || s.last_name AS name, s.curriculum_id,
       COALESCE(cr.courses, 0) AS courses, COALESCE(cr.credits, 0) AS credits, t.max_credits
FROM student s
JOIN term t ON t.is_current = 1
LEFT JOIN v_student_credits cr ON cr.student_id = s.student_id AND cr.term_id = t.term_id
WHERE (:q = '' OR s.student_id LIKE :q || '%' OR s.first_name LIKE '%' || :q || '%'
       OR s.curriculum_id = :q)
ORDER BY s.curriculum_id = 'EXT', s.student_id
LIMIT 200
"""

STUDENT_LIST = """
SELECT s.student_id, s.first_name, s.last_name, s.curriculum_id, s.entry_year,
       u.username, u.is_active, COALESCE(cr.credits, 0) AS credits
FROM student s
JOIN term t ON t.is_current = 1
LEFT JOIN app_user u ON u.student_id = s.student_id
LEFT JOIN v_student_credits cr ON cr.student_id = s.student_id AND cr.term_id = t.term_id
WHERE (:q = '' OR s.student_id LIKE :q || '%' OR s.first_name LIKE '%' || :q || '%'
       OR s.last_name LIKE '%' || :q || '%' OR s.curriculum_id = :q)
ORDER BY s.curriculum_id = 'EXT', s.student_id
LIMIT 200
"""

TERMS = """
SELECT term_id, academic_year, semester, is_current, reg_open_at, reg_close_at, reg_is_open, max_credits
FROM v_term_status ORDER BY academic_year DESC, semester DESC
"""

SECTIONS_ADMIN = """
SELECT ss.section_id, ss.course_code, c.name_th, c.credits, ss.section_no, ss.term_id,
       ss.capacity, ss.enrolled, ss.available,
       (SELECT COUNT(*) FROM waitlist w WHERE w.section_id = ss.section_id) AS waiting,
       (SELECT COUNT(*) FROM v_waitlist_next n WHERE n.section_id = ss.section_id) AS can_promote,
       (SELECT group_concat(q.curriculum_id || ' ' || q.used || '/' || q.seats, ', ')
          FROM v_quota_seat q WHERE q.section_id = ss.section_id) AS quotas
FROM v_section_seat ss
JOIN course c ON c.course_code = ss.course_code
JOIN term t ON t.term_id = ss.term_id AND t.is_current = 1
ORDER BY ss.course_code, ss.section_no
"""

USERS = """
SELECT u.user_id, u.username, u.role, u.student_id, u.instructor_id, i.full_name AS instructor_name,
       u.is_active, u.created_at
FROM app_user u LEFT JOIN instructor i ON i.instructor_id = u.instructor_id
WHERE (:q = '' OR u.username LIKE '%' || :q || '%' OR u.role = :q)
ORDER BY CASE u.role WHEN 'admin' THEN 1 WHEN 'scheduler' THEN 2 ELSE 3 END, u.username
"""

# ------------------------------------------------------------------ ผู้จัดตาราง
SCHED_SECTIONS = """
SELECT s.section_id, s.course_code, c.name_th, s.section_no, s.capacity,
       (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id) AS enrolled
FROM section s
JOIN course c ON c.course_code = s.course_code
JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
ORDER BY s.course_code, s.section_no
"""

SCHED_MEETINGS = """
SELECT cm.* FROM class_meeting cm
JOIN section s ON s.section_id = cm.section_id
JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
ORDER BY cm.day_of_week, cm.start_time
"""

SCHED_EXAMS = """
SELECT x.* FROM exam x
JOIN section s ON s.section_id = x.section_id
JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
ORDER BY x.exam_date, x.start_time
"""

SCHED_INSTRUCTORS = """
SELECT si.section_id, i.instructor_id, i.full_name
FROM section_instructor si JOIN instructor i ON i.instructor_id = si.instructor_id
ORDER BY i.full_name
"""

R8_ROOM_USAGE = f"""
SELECT u.room_code, r.capacity, u.day_of_week, {DAY_NAME.format(col="u.day_of_week")} AS day,
       u.start_time || '-' || u.end_time AS time, u.course_code, u.section_no
FROM v_room_usage u
JOIN room r ON r.room_code = u.room_code
JOIN term t ON t.term_id = u.term_id AND t.is_current = 1
ORDER BY u.room_code, u.day_of_week, u.start_time
"""

R9_INSTRUCTOR_LOAD = """
SELECT i.instructor_id, i.full_name, COUNT(DISTINCT b.section_id) AS sections,
       COALESCE(SUM((CAST(substr(b.end_time, 1, 2) AS INTEGER) * 60 + CAST(substr(b.end_time, 4, 2) AS INTEGER)
                   - CAST(substr(b.start_time, 1, 2) AS INTEGER) * 60 - CAST(substr(b.start_time, 4, 2) AS INTEGER)) / 60.0), 0)
         AS hours_per_week,
       (SELECT group_concat(DISTINCT s.course_code) FROM section_instructor si
          JOIN section s ON s.section_id = si.section_id
          JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
         WHERE si.instructor_id = i.instructor_id) AS courses
FROM instructor i
LEFT JOIN v_instructor_busy b ON b.instructor_id = i.instructor_id
     AND b.term_id = (SELECT term_id FROM term WHERE is_current = 1)
GROUP BY i.instructor_id
ORDER BY hours_per_week DESC, i.full_name
"""

SCHEDULE_LOG = """
SELECT l.log_id, substr(l.logged_at, 1, 19) AS logged_at, s.course_code, c.name_th, s.section_no,
       l.entity, l.action, l.detail, COALESCE(u.username, 'ระบบ') AS actor
FROM schedule_log l
JOIN section s ON s.section_id = l.section_id
JOIN course c  ON c.course_code = s.course_code
LEFT JOIN app_user u ON u.user_id = l.actor_user_id
ORDER BY l.log_id DESC
LIMIT 300
"""


# ------------------------------------------------------------------ ตารางเรียนรายสัปดาห์ (อ่านอย่างเดียว ใช้กับ core.timetable)
STUDENT_MEETINGS = """
SELECT cm.day_of_week, cm.start_time, cm.end_time, cm.room_code,
       s.section_id, s.course_code, s.section_no, c.name_th
FROM enrollment e
JOIN section s        ON s.section_id = e.section_id
JOIN term t           ON t.term_id = s.term_id AND t.is_current = 1
JOIN course c         ON c.course_code = s.course_code
JOIN class_meeting cm ON cm.section_id = s.section_id
WHERE e.student_id = :sid
ORDER BY cm.day_of_week, cm.start_time
"""

ROOM_MEETINGS = """
SELECT u.day_of_week, u.start_time, u.end_time, u.section_id, u.course_code, u.section_no, c.name_th,
       (SELECT group_concat(i.full_name, ', ') FROM section_instructor si
          JOIN instructor i ON i.instructor_id = si.instructor_id WHERE si.section_id = u.section_id) AS teachers
FROM v_room_usage u
JOIN term t   ON t.term_id = u.term_id AND t.is_current = 1
JOIN course c ON c.course_code = u.course_code
WHERE u.room_code = :room
ORDER BY u.day_of_week, u.start_time
"""

INSTRUCTOR_MEETINGS = """
SELECT b.day_of_week, b.start_time, b.end_time, b.section_id, b.course_code, b.section_no, c.name_th, cm.room_code
FROM v_instructor_busy b
JOIN term t           ON t.term_id = b.term_id AND t.is_current = 1
JOIN course c         ON c.course_code = b.course_code
JOIN class_meeting cm ON cm.meeting_id = b.meeting_id
WHERE b.instructor_id = :iid
ORDER BY b.day_of_week, b.start_time
"""

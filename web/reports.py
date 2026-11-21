"""SQL ของรายงาน R1–R6 (ชุดเดียวกับ queries.sql แต่รับรหัสนักศึกษาเป็นพารามิเตอร์ :sid)"""

DAY_NAME = "CASE {col} WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' " \
           "WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END"

STUDENT_INFO = """
SELECT s.student_id, s.first_name, s.last_name, s.curriculum_id, p.program_name,
       lv.year_level, lv.semester, lv.term_id
FROM student s
JOIN curriculum cu ON cu.curriculum_id = s.curriculum_id
JOIN program p     ON p.program_code = cu.program_code
JOIN v_student_level lv ON lv.student_id = s.student_id
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
)
SELECT t.course_code, c.name_th, s.section_no AS sec,
       CASE
         WHEN s.section_id IS NULL        THEN 'ไม่เปิดสอนเทอมนี้'
         WHEN cc.with_course IS NOT NULL  THEN 'เวลาเรียนชนกับ ' || cc.with_course
         WHEN ce.with_course IS NOT NULL  THEN 'เวลาสอบชนกับ ' || ce.with_course
         WHEN sf.seats_left <= 0          THEN 'ที่นั่ง/โควตาเต็ม'
         ELSE 'ลงได้ (เหลือ ' || sf.seats_left || ' ที่)'
       END AS result,
       (s.section_id IS NOT NULL AND cc.with_course IS NULL AND ce.with_course IS NULL
        AND sf.seats_left > 0) AS ok
FROM todo t
JOIN course c ON c.course_code = t.course_code
LEFT JOIN section s ON s.course_code = t.course_code AND s.term_id = t.term_id
LEFT JOIN clash cc ON cc.section_id = s.section_id AND cc.kind = 'CLASS'
LEFT JOIN clash ce ON ce.section_id = s.section_id AND ce.kind = 'EXAM'
LEFT JOIN v_seat_for_student sf ON sf.section_id = s.section_id AND sf.student_id = t.student_id
ORDER BY t.course_code
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
SELECT s.course_code, c.name_th, s.section_no AS sec, q.curriculum_id, q.used, q.seats,
       ss.enrolled, ss.capacity, ss.available AS section_free
FROM v_quota_seat q
JOIN section s         ON s.section_id = q.section_id
JOIN course c          ON c.course_code = s.course_code
JOIN v_section_seat ss ON ss.section_id = q.section_id
WHERE q.quota_left <= 0 AND ss.available > 0
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
       EXISTS (SELECT 1 FROM waitlist w WHERE w.student_id = :sid AND w.section_id = s.section_id) AS is_waiting
FROM section s
JOIN me ON me.term_id = s.term_id
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
       w.no_conflict, w.seats_left,
       ROW_NUMBER() OVER (PARTITION BY w.section_id ORDER BY w.priority, w.requested_at) AS queue_no
FROM v_waitlist_rank w
JOIN section s ON s.section_id = w.section_id
JOIN course c  ON c.course_code = w.course_code
JOIN student st ON st.student_id = w.student_id
ORDER BY w.course_code, s.section_no, queue_no
"""

SECTION_SEATS = """
SELECT ss.section_id, ss.course_code, c.name_th, ss.section_no, ss.enrolled, ss.capacity, ss.available,
       (SELECT COUNT(*) FROM waitlist w WHERE w.section_id = ss.section_id) AS waiting
FROM v_section_seat ss
JOIN course c ON c.course_code = ss.course_code
JOIN term t ON t.term_id = ss.term_id AND t.is_current = 1
ORDER BY ss.course_code, ss.section_no
"""

LOG = """
SELECT l.log_id, l.logged_at, l.student_id, st.first_name || ' ' || st.last_name AS student_name,
       s.course_code, c.name_th, s.section_no, l.action
FROM registration_log l
JOIN student st ON st.student_id = l.student_id
JOIN section s  ON s.section_id = l.section_id
JOIN course c   ON c.course_code = s.course_code
WHERE (:sid = '' OR l.student_id = :sid)
  AND (:action = '' OR l.action = :action)
ORDER BY l.log_id DESC
LIMIT 300
"""

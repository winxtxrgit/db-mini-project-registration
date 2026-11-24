-- รายงานหลักของระบบ (ใช้กับข้อมูลใน seed.sql)
.mode list
.separator " | "
.headers on

.print ''
.print '=== R1 สถานะแผนการเรียนของนักศึกษา 6799000001 (วิชาบังคับถึงเทอมปัจจุบัน) ==='
WITH me AS (SELECT * FROM v_student_level WHERE student_id = '6799000001'),
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
         WHEN EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = p.student_id AND v.course_code = p.course_code)
           THEN 'ผ่านแล้ว'
         WHEN EXISTS (SELECT 1 FROM enrollment e JOIN section s ON s.section_id = e.section_id
                       WHERE e.student_id = p.student_id AND s.course_code = p.course_code AND s.term_id = p.term_id)
           THEN CASE WHEN p.is_now THEN 'ลงแล้ว' ELSE 'ลงแล้ว (วิชาค้าง)' END
         WHEN p.is_now THEN 'ยังไม่ได้ลง'
         ELSE 'ค้าง ยังไม่ได้ลง'
       END AS status
FROM plan p JOIN course c ON c.course_code = p.course_code
WHERE NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = p.student_id AND v.course_code = p.course_code)
ORDER BY p.year_level, p.semester, p.course_code;

.print ''
.print '=== R2 วิชาบังคับที่ยังไม่ได้ลง ลงได้หรือไม่ และเพราะอะไร ==='
WITH me AS (SELECT * FROM v_student_level WHERE student_id = '6799000001'),
todo AS (
  SELECT sp.course_code, me.student_id, me.term_id
  FROM study_plan sp JOIN me ON me.curriculum_id = sp.curriculum_id
  WHERE sp.is_required = 1
    AND (sp.year_level < me.year_level OR (sp.year_level = me.year_level AND sp.semester <= me.semester))
    AND NOT EXISTS (SELECT 1 FROM v_passed v WHERE v.student_id = me.student_id AND v.course_code = sp.course_code)
    AND NOT EXISTS (SELECT 1 FROM enrollment e JOIN section s ON s.section_id = e.section_id
                     WHERE e.student_id = me.student_id AND s.course_code = sp.course_code AND s.term_id = me.term_id)
),
clash AS (   -- วิชาที่ลงไว้แล้วซึ่งชนกับ section ที่อยากลง
  SELECT c.section_id, m.student_id, c.kind, group_concat(DISTINCT m.course_code) AS with_course
  FROM v_section_slot c
  JOIN section ns ON ns.section_id = c.section_id
  JOIN v_student_slot m ON m.term_id = ns.term_id AND m.kind = c.kind AND m.slot_key = c.slot_key
                       AND m.start_time < c.end_time AND c.start_time < m.end_time
  GROUP BY c.section_id, m.student_id, c.kind
)
SELECT t.course_code, c.name_th, s.section_no AS sec,
       CASE
         WHEN s.section_id IS NULL                 THEN 'ไม่เปิดสอนเทอมนี้'
         WHEN cc.with_course IS NOT NULL           THEN 'เวลาเรียนชนกับ ' || cc.with_course
         WHEN ce.with_course IS NOT NULL           THEN 'เวลาสอบชนกับ ' || ce.with_course
         WHEN sf.seats_left <= 0                   THEN 'ที่นั่ง/โควตาเต็ม'
         WHEN COALESCE(cr.credits, 0) + c.credits > tm.max_credits
                                                   THEN 'หน่วยกิตจะเกินเพดาน ' || tm.max_credits
         ELSE 'ลงได้ (เหลือ ' || sf.seats_left || ' ที่)'
       END AS result
FROM todo t
JOIN course c ON c.course_code = t.course_code
LEFT JOIN section s ON s.course_code = t.course_code AND s.term_id = t.term_id
LEFT JOIN clash cc ON cc.section_id = s.section_id AND cc.student_id = t.student_id AND cc.kind = 'CLASS'
LEFT JOIN clash ce ON ce.section_id = s.section_id AND ce.student_id = t.student_id AND ce.kind = 'EXAM'
LEFT JOIN v_seat_for_student sf ON sf.section_id = s.section_id AND sf.student_id = t.student_id
JOIN term tm ON tm.term_id = t.term_id
LEFT JOIN v_student_credits cr ON cr.student_id = t.student_id AND cr.term_id = t.term_id
ORDER BY t.course_code;

.print ''
.print '=== R3 ตารางสอบของ 6799000001 และวันที่ต้องสอบมากกว่า 1 วิชา ==='
SELECT x.exam_date, x.start_time || '-' || x.end_time AS time, s.course_code, c.name_th,
       CASE WHEN COUNT(*) OVER (PARTITION BY x.exam_date) > 1 THEN '⚠ สอบหลายวิชาวันนี้' ELSE '' END AS note
FROM enrollment e
JOIN section s ON s.section_id = e.section_id
JOIN course c  ON c.course_code = s.course_code
JOIN exam x    ON x.section_id = s.section_id
WHERE e.student_id = '6799000001'
ORDER BY x.exam_date, x.start_time;

.print ''
.print '=== R4 ความต้องการที่นั่งวิชาบังคับเทียบกับที่เปิด (สำหรับฝ่ายทะเบียน) ==='
WITH need AS (   -- นักศึกษาที่ยังไม่ผ่านวิชาบังคับซึ่งถึงกำหนดแล้วตามแผน
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
       CASE WHEN o.course_code IS NULL THEN '❌ ไม่เปิดสอน'
            WHEN o.available = 0      THEN '⚠ เต็ม'
            ELSE '' END AS alert
FROM need n JOIN course c ON c.course_code = n.course_code
LEFT JOIN offer o ON o.course_code = n.course_code
ORDER BY (o.course_code IS NULL) DESC, n.course_code;

.print ''
.print '=== R5 ที่นั่งถูกล็อกด้วยโควตา: หลักสูตรหนึ่งเต็ม แต่ section ยังว่าง ==='
SELECT s.course_code, s.section_no AS sec, q.curriculum_id, q.used || '/' || q.seats AS quota,
       ss.enrolled || '/' || ss.capacity AS section_total, ss.available AS section_free
FROM v_quota_seat q
JOIN section s         ON s.section_id = q.section_id
JOIN v_section_seat ss ON ss.section_id = q.section_id
WHERE q.quota_left <= 0 AND ss.available > 0;

.print ''
.print '=== R6 วิชาค้างของ 6799000001 ที่ชนกับวิชาบังคับตามแผนเทอมนี้ ==='
WITH me AS (SELECT * FROM v_student_level WHERE student_id = '6799000001'),
todo AS (   -- วิชาบังคับที่ถึงกำหนดแล้วแต่ยังไม่ผ่าน: BACKLOG = ค้างจากเทอมก่อน, NOW = ตามแผนเทอมนี้
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
            ELSE CASE a.slot_key WHEN '1' THEN 'จันทร์' WHEN '2' THEN 'อังคาร' WHEN '3' THEN 'พุธ' WHEN '4' THEN 'พฤหัสบดี'
                                 WHEN '5' THEN 'ศุกร์' WHEN '6' THEN 'เสาร์' ELSE 'อาทิตย์' END
       END AS day_or_date,
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
ORDER BY b.course_code, n.course_code, a.kind;

.print ''
.print '=== R7 หน่วยกิตที่ลงในภาคปัจจุบัน เทียบเพดาน (สำหรับฝ่ายทะเบียน, เฉพาะนักศึกษาที่มีบัญชีผู้ใช้) ==='
SELECT u.student_id, s.curriculum_id, COALESCE(cr.courses, 0) AS courses, COALESCE(cr.credits, 0) AS credits,
       t.max_credits,
       CASE WHEN COALESCE(cr.credits, 0) = 0 THEN 'ยังไม่ลงทะเบียน'
            WHEN cr.credits >= t.max_credits THEN 'เต็มเพดาน' ELSE '' END AS note
FROM app_user u
JOIN student s ON s.student_id = u.student_id
JOIN term t ON t.is_current = 1
LEFT JOIN v_student_credits cr ON cr.student_id = u.student_id AND cr.term_id = t.term_id
ORDER BY u.student_id;

.print ''
.print '=== R8 การใช้ห้องเรียนในภาคปัจจุบัน (สำหรับผู้จัดตาราง) ==='
SELECT u.room_code,
       CASE u.day_of_week WHEN 1 THEN 'จันทร์' WHEN 2 THEN 'อังคาร' WHEN 3 THEN 'พุธ' WHEN 4 THEN 'พฤหัสบดี'
                          WHEN 5 THEN 'ศุกร์' WHEN 6 THEN 'เสาร์' ELSE 'อาทิตย์' END AS day,
       u.start_time || '-' || u.end_time AS time, u.course_code, u.section_no
FROM v_room_usage u JOIN term t ON t.term_id = u.term_id AND t.is_current = 1
ORDER BY u.room_code, u.day_of_week, u.start_time;

.print ''
.print '=== R9 ภาระสอนของอาจารย์ในภาคปัจจุบัน (ชั่วโมงต่อสัปดาห์) ==='
SELECT i.full_name, COUNT(DISTINCT b.section_id) AS sections,
       COALESCE(SUM((CAST(substr(b.end_time, 1, 2) AS INTEGER) * 60 + CAST(substr(b.end_time, 4, 2) AS INTEGER)
                   - CAST(substr(b.start_time, 1, 2) AS INTEGER) * 60 - CAST(substr(b.start_time, 4, 2) AS INTEGER)) / 60.0), 0)
         AS hours_per_week
FROM instructor i
LEFT JOIN v_instructor_busy b ON b.instructor_id = i.instructor_id
     AND b.term_id = (SELECT term_id FROM term WHERE is_current = 1)
GROUP BY i.instructor_id
ORDER BY hours_per_week DESC, i.full_name;

.print ''
.print '=== R12 ภาพรวมตารางเรียนข้ามชั้นปีของหลักสูตร CPE63 (แต่ละช่องคือวิชาที่ชั้นปีนั้นเรียนตามแผน) ==='
SELECT CASE day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END AS day,
       start_time || '-' || end_time AS time,
       COALESCE(group_concat(CASE WHEN year_level = 1 THEN course_code || ' (' || COALESCE(room_code, '-') || ')' END, ', '), '') AS year_1,
       COALESCE(group_concat(CASE WHEN year_level = 2 THEN course_code || ' (' || COALESCE(room_code, '-') || ')' END, ', '), '') AS year_2,
       COALESCE(group_concat(CASE WHEN year_level = 3 THEN course_code || ' (' || COALESCE(room_code, '-') || ')' END, ', '), '') AS year_3,
       COALESCE(group_concat(CASE WHEN year_level = 4 THEN course_code || ' (' || COALESCE(room_code, '-') || ')' END, ', '), '') AS year_4,
       COALESCE(group_concat(CASE WHEN year_level IS NULL THEN course_code || ' (' || COALESCE(room_code, '-') || ')' END, ', '), '') AS not_in_plan
FROM v_schedule_overview
WHERE curriculum_id = 'CPE63' OR curriculum_id IS NULL
GROUP BY day_of_week, start_time, end_time
ORDER BY day_of_week, start_time;

.print ''
.print '--- R12 (ต่อ) เปิดดูเฉพาะปี 2 กับปี 3 เพื่อจัดวิชาเรียนซ้ำ ---'
SELECT CASE day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END AS day,
       start_time || '-' || end_time AS time, 'ปี ' || year_level AS year,
       course_code, course_name, section_no AS sec, COALESCE(room_code, '-') AS room_code,
       COALESCE(instructor_name, '-') AS instructor_name,
       enrolled_count || '/' || capacity AS enrolled
FROM v_schedule_overview
WHERE curriculum_id = 'CPE63' AND year_level IN (2, 3)
ORDER BY day_of_week, start_time, year_level;

.print ''
.print '=== R14 วิชาเรียนซ้ำที่ชนกับวิชาบังคับของรุ่นพี่ และวิชาบังคับชั้นปีเดียวกันที่ชนกันเอง ==='
SELECT curriculum_id,
       CASE day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END AS day,
       retake_course || ' (วิชาปี ' || retake_year || ') ' || retake_time AS lower_year_course,
       required_course || ' (บังคับปี ' || senior_year || ') ' || required_time AS senior_required_course,
       affected_students AS seniors_not_passed
FROM v_retake_conflict
ORDER BY affected_students DESC, day_of_week;

SELECT 'วิชาบังคับชั้นปีเดียวกันที่เวลาทับกัน' AS check_name, COUNT(*) AS found,
       CASE WHEN COUNT(*) = 0 THEN 'ไม่พบ' ELSE 'ต้องแก้ตาราง ดู v_cohort_conflict' END AS result
FROM v_cohort_conflict;

.print ''
.print '=== R13 ห้องสอบที่ว่างและจุพอสำหรับ 310-2205 (2027-03-01 เวลา 09:00-12:00) เรียงจากห้องที่พอดีที่สุด ==='
WITH q AS (
  SELECT s.section_id, '2027-03-01' AS d, '09:00' AS t1, '12:00' AS t2,
         (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id) AS students
  FROM section s JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
  WHERE s.course_code = '310-2205'
)
SELECT r.room_code, COALESCE(CAST(r.capacity AS TEXT), 'ไม่ทราบความจุ') AS capacity, q.students,
       CASE
         WHEN used.course_code IS NOT NULL THEN 'ไม่ว่าง: ใช้สอบ ' || used.course_code
         WHEN r.capacity IS NULL           THEN 'ไม่ทราบความจุ'
         WHEN r.capacity < q.students      THEN 'จุไม่พอ'
         ELSE 'ใช้ได้ (ที่นั่งเหลือ ' || (r.capacity - q.students) || ')'
       END AS result
FROM room r
CROSS JOIN q
LEFT JOIN (SELECT ex.room_code, group_concat(s.course_code, ', ') AS course_code
           FROM exam ex JOIN section s ON s.section_id = ex.section_id, q
           WHERE ex.exam_date = q.d AND ex.start_time < q.t2 AND q.t1 < ex.end_time
             AND ex.room_code IS NOT NULL AND ex.section_id <> q.section_id
           GROUP BY ex.room_code) used ON used.room_code = r.room_code
ORDER BY (used.course_code IS NULL AND r.capacity >= q.students) DESC,
         (used.course_code IS NULL AND r.capacity IS NULL) DESC,
         r.capacity IS NULL, r.capacity, r.room_code;

.print ''
.print '=== R15 ห้องเรียนที่ว่างวันศุกร์ 09:00-12:00 และจุได้อย่างน้อย 47 คน (ใช้ตอนย้ายคาบ) ==='
SELECT r.room_code, COALESCE(CAST(r.capacity AS TEXT), 'ไม่ทราบความจุ') AS capacity
FROM room r
WHERE (r.capacity >= 47 OR r.capacity IS NULL)
  AND NOT EXISTS (SELECT 1 FROM v_room_usage u
                  JOIN term t ON t.term_id = u.term_id AND t.is_current = 1
                  WHERE u.room_code = r.room_code AND u.day_of_week = 5
                    AND u.start_time < '12:00' AND '09:00' < u.end_time)
ORDER BY r.capacity IS NULL, r.capacity, r.room_code;

.print ''
.print '=== R16 วันที่นักศึกษาสอบหลายวิชาในวันเดียวกัน (จำนวนนักศึกษาที่ได้รับผล) ==='
SELECT exam_date, course_1, time_1, course_2, time_2, COUNT(*) AS students
FROM v_student_exam_clash
WHERE severity = 'SAME_DAY'
GROUP BY exam_date, course_1, time_1, course_2, time_2
ORDER BY exam_date, course_1, course_2;

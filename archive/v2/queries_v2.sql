-- =====================================================================
-- รายงานสำหรับฝ่ายจัดตารางเรียนและจัดสอบ (R7–R12) ใช้กับ schema_v2.sql + seed_v2.sql
-- =====================================================================
.mode box
.headers on

.print ''
.print '=== R7 อาจารย์ว่างหรือไม่ ถ้าจะวางคาบวันจันทร์ 09:00-12:00 (แก้ค่าใน target_slot เพื่อดูช่วงอื่น) ==='
WITH target_slot AS (SELECT 1 AS day_of_week, '09:00' AS slot_start, '12:00' AS slot_end),
busy AS (
  SELECT b.instructor_id,
         group_concat(CASE b.busy_type
                        WHEN 'teaching' THEN 'สอน ' || b.course_code || ' ' || b.start_time || '-' || b.end_time
                        ELSE 'แจ้งไม่ว่าง ' || b.start_time || '-' || b.end_time || COALESCE(' (' || b.note || ')', '')
                      END, ', ') AS reason
  FROM v_instructor_busy b
  JOIN term t ON t.term_id = b.term_id AND t.is_current = 1
  JOIN target_slot ts ON ts.day_of_week = b.day_of_week
                     AND b.start_time < ts.slot_end AND ts.slot_start < b.end_time
  GROUP BY b.instructor_id
),
pref AS (
  SELECT ia.instructor_id
  FROM instructor_availability ia
  JOIN term t ON t.term_id = ia.term_id AND t.is_current = 1
  JOIN target_slot ts ON ts.day_of_week = ia.day_of_week
                     AND ia.start_time < ts.slot_end AND ts.slot_start < ia.end_time
  WHERE ia.status = 'preferred'
)
SELECT i.instructor_id, i.full_name,
       CASE WHEN b.instructor_id IS NOT NULL THEN '🔴 ไม่ว่าง'
            WHEN p.instructor_id IS NOT NULL THEN '🟢 ว่าง (ช่วงที่อยากสอน)'
            ELSE '🟢 ว่าง' END AS status,
       COALESCE(b.reason, '') AS reason
FROM instructor i
LEFT JOIN busy b ON b.instructor_id = i.instructor_id
LEFT JOIN pref p ON p.instructor_id = i.instructor_id
ORDER BY (b.instructor_id IS NOT NULL) DESC, i.instructor_id;

.print ''
.print '=== R8 ภาพรวมตารางเรียนข้ามชั้นปีของหลักสูตร CPE63 (แต่ละช่องคือวิชาที่ชั้นปีนั้นเรียนตามแผน) ==='
SELECT CASE day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END AS day,
       start_time || '-' || end_time AS time,
       COALESCE(group_concat(CASE WHEN year_level = 1 THEN course_code || ' (' || room_code || ')' END, ', '), '') AS year_1,
       COALESCE(group_concat(CASE WHEN year_level = 2 THEN course_code || ' (' || room_code || ')' END, ', '), '') AS year_2,
       COALESCE(group_concat(CASE WHEN year_level = 3 THEN course_code || ' (' || room_code || ')' END, ', '), '') AS year_3,
       COALESCE(group_concat(CASE WHEN year_level = 4 THEN course_code || ' (' || room_code || ')' END, ', '), '') AS year_4,
       COALESCE(group_concat(CASE WHEN year_level IS NULL THEN course_code || ' (' || room_code || ')'
                                  || CASE WHEN is_locked = 1 THEN ' [ล็อก]' ELSE '' END END, ', '), '') AS not_in_plan
FROM v_schedule_overview
WHERE curriculum_id = 'CPE63' OR curriculum_id IS NULL
GROUP BY day_of_week, start_time, end_time
ORDER BY day_of_week, start_time;

.print ''
.print '--- R8 (ต่อ) เปิดดูเฉพาะปี 2 กับปี 3 เพื่อจัดวิชาเรียนซ้ำ (แก้ year_level IN (...) แทนการกดสวิตช์ชั้นปีบนหน้าจอ)'
SELECT CASE day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' WHEN 5 THEN 'ศ.' WHEN 6 THEN 'ส.' ELSE 'อา.' END AS day,
       start_time || '-' || end_time AS time, 'ปี ' || year_level AS year,
       course_code, course_name, section_no AS sec, room_code, instructor_name,
       enrolled_count || '/' || capacity AS enrolled
FROM v_schedule_overview
WHERE curriculum_id = 'CPE63' AND year_level IN (2, 3)
ORDER BY day_of_week, start_time, year_level;

.print ''
.print '=== R9 ตรวจตารางสอบ: 🔴 สอบชนกัน (ต้องไม่มี) และ 🟡 สอบหลายวิชาในวันเดียวกัน (จำนวนนักศึกษาที่ได้รับผล) ==='
SELECT exam_date, course_1, time_1, course_2, time_2, COUNT(*) AS students,
       CASE severity WHEN 'CLASH' THEN '🔴 สอบชนกัน ต้องแก้ตารางสอบ'
                     ELSE '🟡 สอบหลายวิชาในวันเดียวกัน' END AS severity
FROM v_student_exam_clash
GROUP BY exam_date, course_1, course_2
ORDER BY (severity = 'CLASH') DESC, exam_date, course_1;

.print ''
.print '=== R10 ห้องสอบสำหรับ 310-2205 (สอบ 1 มี.ค. 2570 = 2027-03-01 เวลา 09:00-12:00) เรียงจากห้องที่พอดีที่สุด ==='
WITH q AS (
  SELECT s.section_id, '2027-03-01' AS d, '09:00' AS t1, '12:00' AS t2,
         (SELECT COUNT(*) FROM enrollment e WHERE e.section_id = s.section_id) AS students
  FROM section s JOIN term t ON t.term_id = s.term_id AND t.is_current = 1
  WHERE s.course_code = '310-2205'
)
SELECT r.room_code, r.room_name, r.room_type, r.capacity, q.students,
       CASE
         WHEN used.course_code IS NOT NULL THEN 'ไม่ว่าง: ใช้สอบ ' || used.course_code
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
WHERE r.is_exam_room = 1
ORDER BY (used.course_code IS NULL AND r.capacity >= q.students) DESC, r.capacity;

.print ''
.print '=== R11 วิชาเรียนซ้ำที่ชนกับวิชาบังคับของรุ่นพี่ และวิชาบังคับชั้นปีเดียวกันที่ชนกันเอง ==='
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
.print '=== R12 ความคืบหน้าการจัดตาราง: ชั่วโมงที่วางแล้วเทียบกับชั่วโมงตามหน่วยกิต และสถานะล็อก (เรียงตามลำดับการจัด) ==='
WITH need AS (   -- credit_pattern เช่น 3(3-0-6) = บรรยาย 3 + ปฏิบัติ 0 ชั่วโมงต่อสัปดาห์
  SELECT course_code,
         CAST(substr(p, 1, instr(p, '-') - 1) AS INTEGER)
         + CAST(substr(substr(p, instr(p, '-') + 1), 1, instr(substr(p, instr(p, '-') + 1), '-') - 1) AS INTEGER) AS hours_per_week
  FROM (SELECT course_code, substr(credit_pattern, instr(credit_pattern, '(') + 1) AS p
        FROM course WHERE credit_pattern LIKE '%(%-%-%)')
),
placed AS (
  SELECT section_id,
         SUM((strftime('%s', '2000-01-01 ' || end_time) - strftime('%s', '2000-01-01 ' || start_time)) / 3600.0) AS hours
  FROM class_meeting GROUP BY section_id
)
SELECT COALESCE(sp.priority, 50) AS priority, c.course_category AS category, s.course_code, c.name_th, s.section_no AS sec,
       COALESCE(pl.hours, 0) || '/' || n.hours_per_week AS hours_placed,
       CASE WHEN COALESCE(pl.hours, 0) >= n.hours_per_week THEN 'ครบ' ELSE 'ยังไม่ครบ' END AS placed,
       CASE WHEN sp.is_locked = 1 THEN '🔒 ล็อกแล้ว' ELSE 'ยังไม่ล็อก' END AS lock_status
FROM section s
JOIN term t   ON t.term_id = s.term_id AND t.is_current = 1
JOIN course c ON c.course_code = s.course_code
LEFT JOIN need n   ON n.course_code = s.course_code
LEFT JOIN placed pl ON pl.section_id = s.section_id
LEFT JOIN scheduling_priority sp ON sp.section_id = s.section_id
ORDER BY priority, s.course_code;

.print ''
.print '--- R12 (ต่อ) ห้องเรียนที่ว่างวันศุกร์ 09:00-12:00 และจุได้อย่างน้อย 47 คน (ใช้ตอนย้ายคาบ)'
SELECT r.room_code, r.room_name, r.room_type, r.capacity
FROM room r
WHERE r.capacity >= 47 AND r.room_type <> 'exam_hall'
  AND NOT EXISTS (SELECT 1 FROM v_room_usage u
                  JOIN term t ON t.term_id = u.term_id AND t.is_current = 1
                  WHERE u.room_code = r.room_code AND u.day_of_week = 5
                    AND u.start_time < '12:00' AND '09:00' < u.end_time)
ORDER BY r.capacity;

-- =====================================================================
-- สาธิตกฎของส่วนขยาย v2 (D11–D20) ต่อจาก demo.sql เดิม (D1–D10)
-- ข้อที่ "ควรผิด" จะขึ้น Error จาก trigger แล้วรันข้อต่อไปต่อ
-- =====================================================================
.mode box
.headers on

.print ''
.print '--- D11 วางคาบ 100-2102 วันจันทร์ 09:00-12:00 ในห้อง 15208: ควรผิด เพราะห้องนี้ใช้สอน 310-3313 เวลาเดียวกัน'
INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code)
VALUES (9, 1, '09:00', '12:00', '15208');

.print ''
.print '--- D12 เพิ่มอาจารย์ผู้สอน 312-3302 (จ. 09:00-12:00) ให้สอน 310-3313 (จ. 09:00-12:00) ด้วย: ควรผิด เพราะสอนสองวิชาพร้อมกันไม่ได้'
INSERT INTO section_instructor (section_id, instructor_id) VALUES (7, 6);

.print ''
.print '--- D13 ย้ายคาบ 310-2309 ไปวันจันทร์ 09:00-12:00 ห้อง 15303: ควรผิด เพราะอาจารย์ผู้สอนแจ้งไม่ว่างช่วงนั้น'
UPDATE class_meeting SET day_of_week = 1, start_time = '09:00', end_time = '12:00', room_code = '15303'
WHERE section_id = 3;

.print ''
.print '--- D14 ย้ายคาบ 910-1116 (วิชาส่วนกลางที่ล็อกแล้ว) ไปวันศุกร์: ควรผิด เพราะต้องปลดล็อกก่อน'
UPDATE class_meeting SET day_of_week = 5 WHERE section_id = 8;

.print ''
.print '--- D15 ปลดล็อก 910-1116 แล้ววางคาบวิชาสาขา 310-3419 เพิ่ม: ควรผิด เพราะวิชาส่วนกลางต้องล็อกครบก่อน (แล้วล็อกกลับ)'
UPDATE scheduling_priority SET is_locked = 0 WHERE section_id = 8;
INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code)
VALUES (10, 5, '13:00', '16:00', '15312');
UPDATE scheduling_priority SET is_locked = 1, locked_at = '2026-11-14 10:00' WHERE section_id = 8;

.print ''
.print '--- D16 แก้ปัญหาวิชาเรียนซ้ำชนวิชาบังคับรุ่นพี่ (310-2205 กับ 310-3419 พุธ 09:00-12:00)'
.print '        (ก) ย้าย 310-3419 ไปศุกร์ 09:00-12:00: ควรผิด เพราะอาจารย์ผู้สอนแจ้งไม่ว่าง'
UPDATE class_meeting SET day_of_week = 5 WHERE section_id = 10;
.print '        (ข) ย้าย 310-2205 ไปศุกร์ 09:00-12:00 ห้องเดิม: ควรผ่าน (ห้องว่าง อาจารย์ว่าง นักศึกษาที่ลงแล้วไม่มีคาบวันศุกร์)'
UPDATE class_meeting SET day_of_week = 5 WHERE section_id = 1;
SELECT COUNT(*) AS retake_conflicts_left FROM v_retake_conflict;

.print ''
.print '--- D17 นักศึกษา 6799000001 ลง 310-3419 ที่เคยลงไม่ได้ใน D1 ของ demo.sql: ควรผ่านแล้ว'
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000001', 10);
SELECT s.course_code, c.name_th,
       (SELECT group_concat(CASE m.day_of_week WHEN 1 THEN 'จ.' WHEN 2 THEN 'อ.' WHEN 3 THEN 'พ.' WHEN 4 THEN 'พฤ.' ELSE 'ศ.' END
                            || ' ' || m.start_time || '-' || m.end_time, ', ')
          FROM class_meeting m WHERE m.section_id = s.section_id) AS class_time
FROM enrollment e JOIN section s ON s.section_id = e.section_id JOIN course c ON c.course_code = s.course_code
WHERE e.student_id = '6799000001' AND s.course_code IN ('310-2205', '310-3419');

.print ''
.print '--- D18 จัดห้องสอบของ 310-2205 (ผู้เข้าสอบ 47 คน สอบ 1 มี.ค. 2570 09:00-12:00)'
.print '        (ก) ห้อง 15309: ควรผิด เพราะไม่ใช่ห้องสอบ'
UPDATE exam SET room_code = '15309' WHERE section_id = 1;
.print '        (ข) ห้อง 15303 (จุ 45): ควรผิด เพราะจุไม่พอ'
UPDATE exam SET room_code = '15303' WHERE section_id = 1;
.print '        (ค) ห้อง 15208 (จุ 60): ควรผ่าน'
UPDATE exam SET room_code = '15208' WHERE section_id = 1;
.print '        (ง) จัด 100-2102 ที่สอบวันและเวลาเดียวกันลงห้อง 15208 ด้วย: ควรผิด เพราะห้องสอบซ้ำ'
UPDATE exam SET room_code = '15208' WHERE section_id = 9;
.print '        (จ) จัด 100-2102 ลงห้อง HALL-B แทน: ควรผ่าน'
UPDATE exam SET room_code = 'HALL-B' WHERE section_id = 9;

.print ''
.print '--- D19 กำหนดวันสอบ 310-3313 (reg ยังไม่ประกาศ)'
.print '        (ก) 9 มี.ค. 2570 09:00-12:00: ควรผิด เพราะมีนักศึกษาที่ต้องสอบ 310-2309 เวลาเดียวกัน'
INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time, room_code)
VALUES (7, 'FINAL', '2027-03-09', '09:00', '12:00', '15303');
.print '        (ข) 10 มี.ค. 2570 13:00-16:00 ห้อง 15303: ควรผ่าน'
INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time, room_code)
VALUES (7, 'FINAL', '2027-03-10', '13:00', '16:00', '15303');

.print ''
.print '--- D20 ตารางสอบหลังจัดห้อง (view v_exam_schedule_full)'
SELECT exam_date, start_time || '-' || end_time AS time, course_code, course_name,
       student_count AS students, COALESCE(room_code, '(ยังไม่จัดห้อง)') AS room, room_capacity AS capacity
FROM v_exam_schedule_full
ORDER BY exam_date, start_time, course_code;

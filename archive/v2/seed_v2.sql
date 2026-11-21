-- =====================================================================
-- ข้อมูลตัวอย่างของส่วนขยาย v2 (รันต่อจาก schema_v2.sql)
-- ข้อมูลในไฟล์นี้เป็น "ข้อมูลสมมุติ" ทั้งหมด เพราะ reg ไม่ได้แสดง
-- ความจุห้อง ห้องสอบ เวลาว่างของอาจารย์ และสถานะล็อกตาราง
-- =====================================================================

------------------------------------------------------------------
-- 1) รายละเอียดห้อง (รหัสห้อง 6 ห้องแรกมาจาก reg ส่วนชื่อ ประเภท และความจุเป็นค่าสมมุติ)
------------------------------------------------------------------
UPDATE room SET room_name = 'ห้องบรรยาย 15208',          building = 'อาคาร 15', floor_no = 2, room_type = 'lecture',  capacity = 60, is_exam_room = 1 WHERE room_code = '15208';
UPDATE room SET room_name = 'ห้องบรรยาย 15303',          building = 'อาคาร 15', floor_no = 3, room_type = 'lecture',  capacity = 45, is_exam_room = 1 WHERE room_code = '15303';
UPDATE room SET room_name = 'ห้องปฏิบัติการ 15309',      building = 'อาคาร 15', floor_no = 3, room_type = 'lab',      capacity = 40, is_exam_room = 0 WHERE room_code = '15309';
UPDATE room SET room_name = 'ห้องคอมพิวเตอร์ 15312',     building = 'อาคาร 15', floor_no = 3, room_type = 'computer', capacity = 50, is_exam_room = 1 WHERE room_code = '15312';
UPDATE room SET room_name = 'ห้องบรรยายรวม 5427',        building = 'อาคาร 5',  floor_no = 4, room_type = 'lecture',  capacity = 80, is_exam_room = 1 WHERE room_code = '5427';
UPDATE room SET room_name = 'ห้องบรรยาย 4315',           building = 'อาคาร 4',  floor_no = 3, room_type = 'lecture',  capacity = 40, is_exam_room = 0 WHERE room_code = '4315';

-- ห้องสอบรวม (รหัสสมมุติ)
INSERT INTO room (room_code, capacity, room_name, building, floor_no, room_type, is_exam_room) VALUES
('HALL-A', 120, 'ห้องสอบรวม A', 'อาคารอเนกประสงค์', 1, 'exam_hall', 1),
('HALL-B',  60, 'ห้องสอบรวม B', 'อาคารอเนกประสงค์', 1, 'exam_hall', 1);

------------------------------------------------------------------
-- 2) หมวดวิชา
--    service  = วิชาศึกษาทั่วไป ภาษา และวิชาพื้นฐานวิศวกรรมที่เรียนร่วมหลายสาขา (รหัส 9xx และ 300)
--    core     = วิชาบังคับในแผนของสาขา
--    elective = วิชาเลือกของสาขา
------------------------------------------------------------------
UPDATE course SET course_category = 'service' WHERE course_code GLOB '9*' OR course_code GLOB '300-*';
UPDATE course SET course_category = 'core'
WHERE course_category = 'regular'
  AND course_code IN (SELECT course_code FROM study_plan WHERE is_required = 1);
UPDATE course SET course_category = 'elective'
WHERE course_category = 'regular'
  AND (course_code IN (SELECT course_code FROM study_plan WHERE is_required = 0) OR course_code = '310-3313');

------------------------------------------------------------------
-- 3) เวลาว่าง/ไม่ว่างที่อาจารย์ส่งก่อนเปิดภาค 2/2569
------------------------------------------------------------------
INSERT INTO instructor_availability (instructor_id, term_id, day_of_week, start_time, end_time, status, note, submitted_at) VALUES
(3,  '2569-2', 1, '09:00', '12:00', 'unavailable', 'ประชุมประจำสัปดาห์',      '2026-10-20 10:00'),
(3,  '2569-2', 3, '13:00', '16:00', 'preferred',   NULL,                      '2026-10-20 10:00'),
(1,  '2569-2', 5, '09:00', '12:00', 'preferred',   NULL,                      '2026-10-21 09:30'),
(1,  '2569-2', 2, '13:00', '16:00', 'unavailable', 'ติดภารกิจนอกสถาบัน',      '2026-10-21 09:30'),
(10, '2569-2', 5, '09:00', '12:00', 'unavailable', 'ติดภารกิจนอกสถาบัน',      '2026-10-22 14:00'),
(5,  '2569-2', 5, '13:00', '16:00', 'unavailable', 'ติดภารกิจนอกสถาบัน',      '2026-10-22 15:10'),
(8,  '2569-2', 4, '08:00', '17:00', 'unavailable', 'ไม่อยู่ทั้งวัน',          '2026-10-19 08:45');

------------------------------------------------------------------
-- 4) ลำดับการจัดและการล็อก: วิชาส่วนกลางจัดก่อนและล็อกแล้ว วิชาสาขายังไม่ล็อก
------------------------------------------------------------------
INSERT INTO scheduling_priority (section_id, priority, is_locked, lock_reason, locked_by, locked_at) VALUES
(8, 1, 1, 'วิชาศึกษาทั่วไป เรียนร่วมหลายคณะ', 'ฝ่ายจัดตาราง', '2026-10-15 09:00');

INSERT INTO scheduling_priority (section_id, priority)
SELECT s.section_id,
       CASE c.course_category WHEN 'core' THEN 20 WHEN 'elective' THEN 40 ELSE 50 END
FROM section s
JOIN course c ON c.course_code = s.course_code
JOIN term t   ON t.term_id = s.term_id AND t.is_current = 1
WHERE s.section_id <> 8;

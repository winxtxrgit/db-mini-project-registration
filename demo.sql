-- สาธิต trigger: แต่ละข้อที่ "ควรผิด" จะขึ้น Error แล้วรันข้อต่อไปต่อ
.mode list
.separator " | "
.headers on

.print ''
.print '--- D1 ลง 310-3419 (วิชาบังคับตามแผน 2/2569): ควรผิด เพราะเรียน พ. 09:00-12:00 ชนกับ 310-2205 ที่เป็นวิชาค้าง'
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000001', 10);

.print ''
.print '--- D2 ลง 312-3302 ปัญญาประดิษฐ์ (วิชาบังคับตามแผน 2/2569): ควรผิด เพราะเรียน จ. 09:00-12:00 ชนกับ 310-3313'
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000001', 6);

.print ''
.print '--- D3 เวลาสอบชน: เปิดกลุ่มสาธิต 02 ของ 310-3313 (ศ. 13:00-16:00) สอบ 9 มี.ค. 09:00-12:00 ตรงกับ 310-2309 แล้ว 6799000003 ขอลง: ควรผิด'
INSERT INTO section (section_id, course_code, term_id, section_no, capacity) VALUES (11, '310-3313', '2569-2', '02', 10);
INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) VALUES (11, 5, '13:00', '16:00', '15303');
INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time) VALUES (11, 'FINAL', '2027-03-09', '09:00', '12:00');
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000003', 11);

.print ''
.print '--- D4 6799000005 ลง 312-3302 ปัญญาประดิษฐ์: ควรผ่าน และตารางสอบเตือนว่า 9 มี.ค. ต้องสอบ 2 วิชา (เวลาไม่ชน)'
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 6);
SELECT x.exam_date, x.start_time || '-' || x.end_time AS time, s.course_code,
       CASE WHEN COUNT(*) OVER (PARTITION BY x.exam_date) > 1 THEN '⚠ สอบหลายวิชาวันนี้' ELSE '' END AS note
FROM enrollment e JOIN section s ON s.section_id = e.section_id JOIN exam x ON x.section_id = s.section_id
WHERE e.student_id = '6799000005' ORDER BY x.exam_date, x.start_time;

.print ''
.print '--- D5 นักศึกษาหลักสูตร 69 ลง 100-2102: ควรผิด เพราะโควตา :69 เต็ม ทั้งที่ห้องยังว่าง 15 ที่'
INSERT INTO enrollment (student_id, section_id) VALUES ('B6907', 9);

.print ''
.print '--- D6 ลงวิชาที่ยังไม่ผ่านวิชาบังคับก่อน: ควรผิด'
INSERT INTO enrollment (student_id, section_id) VALUES ('F0300', 5);

.print ''
.print '--- D7 คิวสำรอง: เติม 310-2205 ให้เต็ม 50/50'
INSERT INTO enrollment (student_id, section_id) VALUES ('F0287', 1), ('F0288', 1), ('F0289', 1);
SELECT course_code, enrolled, capacity, available FROM v_section_seat WHERE section_id = 1;

-- นักศึกษาปี 4 ที่เคยได้ F วิชานี้ (วิชาค้าง)
INSERT INTO student VALUES ('6799000006', 'เอฟ', 'สมมุติ', 'CPE63', 2566);
INSERT INTO transcript VALUES ('6799000006', '310-2205', '2568-2', 'F');

.print ''
.print '--- D8 เข้าคิว: F0290 ขอก่อน แต่ 6799000006 ติดวิชาค้าง จึงได้ลำดับก่อน'
INSERT INTO waitlist (student_id, section_id, requested_at) VALUES ('F0290', 1, '2026-11-09 08:00:00');
INSERT INTO waitlist (student_id, section_id, requested_at) VALUES ('6799000006', 1, '2026-11-09 10:00:00');
SELECT student_id, priority, requested_at, no_conflict, seats_left
FROM v_waitlist_rank WHERE section_id = 1 ORDER BY priority, requested_at;

.print ''
.print '--- D9 เข้าคิว section ที่ยังว่าง: ควรผิด (ระบบแจ้งให้ไปลงทะเบียนตามปกติ)'
INSERT INTO waitlist (student_id, section_id) VALUES ('F0291', 2);

.print ''
.print '--- D10 F0001 ถอน 310-2205 ระบบจะเลื่อนคนแรกในคิวขึ้นมาเอง'
DELETE FROM enrollment WHERE student_id = 'F0001' AND section_id = 1;
SELECT student_id, priority FROM v_waitlist_rank WHERE section_id = 1;
SELECT log_id, student_id, section_id, action FROM registration_log
WHERE section_id = 1 AND log_id > (SELECT MAX(log_id) - 3 FROM registration_log);

------------------------------------------------------------------
-- ส่วนที่เพิ่มในรอบออกแบบ 3 บทบาท
-- app_session = ผู้ทำรายการ (แอปใส่ให้อัตโนมัติ ในไฟล์นี้ใส่เองเพื่อจำลอง)
------------------------------------------------------------------
.print ''
.print '--- D11 ช่วงลงทะเบียนปิดแล้ว: นักศึกษา 6799000005 ถอน 310-2308 เอง: ควรผิด / ฝ่ายทะเบียนถอนแทน: ผ่าน'
UPDATE term SET reg_close_at = '2026-11-01 00:00' WHERE term_id = '2569-2';
INSERT INTO app_session VALUES (1, (SELECT user_id FROM app_user WHERE username = '6799000005'));
DELETE FROM enrollment WHERE student_id = '6799000005' AND section_id = 2;
UPDATE app_session SET user_id = (SELECT user_id FROM app_user WHERE username = 'admin');
DELETE FROM enrollment WHERE student_id = '6799000005' AND section_id = 2;
DELETE FROM app_session;
UPDATE term SET reg_close_at = '2027-01-15 23:59' WHERE term_id = '2569-2';
SELECT l.log_id, l.student_id, l.section_id, l.action, u.username AS actor
FROM registration_log l LEFT JOIN app_user u ON u.user_id = l.actor_user_id
WHERE l.log_id = (SELECT MAX(log_id) FROM registration_log);

.print ''
.print '--- D12 หน่วยกิตเกินเพดาน: ลดเพดานเหลือ 8 แล้ว 6799000005 (ลงอยู่ 6 หน่วยกิต) ลง 310-2311 อีก 3: ควรผิด'
UPDATE term SET max_credits = 8 WHERE term_id = '2569-2';
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 4);
UPDATE term SET max_credits = 22 WHERE term_id = '2569-2';

.print ''
.print '--- D13 ผู้จัดตารางวางคาบ 310-2308 ที่ห้อง 15208 วันพุธ 09:00-10:00 ซึ่ง 310-2205 ใช้อยู่: ควรผิด'
INSERT INTO app_session VALUES (1, (SELECT user_id FROM app_user WHERE username = 'scheduler'));
INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) VALUES (2, 3, '09:00', '10:00', '15208');

.print ''
.print '--- D14 มอบหมายอาจารย์ที่สอน 310-2205 (พ. 09:00-12:00) ให้สอน 310-3419 ซึ่งเวลาเดียวกันด้วย: ควรผิด'
INSERT INTO section_instructor VALUES (10, 1);

.print ''
.print '--- D15 ย้าย 312-3302 จาก จ. 09:00-12:00 ไป อ. 13:00-16:00 ซึ่งนักศึกษาบางคนเรียน 310-2308 อยู่: ควรผิด'
UPDATE class_meeting SET day_of_week = 2, start_time = '13:00', end_time = '16:00' WHERE section_id = 6;

.print ''
.print '--- D16 ใช้ห้องสอบที่จุ 10 คนให้ 310-3419 ซึ่งมีคนลง 16 คน: ควรผิด / ย้ายเวลาสอบไปวันที่ว่าง: ผ่านและมีประวัติ'
INSERT INTO room (room_code, capacity) VALUES ('R-SMALL', 10);
UPDATE exam SET room_code = 'R-SMALL' WHERE section_id = 10;
UPDATE exam SET exam_date = '2027-03-10' WHERE section_id = 10;
DELETE FROM app_session;
SELECT l.log_id, l.section_id, l.entity, l.action, l.detail, u.username AS actor
FROM schedule_log l LEFT JOIN app_user u ON u.user_id = l.actor_user_id
ORDER BY l.log_id DESC LIMIT 1;

.print ''
.print '--- D17 ลดจำนวนรับ 310-3419 เหลือ 10 ทั้งที่ลงแล้ว 16 คน: ควรผิด'
UPDATE section SET capacity = 10 WHERE section_id = 10;

.print ''
.print '--- D18 คิวที่ลงไม่ได้ต้องไม่ทำให้ถอนพัง: F0290 อยู่คิวแรกแต่หน่วยกิตจะเกิน จึงข้ามไปเลื่อน F0291'
INSERT INTO enrollment (student_id, section_id) VALUES ('F0290', 10), ('F0290', 8);
INSERT INTO waitlist (student_id, section_id) VALUES ('F0291', 1);
UPDATE term SET max_credits = 6 WHERE term_id = '2569-2';
SELECT student_id, priority, requested_at, credits_ok FROM v_waitlist_rank WHERE section_id = 1 ORDER BY priority, requested_at;
DELETE FROM enrollment WHERE student_id = 'F0002' AND section_id = 1;
UPDATE term SET max_credits = 22 WHERE term_id = '2569-2';
SELECT student_id, action FROM registration_log WHERE section_id = 1 ORDER BY log_id DESC LIMIT 2;

.print ''
.print '--- D19 ช่วงลดวิชาแยกจากช่วงลงทะเบียน (ตามปฏิทินการศึกษาจริง): ปิดช่วงลงทะเบียน เปิดเฉพาะช่วงลดวิชา'
.print '    6799000005 ถอน 310-2309 เอง: ผ่าน / ลงกลับเอง: ควรผิด / เปิดช่วงเพิ่มวิชาแล้วลงใหม่: ผ่าน'
UPDATE term SET reg_close_at = '2026-11-01 00:00', drop_open_at = '2026-11-01 00:00', drop_close_at = '2099-12-31 23:59'
 WHERE term_id = '2569-2';
SELECT term_id, reg_is_open, add_is_open, drop_is_open, can_add, can_drop FROM v_term_status WHERE term_id = '2569-2';
INSERT INTO app_session VALUES (1, (SELECT user_id FROM app_user WHERE username = '6799000005'));
DELETE FROM enrollment WHERE student_id = '6799000005' AND section_id = 3;
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 3);
UPDATE term SET add_open_at = '2026-11-01 00:00', add_close_at = '2099-12-31 23:59' WHERE term_id = '2569-2';
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000005', 3);
DELETE FROM app_session;
UPDATE term SET reg_close_at = '2027-01-15 23:59', add_open_at = NULL, add_close_at = NULL,
                drop_open_at = NULL, drop_close_at = NULL WHERE term_id = '2569-2';
SELECT l.student_id, s.course_code, l.action, u.username AS actor
FROM registration_log l JOIN section s ON s.section_id = l.section_id LEFT JOIN app_user u ON u.user_id = l.actor_user_id
WHERE l.student_id = '6799000005' ORDER BY l.log_id DESC LIMIT 2;

.print ''
.print '--- D21 ย้ายคาบ 910-1116 ที่ล็อกตารางไว้แล้วไปวันศุกร์: ควรผิด (ต้องปลดล็อกก่อน)'
SELECT s.course_code, p.priority, p.is_locked, p.lock_reason, u.username AS locked_by
FROM scheduling_priority p JOIN section s ON s.section_id = p.section_id
LEFT JOIN app_user u ON u.user_id = p.locked_by_user_id
WHERE p.section_id = 8;
UPDATE class_meeting SET day_of_week = 5 WHERE section_id = 8;

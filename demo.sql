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
.print '--- D3 เวลาสอบชน (ข้อมูลสมมุติ): ถ้า 310-3313 ประกาศสอบ 9 มี.ค. 09:00-12:00 ตรงกับฐานข้อมูล แล้ว 6799000003 ขอลง: ควรผิด'
INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time) VALUES (7, 'FINAL', '2027-03-09', '09:00', '12:00');
INSERT INTO enrollment (student_id, section_id) VALUES ('6799000003', 7);
DELETE FROM exam WHERE section_id = 7;   -- ลบวันสอบสมมุติออก เพราะ reg ยังไม่ประกาศวันสอบของวิชานี้

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

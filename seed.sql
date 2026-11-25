-- ข้อมูลตัวอย่าง
-- รายวิชา แผนการเรียน CPE63 เวลาเรียน/สอบ จำนวนรับ: จาก reg.cdti.ac.th ภาค 2/2569 (ตรวจซ้ำทีละรหัสวิชาเมื่อ 11 พ.ย. 2569)
-- นักศึกษาทุกคนเป็นข้อมูลสมมุติ / วันที่เก็บเป็น ค.ศ. (01/03/70 = 2027-03-01)

PRAGMA foreign_keys = ON;

INSERT INTO program VALUES
 ('6313301', 'วิศวกรรมคอมพิวเตอร์'),
 ('BBA',     'บริหารธุรกิจ (สมมุติรหัส)'),
 ('EXT',     'นักศึกษาหลักสูตรอื่น (จำลองไว้เติมจำนวนคน)');

INSERT INTO curriculum VALUES
 ('CPE63', '6313301', 2563),
 ('BBA65', 'BBA',     2565),
 ('BBA69', 'BBA',     2569),
 ('EXT',   'EXT',     2566);

INSERT INTO term (term_id, academic_year, semester, is_current) VALUES
 ('2567-1', 2567, 1, 0), ('2567-2', 2567, 2, 0),
 ('2568-1', 2568, 1, 0), ('2568-2', 2568, 2, 0),
 ('2569-1', 2569, 1, 0);
-- ภาคปัจจุบัน: ช่วงลงทะเบียนสมมุติ (ยาวกว่าจริง เพื่อให้สาธิตการลงทะเบียนได้) และเพดาน 22 หน่วยกิต
-- ปฏิทินจริงใน reg (ปริญญาตรี ภาคปกติ 2/2569): ลงทะเบียน 29 ต.ค.–4 พ.ย. 2569, เพิ่มวิชา 9–20 พ.ย., ลดวิชา 9 พ.ย.–4 ธ.ค.
-- ช่วงเพิ่ม/ลดวิชา (add_*/drop_*) เว้นว่างไว้ ตั้งได้ที่หน้าภาคเรียนของฝ่ายทะเบียน (สาธิตใน demo.sql ข้อ D19)
INSERT INTO term (term_id, academic_year, semester, is_current, reg_open_at, reg_close_at, max_credits) VALUES
 ('2569-2', 2569, 2, 1, '2026-10-20 08:00', '2027-01-15 23:59', 22);

INSERT INTO course (course_code, name_th, name_en, credits, credit_pattern) VALUES
 ('300-1101','คณิตศาสตร์วิศวกรรม 1','Engineering Mathematics 1',3,'3(3-0-6)'),
 ('300-1103','ฟิสิกส์','Physics',3,'3(3-0-6)'),
 ('300-1104','ปฏิบัติการฟิสิกส์','Physics Laboratory',1,'1(0-3-2)'),
 ('300-1107','พื้นฐานการเขียนโปรแกรม','Programming Fundamentals',3,'3(2-2-6)'),
 ('920-1135','สุขภาวะกายและจิต','Body and Mind Wellness',3,'3(3-0-6)'),
 ('920-1136','ภาวะผู้นำและบุคลิกภาพ','Leadership and Personality',1,'1(0-3-1)'),
 ('931-1107','คณิตศาสตร์และสถิติในชีวิตประจำวัน','Mathematics and Statistics in Daily Life',3,'3(3-0-6)'),
 ('942-1101','ภาษาอังกฤษปรับพื้นฐาน 1','Remedial English Language 1',0,'0(3-0-6)'),
 ('300-1102','คณิตศาสตร์วิศวกรรม 2','Engineering Mathematics 2',3,'3(3-0-6)'),
 ('300-1105','ทฤษฎีวงจรไฟฟ้า','Electric Circuit Theory',3,'3(3-0-6)'),
 ('300-1106','ปฏิบัติการวงจรไฟฟ้า','Electric Circuit Laboratory',1,'1(0-3-2)'),
 ('310-2101','โครงสร้างข้อมูลและขั้นตอนวิธี','Data Structures and Algorithms',3,'3(2-2-6)'),
 ('300-1208','วิยุตคณิต','Discrete Mathematics',3,'3(3-0-6)'),
 ('300-1209','การออกแบบลอจิกของระบบดิจิทัล','Logic Design of Digital Systems',3,'3(3-0-6)'),
 ('300-1210','ปฏิบัติการออกแบบระบบดิจิทัล','Digital System Design Laboratory',1,'1(0-3-2)'),
 ('310-2202','โครงสร้างของระบบคอมพิวเตอร์','Computer Organization',3,'3(3-0-6)'),
 ('310-2203','การพัฒนาระบบซอฟต์แวร์ 1','Software Systems Development 1',1,'1(0-6-2)'),
 ('300-1211','สถิติคณิตศาสตร์','Mathematical Statistics',3,'3(3-0-6)'),
 ('310-2204','การพัฒนาระบบซอฟต์แวร์ 2','Software Systems Development 2',2,'2(0-6-2)'),
 ('310-2205','วิศวกรรมซอฟต์แวร์','Software Engineering',3,'3(3-0-6)'),
 ('310-2206','ระบบปฏิบัติการ','Operating Systems',3,'3(3-0-6)'),
 ('310-3312','หัวข้อคัดสรรด้านวิศวกรรมคอมพิวเตอร์ 1','Selected Topics in Computer Engineering 1',3,'3(3-0-6)'),
 ('942-1108','ภาษาอังกฤษเพื่อวิชาชีพ','English Language for Career',2,'2(1-2-3)'),
 ('310-2307','เครือข่ายคอมพิวเตอร์','Computer Networks',3,'3(3-0-6)'),
 ('310-2310','การพัฒนาโปรแกรมแบบอะซิโครนัส','Asynchronous Programing Development',3,'3(3-0-6)'),
 ('310-3311','การประมวลผลภาพ','Image Processing',3,'3(3-0-6)'),
 ('311-3303','การออกแบบระบบฝังตัว','Embedded System Design',3,'3(3-0-6)'),
 ('311-3304','ปฏิบัติการออกแบบระบบฝังตัว','Embedded System Design Laboratory',1,'1(0-3-2)'),
 ('941-1102','ภาษาไทยเพื่อการสื่อสาร','Thai Language for Communication',2,'2(1-2-3)'),
 ('942-1112','ภาษาอังกฤษเพื่อการนำเสนอ','English Language for Presentation',2,'2(1-2-3)'),
 ('942-1113','การอ่านภาษาอังกฤษเชิงวิเคราะห์','English Reading for Analysis',2,'2(1-2-3)'),
 ('943-1109','ภาษาจีนกลาง 3','Chinese Language 3',1,'1(0-3-1)'),
 ('944-1109','ภาษาญี่ปุ่น 3','Japanese Language 3',1,'1(0-3-1)'),
 ('945-1109','ภาษาเยอรมัน 3','German Language 3',1,'1(0-3-1)'),
 ('946-1103','ภาษาฝรั่งเศส 3','French Language 3',1,'1(0-3-1)'),
 ('310-2308','ปฏิสัมพันธ์ระหว่างคอมพิวเตอร์กับมนุษย์','Computer-Human Interactions',3,'3(3-0-6)'),
 ('310-2309','ระบบฐานข้อมูล','Database Systems',3,'3(3-0-6)'),
 ('310-2311','การคำนวณแบบกลุ่มเมฆ','Cloud Computing',3,'3(3-0-6)'),
 ('310-3416','การวิเคราะห์และการออกแบบขั้นตอนวิธี','Analysis and Design of Algorithms',3,'3(3-0-6)'),
 ('310-3419','การดูแลบริหารจัดการข้อมูล','Data Curation, Management, and Organization',3,'3(3-0-6)'),
 ('312-3302','ปัญญาประดิษฐ์','Artificial Intelligence',3,'3(3-0-6)'),
 ('310-3313','หัวข้อคัดสรรด้านวิศวกรรมคอมพิวเตอร์ 2','Selected Topics in Computer Engineering 2',3,'3(3-0-6)'),
 ('910-1116','การคิดสร้างสรรค์เพื่อสังคม','Creative Thinking for Society',3,'3(3-0-6)'),
 ('100-2102','การเงินธุรกิจ','Business Finance',3,'3(3-0-6)');

-- ตัวอย่างประกอบการสาธิต (ไม่ได้มาจาก reg)
INSERT INTO prerequisite VALUES ('310-3416', '310-2101');

-- แผนการเรียน CPE63 (เข้าปี 2567): (ชั้นปี, เทอม)
INSERT INTO study_plan (curriculum_id, course_code, year_level, semester, is_required) VALUES
 ('CPE63','300-1101',1,1,1),('CPE63','300-1103',1,1,1),('CPE63','300-1104',1,1,1),
 ('CPE63','300-1107',1,1,1),('CPE63','920-1135',1,1,1),('CPE63','920-1136',1,1,1),
 ('CPE63','931-1107',1,1,1),('CPE63','942-1101',1,1,1),
 ('CPE63','300-1102',1,2,1),('CPE63','300-1105',1,2,1),('CPE63','300-1106',1,2,1),
 ('CPE63','310-2101',1,2,1),
 ('CPE63','300-1208',2,1,1),('CPE63','300-1209',2,1,1),('CPE63','300-1210',2,1,1),
 ('CPE63','310-2202',2,1,1),('CPE63','310-2203',2,1,1),
 ('CPE63','300-1211',2,2,1),('CPE63','310-2204',2,2,1),('CPE63','310-2205',2,2,1),
 ('CPE63','310-2206',2,2,1),('CPE63','310-3312',2,2,1),('CPE63','942-1108',2,2,1),
 ('CPE63','310-2307',3,1,1),('CPE63','310-2310',3,1,1),('CPE63','310-3311',3,1,1),
 ('CPE63','311-3303',3,1,1),('CPE63','311-3304',3,1,1),('CPE63','941-1102',3,1,1),
 ('CPE63','942-1112',3,1,1),('CPE63','942-1113',3,1,1),
 ('CPE63','943-1109',3,1,0),('CPE63','944-1109',3,1,0),('CPE63','945-1109',3,1,0),
 ('CPE63','946-1103',3,1,0),   -- ภาษาที่ 3 เลือก 1 ภาษา
 ('CPE63','310-2308',3,2,1),('CPE63','310-2309',3,2,1),('CPE63','310-2311',3,2,1),
 ('CPE63','310-3416',3,2,1),('CPE63','310-3419',3,2,1),('CPE63','312-3302',3,2,1);

INSERT INTO instructor (instructor_id, full_name) VALUES
 (1,'ผศ.ดร.ดำรงค์ฤทธิ์ เศรษฐ์ศิริโชค'),(2,'อ.พงษ์พันธ์ สุริยภัทร'),
 (3,'รศ.ดร.อานนท์ รุ่งสว่าง'),(4,'รศ.ดร.วรา วราวิทย์'),
 (5,'ผศ.ดร.วรัญญู วงษ์เสรี'),(6,'อ.กฤษฎา พรหมสุทธิรักษ์'),
 (7,'อ.ชยันต์ คงทองวัฒนา'),(8,'ผศ.ดร.จเร สิงหโกวินท์'),
 (9,'ผศ.ดร.พรพิพัฒน์ จูฑา'),(10,'อ.วัฒนา หินไชยศรี');

INSERT INTO room (room_code) VALUES ('15208'),('15303'),('15312'),('15309'),('5427'),('4315');

-- section ภาค 2/2569 (จำนวนรับตาม reg)
INSERT INTO section (section_id, course_code, term_id, section_no, capacity) VALUES
 (1,'310-2205','2569-2','01',50),
 (2,'310-2308','2569-2','01',45),
 (3,'310-2309','2569-2','01',50),
 (4,'310-2311','2569-2','01',50),
 (5,'310-3416','2569-2','01',50),
 (6,'312-3302','2569-2','01',30),
 (7,'310-3313','2569-2','01',21),
 (8,'910-1116','2569-2','01',40),
 (9,'100-2102','2569-2','01',36),   -- ห้องเดียวกัน แต่ reg แยกเป็น :65 รับ 30 และ :69 รับ 6
 (10,'310-3419','2569-2','01',20);
-- 910-1116 ใส่เฉพาะกลุ่ม 01 (reg ระบุ "เฉพาะ 67วค.") ส่วนกลุ่ม 02 และ 03 ไม่ได้ใส่ เพราะกลุ่ม 03 จำกัดตามกลุ่มเรียน
-- ("เฉพาะ 69กว." รับ 4 คน เต็มแล้ว) ซึ่ง section_quota ที่จำกัดตามหลักสูตรยังรองรับไม่ได้

INSERT INTO section_quota VALUES (9,'BBA65',30),(9,'BBA69',6);

INSERT INTO section_instructor VALUES (1,1),(2,2),(3,3),(4,4),(5,5),(6,6),(7,7),(8,8),(9,9),(10,10);

INSERT INTO class_meeting (section_id, day_of_week, start_time, end_time, room_code) VALUES
 (1,3,'09:00','12:00','15208'),
 (2,2,'13:00','16:00','15303'),
 (3,3,'13:00','16:00','15312'),
 (4,1,'08:00','09:00','15208'),(4,2,'08:00','09:00','15208'),(4,4,'08:00','09:00','15208'),
 (5,4,'09:00','12:00','15312'),
 (6,1,'09:00','12:00','15309'),
 (7,1,'09:00','12:00','15208'),
 (8,2,'09:00','12:00','5427'),
 (9,3,'09:00','12:00','4315'),
 (10,3,'09:00','12:00','15312');

-- 310-3313: reg ยังไม่ประกาศวันสอบปลายภาค จึงไม่มีแถว (วันสอบสมมุติของวิชานี้ใช้เฉพาะใน demo.sql ข้อ D3)
INSERT INTO exam (section_id, exam_type, exam_date, start_time, end_time) VALUES
 (1,'FINAL','2027-03-01','09:00','12:00'),
 (2,'FINAL','2027-03-03','09:00','12:00'),
 (3,'FINAL','2027-03-09','09:00','12:00'),
 (4,'FINAL','2027-03-04','09:00','12:00'),
 (5,'FINAL','2027-03-11','09:00','12:00'),
 (6,'FINAL','2027-03-09','13:00','16:00'),
 (8,'FINAL','2027-03-04','13:00','16:00'),
 (9,'FINAL','2027-03-01','09:00','12:00'),
 (10,'FINAL','2027-03-08','09:00','12:00');

------------------------------------------------------------------
-- นักศึกษา CPE63 รุ่น 2567 (สมมุติ)
------------------------------------------------------------------
INSERT INTO student VALUES
 ('6799000001','ก้อง','สมมุติ','CPE63',2567),   -- สถานการณ์เดียวกับเจ้าของโปรเจกต์
 ('6799000002','บี','สมมุติ','CPE63',2567),
 ('6799000003','ซี','สมมุติ','CPE63',2567),
 ('6799000004','ดี','สมมุติ','CPE63',2567),
 ('6799000005','อี','สมมุติ','CPE63',2567);

-- ผลการเรียน: ผ่านวิชาบังคับในแผนทุกตัวจนถึง 1/2569 + ภาษาญี่ปุ่น 3
INSERT INTO transcript (student_id, course_code, term_id, grade)
SELECT s.student_id, sp.course_code,
       (s.entry_year + sp.year_level - 1) || '-' || sp.semester, 'B'
FROM student s
JOIN study_plan sp ON sp.curriculum_id = s.curriculum_id
WHERE s.curriculum_id = 'CPE63'
  AND (sp.is_required = 1 OR sp.course_code = '944-1109')
  AND (sp.year_level < 3 OR (sp.year_level = 3 AND sp.semester = 1));

-- คนที่ 1 ไม่ได้ลง 310-2205 ตามแผน 2/2568 จึงเป็นวิชาค้าง
DELETE FROM transcript WHERE student_id = '6799000001' AND course_code = '310-2205';

-- ลงทะเบียน 2/2569 (ผ่าน trigger ทุกแถว)
-- คนที่ 1: ลงเหมือนของจริงทั้ง 7 วิชา (วิชาตามแผนที่ลงไม่ได้คือ 310-3419 และ 312-3302 ดู demo.sql ข้อ D1, D2)
INSERT INTO enrollment (student_id, section_id) VALUES
 ('6799000001',1),('6799000001',2),('6799000001',3),('6799000001',4),('6799000001',5),('6799000001',7),('6799000001',8),
 ('6799000002',2),('6799000002',3),('6799000002',4),('6799000002',5),('6799000002',6),
 ('6799000003',2),('6799000003',3),('6799000003',4),('6799000003',5),
 ('6799000004',2),('6799000004',4),('6799000004',5),('6799000004',6),
 ('6799000005',2),('6799000005',3);

------------------------------------------------------------------
-- เติมนักศึกษาจำลองให้จำนวนลงทะเบียนเท่ากับใน reg
------------------------------------------------------------------
CREATE TEMP TABLE num (i INTEGER PRIMARY KEY);
WITH RECURSIVE n(i) AS (SELECT 1 UNION ALL SELECT i + 1 FROM n WHERE i < 300)
INSERT INTO num SELECT i FROM n;

INSERT INTO student SELECT printf('F%04d', i), 'จำลอง', i, 'EXT', 2566 FROM num;
INSERT INTO student SELECT printf('B65%02d', i), 'บธ65', i, 'BBA65', 2565 FROM num WHERE i <= 15;
INSERT INTO student SELECT printf('B69%02d', i), 'บธ69', i, 'BBA69', 2569 FROM num WHERE i <= 7;

-- คนเติมที่จะลง 310-3416 ต้องผ่านวิชาบังคับก่อน
INSERT INTO transcript SELECT printf('F%04d', i), '310-2101', '2567-2', 'C' FROM num WHERE i BETWEEN 119 AND 158;

-- แต่ละช่วงลง section เดียว: จำนวนในวงเล็บ = เป้าใน reg ลบคนสมมุติด้านบน
INSERT INTO enrollment SELECT printf('F%04d', i), 1, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN   1 AND  46; -- 47
INSERT INTO enrollment SELECT printf('F%04d', i), 2, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN  47 AND  81; -- 40
INSERT INTO enrollment SELECT printf('F%04d', i), 3, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN  82 AND 118; -- 41
INSERT INTO enrollment SELECT printf('F%04d', i), 5, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 119 AND 158; -- 44
INSERT INTO enrollment SELECT printf('F%04d', i), 4, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 159 AND 196; -- 42
INSERT INTO enrollment SELECT printf('F%04d', i), 6, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 197 AND 215; -- 21
INSERT INTO enrollment SELECT printf('F%04d', i), 7, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 216 AND 235; -- 21 (เต็ม)
INSERT INTO enrollment SELECT printf('F%04d', i), 8, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 236 AND 270; -- 36
INSERT INTO enrollment SELECT printf('F%04d', i), 10, '2026-10-29 09:00:00' FROM num WHERE i BETWEEN 271 AND 286; -- 16

-- 100-2102: โควตา :69 เต็ม 6/6 ขณะที่ :65 ใช้ไป 15/30 (ตรงกับใน reg)
INSERT INTO enrollment SELECT printf('B65%02d', i), 9, '2026-10-29 09:00:00' FROM num WHERE i <= 15;
INSERT INTO enrollment SELECT printf('B69%02d', i), 9, '2026-10-29 09:00:00' FROM num WHERE i <= 6;

DROP TABLE num;

-- เก็บประวัติไว้เฉพาะของนักศึกษาสมมุติหลัก
DELETE FROM registration_log WHERE student_id NOT LIKE '6799%';

------------------------------------------------------------------
-- หมวดวิชาและลำดับการจัดตาราง
--   service  = วิชาศึกษาทั่วไป (9xx) และวิชาพื้นฐานวิศวกรรม (300-xxxx) ที่เรียนร่วมหลายสาขา
--   core     = วิชาบังคับในแผนการเรียน
--   elective = วิชาเลือกในแผน และ 310-3313 (หัวข้อคัดสรร)
--   regular  = อื่นๆ เช่น 100-2102 ที่ไม่อยู่ในแผนของ CPE63
------------------------------------------------------------------
UPDATE course SET course_category = 'service' WHERE course_code GLOB '9*' OR course_code GLOB '300-*';
UPDATE course SET course_category = 'core'
WHERE course_category = 'regular'
  AND course_code IN (SELECT course_code FROM study_plan WHERE is_required = 1);
UPDATE course SET course_category = 'elective'
WHERE course_category = 'regular'
  AND (course_code IN (SELECT course_code FROM study_plan WHERE is_required = 0) OR course_code = '310-3313');

-- 910-1116 (วิชาส่วนกลาง) จัดและล็อกไว้ก่อนเปิดภาค ส่วนกลุ่มอื่นยังไม่ล็อก
INSERT INTO scheduling_priority (section_id, priority, is_locked, lock_reason, locked_at) VALUES
 (8, 1, 1, 'วิชาศึกษาทั่วไป เรียนร่วมหลายคณะ', '2026-10-15 09:00:00');

INSERT INTO scheduling_priority (section_id, priority)
SELECT s.section_id,
       CASE c.course_category WHEN 'service' THEN 5 WHEN 'core' THEN 20 WHEN 'elective' THEN 40 ELSE 50 END
FROM section s
JOIN course c ON c.course_code = s.course_code
WHERE s.section_id <> 8;

-- ข้อมูลตั้งต้นของตารางไม่ใช่การแก้ตาราง จึงไม่เก็บใน schedule_log
DELETE FROM schedule_log;

------------------------------------------------------------------
-- บัญชีผู้ใช้สำหรับทดสอบ (ข้อมูลสมมุติ ใช้ในเครื่องเท่านั้น)
-- ทุกบัญชีใช้รหัสผ่านทดสอบเดียวกัน: demo1234 (เก็บเป็น hash แบบ pbkdf2)
--   admin        ฝ่ายทะเบียน
--   scheduler    อาจารย์ผู้จัดตาราง (ผูกกับอาจารย์ id 2)
--   6799000001…5 และ B6501…, B6901… นักศึกษา (username = รหัสนักศึกษา)
------------------------------------------------------------------
INSERT INTO app_user (username, password_hash, role, student_id, instructor_id) VALUES
 ('admin',     'pbkdf2:sha256:600000$o3hUhHVS1HJqZDue$719e5cfcd8eaacfe520dac5e99025a461071f40123394dd01ac36ea0a646532e', 'admin',     NULL, NULL),
 ('scheduler', 'pbkdf2:sha256:600000$o3hUhHVS1HJqZDue$719e5cfcd8eaacfe520dac5e99025a461071f40123394dd01ac36ea0a646532e', 'scheduler', NULL, 2);
INSERT INTO app_user (username, password_hash, role, student_id)
SELECT student_id, 'pbkdf2:sha256:600000$o3hUhHVS1HJqZDue$719e5cfcd8eaacfe520dac5e99025a461071f40123394dd01ac36ea0a646532e', 'student', student_id
FROM student WHERE curriculum_id <> 'EXT'
ORDER BY student_id;

-- 910-1116 ถูกล็อกโดยอาจารย์ผู้จัดตาราง (ใส่หลังสร้างบัญชีผู้ใช้ เพราะตอนล็อกข้างบนยังไม่มีบัญชี)
UPDATE scheduling_priority
   SET locked_by_user_id = (SELECT user_id FROM app_user WHERE username = 'scheduler')
 WHERE section_id = 8;

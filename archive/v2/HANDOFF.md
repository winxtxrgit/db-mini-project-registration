# 📘 HANDOFF.md — คู่มือส่งต่องานสถาปัตยกรรมระบบฐานข้อมูลและการจัดตารางเรียน
## Study Plan–Aware Registration & Scheduling System (CDTI 2/2569)

> **สำหรับ AI / นักพัฒนาตัวถัดไป:**  
> กรุณาอ่านเอกสารนี้เป็นอันดับแรกเพื่อทำความเข้าใจบริบทที่ถูกต้องของงานทั้งหมด ทั้งในแง่ของระบบฐานข้อมูลหลัก (Core Backend Database) และแนวทางการออกแบบ UI จัดการตารางเรียน (UI Reference)

---

## 🧭 1. สาระสำคัญและเจตนารมณ์ที่แท้จริงของโปรเจกต์ (Project Intent & Mental Model)

โปรเจกต์หลักจริง ๆ ของเราคือ **`Mini_Project_PlanA`** ซึ่งเป็น **ระบบหลังบ้าน (Backend Database System)** สำหรับวิชาระบบฐานข้อมูล (Database Systems) สถาบัน CDTI ภาค 2/2569 โดยมีเป้าหมายคือ:
> **"ระบบวางแผนและตรวจสอบการลงทะเบียนตามแผนการเรียน และสนับสนุนฝ่ายจัดตารางเรียน/จัดสอบ"**

### แล้วโฟลเดอร์ `timetable-reconstruction/` คืออะไร?
- **`timetable-reconstruction/` ไม่ใช่โปรเจกต์แยก และไม่ใช่ระบบที่ต้องพัฒนาขนานกัน**
- มันคือ **"แนวทางการออกแบบ UI/UX Reference"** ที่เราไป Reverse Engineer มาจากเว็บจริง (`tarangrian.com`)
- **บทบาทของมัน:** นำมาเป็นต้นแบบไอเดียหน้าจอแสดงผล ให้เห็นภาพว่าหน้าจอของ **"เจ้าหน้าที่ฝ่ายจัดตารางเรียน/จัดสอบ (Admin/Staff Scheduler)"** จะมีหน้าตาและ Interaction แบบใด เช่น การลากวางคาบ (5 วัน x 10 คาบ), การแสดง Progress bar ชั่วโมงที่จัด, การตรวจจับ Conflict แบบเรียลไทม์ และระบบผู้ช่วยจัดตาราง เพื่อนำมาเป็นโจทย์ในการออกแบบ Schema / Trigger / View ในฝั่งฐานข้อมูล `Mini_Project_PlanA` ให้รองรับการทำงานของหน้าบ้านแบบนี้ได้จริง!

---

## 🧩 2. ความต้องการใหม่ที่ต้องเพิ่มและแก้ไขลงใน `Mini_Project_PlanA` (Core Requirements)

จากเงื่อนไขการทำงานจริงของสถาบัน CDTI และความต้องการล่าสุด มีขั้นตอนและฟีเจอร์สำคัญที่ต้องบรรจุลงในฐานข้อมูล ดังนี้:

### ลำดับขั้นตอนการจัดตาราง (Scheduling Workflow):
1. **ล็อก "วิชาส่วนกลาง" ก่อน (Service Courses):**
   - เช่น วิชาพื้นฐานที่เรียนรวมกันหลายสาขา/คณะ (คณิตศาสตร์, ฟิสิกส์, ภาษาอังกฤษ, วิชาศึกษาทั่วไป)
   - กลุ่มนี้ขยับยากที่สุดและกระทบคนหมู่มาก จึงต้องถูกกำหนดช่วงเวลาและ "ล็อก (Locked)" ไว้ในตารางเป็นลำดับแรก
2. **วาง "วิชาบังคับประจำสาขา":**
   - นำตารางของแต่ละสาขามาวางแทรกในช่องว่างที่เหลือ โดยอิงความสะดวก/เวลาว่างของอาจารย์ประจำภาควิชา

---

### 🌟 4 ฟีเจอร์หลักที่สรุปไว้ชัดเจน (Checklist ที่ต้องมีในระบบ):

#### 1. ระบบตรวจสอบความว่างของอาจารย์ (Instructor Availability & Warning)
- อาจารย์ในคณะต้องสามารถส่งช่วงเวลาที่ว่าง/ไม่ว่างได้ก่อนเปิดเทอม
- ขณะที่ฝ่ายจัดตารางกำลังวางวิชา หากเลือกช่วงเวลาที่อาจารย์ **ไม่ว่าง** ระบบต้อง:
  - เตือนด้วยสถานะหรือไฮไลต์สีแดง (Alert/Warning)
  - ห้ามวางทับ หรือขึ้นคำเตือนชัดเจนใน View/Query

#### 2. ระบบตรวจสอบห้องเรียนและห้องสอบไม่ให้ซ้ำ (Room Conflict Prevention)
- ในปัจจุบันตาราง `class_meeting` และ `exam` มีคอลัมน์ `room_code` แล้ว แต่ยังขาด Trigger ตรวจสอบ
- **ต้องสร้าง Trigger บล็อกทันที:** หากห้องถูกจองซ้ำในวันและช่วงเวลาเดียวกัน ทั้งเวลาเรียน (`class_meeting`) และเวลาสอบ (`exam`)
- มี View สำหรับค้นหาห้องที่ว่างตามช่วงเวลาที่กำหนด

#### 3. ภาพรวมตารางเรียนข้ามปี (Cross-Year Schedule Matrix) & การจัดวิชาเรียนซ้ำ/เรียนแก้
- ฝ่ายจัดตารางต้องมองเห็นภาพรวมของตารางเรียนทุกชั้นปี (เช่น วันจันทร์ 9:00–12:00 ปี 1 กับ ปี 2 เรียนอะไรกันอยู่บ้าง)
- **การทับซ้อนกันของชั้นปี:**
  - เป็นเรื่องปกติที่ปี 1 กับปี 2 จะเรียนเวลาเดียวกันได้ในคนละห้อง
  - **ยกเว้น:** กรณีที่ต้องจัดวิชาให้นักศึกษารุ่นพี่ลง "เรียนซ้ำ/เรียนแก้" พร้อมกับรุ่นน้อง จะต้องไม่ชนกับวิชาบังคับในแผนของรุ่นพี่
- **แนวทาง UI/Query:**
  - ต้องมี View แสดงผลว่าเวลานี้มีปีไหนเรียนบ้าง
  - มีเงื่อนไขการกรอง (Filter หรือปุ่มเปิด-ปิดแต่ละชั้นปี เช่น สวิตช์ ปี 1, ปี 2, ปี 3, ปี 4) เพื่อให้ฝ่ายจัดตารางเลือกเปิดดูเฉพาะปีที่เกี่ยวข้องเพื่อจัดวิชาเรียนซ้ำไม่ให้ชน

#### 4. ระบบจัดเวลาสอบไม่ให้ซ้ำกัน (Exam Scheduling System)
- ตารางสอบของนักศึกษาแต่ละคนต้องไม่ชนกัน
- ป้องกันการจัดห้องสอบชนกันในวันและเวลาเดียวกัน
- ระบบต้องมีรายงานเตือน:
  - 🔴 เวลาสอบชนกันโดยตรง (Hard Constraint ห้ามเกิดขึ้น)
  - 🟡 นักศึกษาคนเดียวกันต้องสอบ 2 วิชาขึ้นไปในวันเดียวกัน (แจ้งเตือนล่วงหน้า)
  - ค้นหาห้องสอบที่ว่างตามความจุ (Capacity) ของกลุ่มเรียน

---

## 📂 3. โครงสร้างไฟล์ในแพ็กเกจนี้

```
Database/
├── Mini_Project_PlanA/                    ← 🎯 [CORE PROJECT] โปรเจกต์หลักฐานข้อมูล SQLite
│   ├── HANDOFF.md                         ← [อ่านไฟล์นี้] สรุป Roadmap และข้อกำหนดทั้งหมด
│   ├── README.md                          ← สรุปภาพรวมและ ER diagram ฉบับเดิม
│   ├── Project_Proposal_TH.txt            ← ข้อเสนอโครงงานฉบับส่งอาจารย์
│   ├── schema.sql                         ← โครงสร้าง DB เดิม (18 ตาราง, 8 views, 5 triggers)
│   ├── seed.sql                           ← ข้อมูลตั้งต้นจริงเทอม 2/2569 (วิชา, แผน, นศ.สมมุติ)
│   ├── queries.sql                        ← รายงาน R1–R6 เดิม
│   ├── demo.sql                           ← สคริปต์ Demo D1–D10 เดิม
│   ├── run.sql                            ← สคริปต์รัน SQLite เดิม
│   ├── schema_v2.sql                      ← 🔴 [งานที่ต้องทำ] Schema ส่วนขยายสำหรับ 4 ฟีเจอร์ใหม่
│   ├── queries_v2.sql                     ← 🔴 [งานที่ต้องทำ] รายงาน R7–R10 ใหม่
│   ├── demo_v2.sql                        ← 🔴 [งานที่ต้องทำ] สคริปต์สาธิตระบบใหม่
│   └── Diagrams/
│       ├── registration-er.drawio         ← แผนภาพ ER เดิม
│       └── registration-er.png            ← รูปภาพ ER เดิม
│
└── timetable-reconstruction/              ← 🎨 [UI / INTERACTION REFERENCE]
    │   (แบบจำลองและเอกสารอ้างอิงจากเว็บ tarangrian.com สำหรับศึกษาหน้าตาการใช้งานของฝ่ายจัดตาราง)
    ├── src/
    │   ├── types/schedule.ts              ← ตัวอย่าง Data Model ของตารางสอนและ Conflict
    │   └── lib/stores/
    │       ├── conflictIndex.ts           ← ตัวอย่าง Logic ตรวจจับ Conflict แบบ Multi-dimensional (O(1))
    │       └── timetableStore.ts          ← ตัวอย่าง State Management หน้าตาราง
    ├── prisma/schema.prisma               ← ตัวอย่าง Schema แบบ RDBMS สมัยใหม่
    └── python-solver/solver.py            ← ตัวอย่างอัลกอริทึม Constraint Solver (OR-Tools)
```

---

## 🛠️ 4. แผนงานและโค้ด SQL ที่ต้องนำไปสร้างต่อใน `Mini_Project_PlanA`

ให้สร้างไฟล์ใหม่เพื่อไม่ให้กระทบไฟล์เดิม:
1. `schema_v2.sql`
2. `queries_v2.sql`
3. `demo_v2.sql`
4. `run_v2.sql`

ด้านล่างนี้คือโครงสร้าง SQL ที่ออกแบบไว้รองรับ Requirements ครบถ้วน:

### 4.1 ขยายฐานข้อมูล `schema_v2.sql`

```sql
PRAGMA foreign_keys = ON;

------------------------------------------------------------------
-- 1. อัปเดตตาราง room และ course
------------------------------------------------------------------
ALTER TABLE room ADD COLUMN room_name TEXT;
ALTER TABLE room ADD COLUMN building TEXT;
ALTER TABLE room ADD COLUMN floor_no INTEGER;
ALTER TABLE room ADD COLUMN room_type TEXT DEFAULT 'lecture'
    CHECK (room_type IN ('lecture','lab','computer','exam_hall','multipurpose'));
ALTER TABLE room ADD COLUMN is_exam_room INTEGER DEFAULT 0 CHECK (is_exam_room IN (0,1));

-- เพิ่มหมวดวิชาเพื่อแยกล็อกวิชาส่วนกลาง (Service Course)
ALTER TABLE course ADD COLUMN course_category TEXT DEFAULT 'regular'
    CHECK (course_category IN ('service','core','elective','regular'));

------------------------------------------------------------------
-- 2. ระบบให้อาจารย์ส่งเวลาว่าง (Instructor Availability)
------------------------------------------------------------------
CREATE TABLE instructor_availability (
    avail_id      INTEGER PRIMARY KEY AUTOINCREMENT,
    instructor_id INTEGER NOT NULL REFERENCES instructor(instructor_id),
    term_id       TEXT    NOT NULL REFERENCES term(term_id),
    day_of_week   INTEGER NOT NULL CHECK (day_of_week BETWEEN 1 AND 7), -- 1=จันทร์ .. 7=อาทิตย์
    start_time    TEXT    NOT NULL,
    end_time      TEXT    NOT NULL,
    status        TEXT    NOT NULL DEFAULT 'available'
        CHECK (status IN ('available','unavailable','preferred','locked')),
    note          TEXT,
    submitted_at  DATETIME DEFAULT CURRENT_TIMESTAMP,
    UNIQUE (instructor_id, term_id, day_of_week, start_time, end_time),
    CHECK (start_time < end_time)
);

-- View รวมเวลาที่อาจารย์ไม่ว่าง (ทั้งมีตารางสอนอยู่แล้ว + แจ้งว่าไม่ว่าง)
CREATE VIEW v_instructor_busy AS
SELECT si.instructor_id, i.full_name,
       cm.day_of_week, cm.start_time, cm.end_time,
       s.course_code, s.section_no, 'teaching' AS busy_type
FROM section_instructor si
JOIN class_meeting cm ON cm.section_id = si.section_id
JOIN section       s  ON s.section_id  = si.section_id
JOIN instructor    i  ON i.instructor_id = si.instructor_id
JOIN term          t  ON t.term_id = s.term_id AND t.is_current = 1
UNION ALL
SELECT ia.instructor_id, i.full_name,
       ia.day_of_week, ia.start_time, ia.end_time,
       NULL, NULL, ia.status
FROM instructor_availability ia
JOIN instructor i ON i.instructor_id = ia.instructor_id
JOIN term       t ON t.term_id = ia.term_id AND t.is_current = 1
WHERE ia.status IN ('unavailable','locked');

------------------------------------------------------------------
-- 3. ตารางลำดับความสำคัญและการล็อกวิชา (Service Course Locking)
------------------------------------------------------------------
CREATE TABLE scheduling_priority (
    priority_id  INTEGER PRIMARY KEY AUTOINCREMENT,
    term_id      TEXT    NOT NULL REFERENCES term(term_id),
    section_id   INTEGER NOT NULL REFERENCES section(section_id),
    priority     INTEGER NOT NULL DEFAULT 50, -- 1-10=Service, 11-30=Core, 31-50=Elective
    is_locked    INTEGER NOT NULL DEFAULT 0 CHECK (is_locked IN (0,1)),
    lock_reason  TEXT,
    locked_by    TEXT,
    locked_at    DATETIME,
    UNIQUE (term_id, section_id)
);

------------------------------------------------------------------
-- 4. Triggers ป้องกันห้องเรียนและห้องสอบซ้ำ (Room Conflict Triggers)
------------------------------------------------------------------
CREATE TRIGGER trg_class_meeting_room_conflict
BEFORE INSERT ON class_meeting
WHEN NEW.room_code IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'ห้องเรียนนี้ถูกจองในวันและเวลาเดียวกันแล้ว')
    WHERE EXISTS (
        SELECT 1 FROM class_meeting cm
        WHERE cm.room_code   = NEW.room_code
          AND cm.day_of_week = NEW.day_of_week
          AND cm.start_time  < NEW.end_time
          AND NEW.start_time < cm.end_time
          AND cm.meeting_id != COALESCE(NEW.meeting_id, -1)
    );
END;

CREATE TRIGGER trg_exam_room_conflict
BEFORE INSERT ON exam
WHEN NEW.room_code IS NOT NULL
BEGIN
    SELECT RAISE(ABORT, 'ห้องสอบนี้ถูกจองในวันและเวลาเดียวกันแล้ว')
    WHERE EXISTS (
        SELECT 1 FROM exam ex
        WHERE ex.room_code  = NEW.room_code
          AND ex.exam_date  = NEW.exam_date
          AND ex.start_time < NEW.end_time
          AND NEW.start_time < ex.end_time
          AND ex.exam_id   != COALESCE(NEW.exam_id, -1)
    );
END;

------------------------------------------------------------------
-- 5. View สำหรับฝ่ายจัดตารางมองเห็นภาพรวมข้ามปี (Cross-Year Overview)
------------------------------------------------------------------
CREATE VIEW v_schedule_overview AS
SELECT
    cm.day_of_week,
    cm.start_time,
    cm.end_time,
    s.course_code,
    c.name_th           AS course_name,
    s.section_no,
    cm.room_code,
    i.full_name         AS instructor_name,
    cu.curriculum_id,
    sp.year_level,
    sp.semester         AS plan_semester,
    COUNT(e.student_id) AS enrolled_count,
    s.capacity
FROM class_meeting cm
JOIN section  s   ON s.section_id    = cm.section_id
JOIN course   c   ON c.course_code   = s.course_code
JOIN term     t   ON t.term_id       = s.term_id AND t.is_current = 1
LEFT JOIN section_instructor si ON si.section_id = s.section_id
LEFT JOIN instructor         i  ON i.instructor_id = si.instructor_id
LEFT JOIN enrollment         e  ON e.section_id   = s.section_id
LEFT JOIN student            st ON st.student_id  = e.student_id
LEFT JOIN study_plan         sp ON sp.course_code = s.course_code
                                AND sp.curriculum_id = st.curriculum_id
LEFT JOIN curriculum         cu ON cu.curriculum_id = st.curriculum_id
GROUP BY cm.day_of_week, cm.start_time, cm.end_time, s.section_id, sp.year_level, cu.curriculum_id;

------------------------------------------------------------------
-- 6. View สำหรับตรวจสอบตารางสอบภาพรวมสถาบัน
------------------------------------------------------------------
CREATE VIEW v_exam_schedule_full AS
SELECT
    ex.exam_date,
    ex.start_time || '–' || ex.end_time AS time_slot,
    ex.exam_type,
    ex.room_code,
    r.capacity          AS room_capacity,
    s.course_code,
    c.name_th           AS course_name,
    s.section_no,
    COUNT(e.student_id) AS student_count,
    i.full_name         AS instructor_name
FROM exam ex
JOIN section  s  ON s.section_id    = ex.section_id
JOIN course   c  ON c.course_code   = s.course_code
JOIN term     t  ON t.term_id       = s.term_id AND t.is_current = 1
LEFT JOIN room r ON r.room_code     = ex.room_code
LEFT JOIN enrollment e ON e.section_id = s.section_id
LEFT JOIN section_instructor si ON si.section_id = s.section_id
LEFT JOIN instructor i ON i.instructor_id = si.instructor_id
GROUP BY ex.exam_id;
```

---

### 4.2 รายงานและการสอบถามใหม่ `queries_v2.sql`

```sql
-- R7: ตรวจสอบความพร้อมของอาจารย์ (Dashboard อาจารย์ว่าง/ไม่ว่าง ณ ช่วงเวลาที่จะจัด)
-- แทนค่า: day_of_week, slot_start, slot_end ที่ต้องการวางคาบ
WITH target_slot AS (
    SELECT 1 AS day_of_week, '09:00' AS slot_start, '12:00' AS slot_end
),
busy_instructors AS (
    SELECT DISTINCT instructor_id FROM v_instructor_busy
    WHERE day_of_week = (SELECT day_of_week FROM target_slot)
      AND start_time  < (SELECT slot_end   FROM target_slot)
      AND end_time    > (SELECT slot_start FROM target_slot)
)
SELECT
    i.instructor_id,
    i.full_name,
    CASE WHEN b.instructor_id IS NOT NULL THEN '🔴 ไม่ว่าง (ติดสอน/ติดธุระ)' ELSE '🟢 ว่าง' END AS availability_status
FROM instructor i
LEFT JOIN busy_instructors b ON b.instructor_id = i.instructor_id
ORDER BY availability_status DESC, i.full_name;

-- R8: ภาพรวมตารางเรียนข้ามปี (Cross-Year Timetable Matrix)
-- สำหรับเจ้าหน้าที่ใช้ดูเพื่อจัดวิชาเรียนซ้ำ/เรียนแก้
-- ปรับค่า WHERE year_level IN (...) เพื่อจำลองการเปิด/ปิดปุ่ม Toggle ชั้นปีในหน้าจอ
SELECT
    CASE day_of_week
        WHEN 1 THEN 'จันทร์' WHEN 2 THEN 'อังคาร' WHEN 3 THEN 'พุธ'
        WHEN 4 THEN 'พฤหัสบดี' WHEN 5 THEN 'ศุกร์' WHEN 6 THEN 'เสาร์' ELSE 'อาทิตย์'
    END AS day_name,
    start_time || '–' || end_time AS time_slot,
    course_code,
    course_name,
    section_no,
    'ปี ' || COALESCE(year_level, '-') AS student_year,
    curriculum_id,
    enrolled_count,
    room_code,
    instructor_name
FROM v_schedule_overview
WHERE year_level IN (1, 2, 3, 4) -- Toggle Filter: สามารถเลือกดูเฉพาะ ปี 1 กับ ปี 2 เพื่อจัดวิชาแก้ได้
ORDER BY day_of_week, start_time, year_level;

-- R9: ตรวจสอบการสอบซ้อนวันของนักศึกษา (Exam Load Warning)
SELECT
    e1.student_id,
    st.first_name || ' ' || st.last_name AS student_name,
    ex1.exam_date,
    c1.name_th AS course_1,
    ex1.start_time || '–' || ex1.end_time AS time_1,
    c2.name_th AS course_2,
    ex2.start_time || '–' || ex2.end_time AS time_2,
    CASE
        WHEN ex1.start_time < ex2.end_time AND ex2.start_time < ex1.end_time
        THEN '🔴 สอบชนกันตรงๆ (ต้องแก้ไขตารางสอบด่วน)'
        ELSE '🟡 สอบหลายวิชาในวันเดียวกัน (แจ้งเตือน นศ.)'
    END AS conflict_severity
FROM enrollment e1
JOIN enrollment e2 ON e1.student_id = e2.student_id AND e1.section_id < e2.section_id
JOIN exam ex1 ON ex1.section_id = e1.section_id
JOIN exam ex2 ON ex2.section_id = e2.section_id
             AND ex2.exam_date = ex1.exam_date
             AND ex2.exam_type = ex1.exam_type
JOIN section s1 ON s1.section_id = e1.section_id
JOIN section s2 ON s2.section_id = e2.section_id
JOIN course c1 ON c1.course_code = s1.course_code
JOIN course c2 ON c2.course_code = s2.course_code
JOIN student st ON st.student_id = e1.student_id
ORDER BY ex1.exam_date, e1.student_id;

-- R10: ค้นหาห้องสอบที่ยังว่างในวันและเวลาที่กำหนด (Available Exam Rooms)
SELECT r.room_code, r.room_name, r.capacity, r.room_type
FROM room r
WHERE r.is_exam_room = 1
  AND r.room_code NOT IN (
      SELECT ex.room_code FROM exam ex
      JOIN section s ON s.section_id = ex.section_id
      JOIN term    t ON t.term_id = s.term_id AND t.is_current = 1
      WHERE ex.exam_date  = '2570-03-04'
        AND ex.start_time < '12:00'
        AND ex.end_time   > '09:00'
        AND ex.room_code  IS NOT NULL
  )
ORDER BY r.capacity DESC;
```

---

## 🚀 5. Checklist คำสั่งส่งต่องาน (สิ่งที่ AI ตัวถัดไปต้องทำทันที)

1. อ่านไฟล์ **`Mini_Project_PlanA/HANDOFF.md`** ให้ครบถ้วน
2. สร้างไฟล์ `schema_v2.sql` ตามโค้ดในหัวข้อ 4.1
3. สร้างไฟล์ `queries_v2.sql` ตามโค้ดในหัวข้อ 4.2
4. สร้างไฟล์ `demo_v2.sql` เพื่อสาธิตการ Trigger Error (เช่น ทดสอบเพิ่มห้องเรียนซ้ำ แล้วดูว่า Trigger บล็อกหรือไม่)
5. สร้างสคริปต์ `run_v2.sql` เพื่อรันคำสั่งทั้งหมดใน SQLite:
   ```sql
   .read Mini_Project_PlanA/schema.sql
   .read Mini_Project_PlanA/seed.sql
   .read Mini_Project_PlanA/schema_v2.sql
   .read Mini_Project_PlanA/queries.sql
   .read Mini_Project_PlanA/queries_v2.sql
   ```
6. หากต้องการออกแบบหน้า Web UI ในอนาคต ให้ยึด Interaction และ Data Models จากโฟลเดอร์ `timetable-reconstruction/` เป็นแนวทางหลัก

---
*เอกสารนี้ถูกปรับปรุงตรงตามความต้องการล่าสุดและพร้อมสำหรับการส่งมอบ 100%*

---

## ✅ 6. สถานะงาน (อัปเดต 14 พ.ย. 2569)

ข้อ 5 รายการ 1–5 ทำเสร็จแล้วในโฟลเดอร์ `Mini_Project_PlanA` ฉบับหลัก (ฉบับในชุดส่งต่อ `TimetableSystem_Full_handoff/` เป็นฉบับเก่ากว่าและไม่ได้แก้)

| ไฟล์ | สถานะ |
|---|---|
| `schema_v2.sql` | เสร็จ: 2 ตาราง, 8 view, 8 trigger, คอลัมน์ใหม่ของ `room` และ `course` |
| `seed_v2.sql` | เพิ่มใหม่ (ไม่มีในแผนเดิม): ข้อมูลสมมุติที่ส่วนขยายต้องใช้ |
| `queries_v2.sql` | เสร็จ: R7–R12 |
| `demo_v2.sql` | เสร็จ: D11–D20 (ตั้งใจให้ error 10 ครั้ง) |
| `run_v2.sql` | เสร็จ: รันด้วย `sqlite3 :memory: ".read run_v2.sql"` จากในโฟลเดอร์ |
| `Diagrams/registration-er-v2.drawio`, `.png` | เสร็จ: ER 20 ตาราง |

โค้ดในหัวข้อ 4.1 และ 4.2 ถูกปรับก่อนใช้ รายการจุดที่ต่างอยู่ใน README.md หัวข้อ "จุดที่ต่างจากโค้ดตัวอย่างใน HANDOFF.md"

`Project_Proposal_TH.txt` (อยู่นอกโฟลเดอร์นี้ หนึ่งระดับ) เขียนส่วนที่ 3–4 ใหม่ให้ครอบคลุมส่วนขยายแล้ว โดยเรียกว่า "ส่วน B งานจัดตาราง" แทนคำว่า v2

**ยังไม่ได้ทำ:** ข้อ 5 รายการ 6 (หน้า Web UI)

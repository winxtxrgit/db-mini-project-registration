"""สร้าง registration-er-v2.drawio (Plan A รวมส่วนขยาย v2 = 20 ตาราง)
รัน (จากโฟลเดอร์ archive/v2): python Diagrams/make_er.py Diagrams/registration-er-v2.drawio
"""
import sys
from xml.sax.saxutils import escape

OUT = sys.argv[1]
W, HEAD, ROW = 230, 30, 24
A, B, C, D, E, F, G = 40, 360, 680, 1000, 1320, 1640, 1960
R1, R2, R3 = 100, 400, 700

BLUE = ("#dae8fc", "#6c8ebf")      # ข้อมูลหลัก
GREEN = ("#d5e8d4", "#82b366")     # program (แยกเพื่อ 3NF)
ORANGE = ("#ffe6cc", "#d79b00")    # รายวิชาที่เปิดสอน
PURPLE = ("#e1d5e7", "#9673a6")    # การลงทะเบียน
YELLOW = ("#fff2cc", "#d6b656")    # ตารางใหม่ใน v2

tables = [
    ("program", A, R1, [("PK", "program_code", "TEXT"), ("", "program_name", "TEXT")], GREEN),
    ("curriculum", B, R1, [("PK", "curriculum_id", "TEXT"), ("FK", "program_code", "TEXT"),
                           ("", "curriculum_year", "INTEGER")], BLUE),
    ("study_plan", C, R1, [("PK,FK", "curriculum_id", "TEXT"), ("PK,FK", "course_code", "TEXT"),
                           ("", "year_level", "INTEGER"), ("", "semester", "INTEGER"),
                           ("", "is_required", "INTEGER")], BLUE),
    ("course", D, R1, [("PK", "course_code", "TEXT"), ("", "name_th", "TEXT"), ("", "name_en", "TEXT"),
                       ("", "credits", "INTEGER"), ("", "credit_pattern", "TEXT"),
                       ("", "course_category (v2)", "TEXT")], BLUE),
    ("prerequisite", E, R1, [("PK,FK", "course_code", "TEXT"), ("PK,FK", "prereq_code", "TEXT")], BLUE),
    ("section_quota", F, R1, [("PK,FK", "section_id", "INTEGER"), ("PK,FK", "curriculum_id", "TEXT"),
                              ("", "seats", "INTEGER")], ORANGE),

    ("student", A, R2, [("PK", "student_id", "TEXT"), ("", "first_name", "TEXT"), ("", "last_name", "TEXT"),
                        ("FK", "curriculum_id", "TEXT"), ("", "entry_year", "INTEGER")], BLUE),
    ("transcript", B, R2, [("PK,FK", "student_id", "TEXT"), ("PK,FK", "course_code", "TEXT"),
                           ("PK,FK", "term_id", "TEXT"), ("", "grade", "TEXT")], PURPLE),
    ("term", C, R2, [("PK", "term_id", "TEXT"), ("", "academic_year", "INTEGER"),
                     ("", "semester", "INTEGER"), ("", "is_current", "INTEGER")], BLUE),
    ("section", D, R2, [("PK", "section_id", "INTEGER"), ("FK", "course_code", "TEXT"),
                        ("FK", "term_id", "TEXT"), ("", "section_no", "TEXT"),
                        ("", "capacity", "INTEGER")], ORANGE),
    ("section_instructor", E, R2, [("PK,FK", "section_id", "INTEGER"),
                                   ("PK,FK", "instructor_id", "INTEGER")], ORANGE),
    ("instructor", F, R2, [("PK", "instructor_id", "INTEGER"), ("", "full_name", "TEXT")], BLUE),
    ("instructor_availability", G, R2, [("PK", "avail_id", "INTEGER"), ("FK", "instructor_id", "INTEGER"),
                                        ("FK", "term_id", "TEXT"), ("", "day_of_week", "INTEGER"),
                                        ("", "start_time", "TEXT"), ("", "end_time", "TEXT"),
                                        ("", "status", "TEXT"), ("", "note", "TEXT"),
                                        ("", "submitted_at", "TEXT")], YELLOW),

    ("registration_log", A, R3, [("PK", "log_id", "INTEGER"), ("FK", "student_id", "TEXT"),
                                 ("FK", "section_id", "INTEGER"), ("", "action", "TEXT"),
                                 ("", "logged_at", "TEXT")], PURPLE),
    ("enrollment", B, R3, [("PK,FK", "student_id", "TEXT"), ("PK,FK", "section_id", "INTEGER"),
                           ("", "enrolled_at", "TEXT")], PURPLE),
    ("waitlist", C, R3, [("PK,FK", "student_id", "TEXT"), ("PK,FK", "section_id", "INTEGER"),
                         ("", "requested_at", "TEXT")], PURPLE),
    ("class_meeting", D, R3, [("PK", "meeting_id", "INTEGER"), ("FK", "section_id", "INTEGER"),
                              ("", "day_of_week", "INTEGER"), ("", "start_time", "TEXT"),
                              ("", "end_time", "TEXT"), ("FK", "room_code", "TEXT")], ORANGE),
    ("room", E, R3 + 60, [("PK", "room_code", "TEXT"), ("", "capacity", "INTEGER"),
                          ("", "room_name (v2)", "TEXT"), ("", "building (v2)", "TEXT"),
                          ("", "floor_no (v2)", "INTEGER"), ("", "room_type (v2)", "TEXT"),
                          ("", "is_exam_room (v2)", "INTEGER")], BLUE),
    ("exam", F, R3, [("PK", "exam_id", "INTEGER"), ("FK", "section_id", "INTEGER"),
                     ("", "exam_type", "TEXT"), ("", "exam_date", "TEXT"), ("", "start_time", "TEXT"),
                     ("", "end_time", "TEXT"), ("FK", "room_code", "TEXT")], ORANGE),
    ("scheduling_priority", G, R3, [("PK,FK", "section_id", "INTEGER"), ("", "priority", "INTEGER"),
                                    ("", "is_locked", "INTEGER"), ("", "lock_reason", "TEXT"),
                                    ("", "locked_by", "TEXT"), ("", "locked_at", "TEXT")], YELLOW),
]
assert len(tables) == 20
box = {t[0]: (t[1], t[2], W, HEAD + ROW * len(t[3])) for t in tables}


def side(name, s, v):
    x, y, w, h = box[name]
    if s == "L": return 0, (v - y) / h
    if s == "R": return 1, (v - y) / h
    if s == "T": return (v - x) / w, 0
    return (v - x) / w, 1


def X(name, f):
    x, y, w, h = box[name]
    return x + w * f


ROOM_Y = R3 + 60 + 42      # แถว room_code ของตาราง room
MANY, ONE = "ERmany", "ERzeroToOne"

# (parent, ฝั่ง, ค่า, child, ฝั่ง, ค่า, waypoints, parent เป็น NULL ได้, label, ปลายฝั่ง child)
rels = [
    ("program", "R", R1 + 42, "curriculum", "L", R1 + 42, [], False, "", MANY),
    ("curriculum", "R", R1 + 42, "study_plan", "L", R1 + 42, [], False, "", MANY),
    ("course", "L", R1 + 66, "study_plan", "R", R1 + 66, [], False, "", MANY),
    ("course", "R", R1 + 42, "prerequisite", "L", R1 + 42, [], False, "course_code", MANY),
    ("course", "R", R1 + 66, "prerequisite", "L", R1 + 66, [], False, "prereq_code", MANY),
    ("curriculum", "T", X("curriculum", .5), "section_quota", "T", X("section_quota", .5),
     [(X("curriculum", .5), 72), (X("section_quota", .5), 72)], False, "", MANY),
    ("section", "T", X("section", .85), "section_quota", "B", X("section_quota", .5),
     [(X("section", .85), 345), (X("section_quota", .5), 345)], False, "", MANY),
    ("course", "B", X("course", .5), "section", "T", X("section", .5), [], False, "", MANY),
    ("course", "B", X("course", .2), "transcript", "T", X("transcript", .5),
     [(X("course", .2), 300), (X("transcript", .5), 300)], False, "", MANY),
    ("curriculum", "B", X("curriculum", .2), "student", "T", X("student", .5),
     [(X("curriculum", .2), 325), (X("student", .5), 325)], False, "", MANY),
    ("student", "R", R2 + 42, "transcript", "L", R2 + 42, [], False, "", MANY),
    ("term", "L", R2 + 90, "transcript", "R", R2 + 90, [], False, "", MANY),
    ("term", "R", R2 + 90, "section", "L", R2 + 90, [], False, "", MANY),
    ("section", "R", R2 + 42, "section_instructor", "L", R2 + 42, [], False, "", MANY),
    ("instructor", "L", R2 + 66, "section_instructor", "R", R2 + 66, [], False, "", MANY),
    ("section", "B", X("section", .5), "class_meeting", "T", X("class_meeting", .5), [], False, "", MANY),
    ("section", "B", X("section", .85), "exam", "T", X("exam", .5),
     [(X("section", .85), 655), (X("exam", .5), 655)], False, "", MANY),
    ("room", "L", ROOM_Y, "class_meeting", "R", ROOM_Y, [], True, "", MANY),
    ("room", "R", ROOM_Y, "exam", "L", ROOM_Y, [], True, "", MANY),
    ("student", "B", X("student", .3), "registration_log", "T", X("registration_log", .3), [], False, "", MANY),
    ("student", "B", X("student", .6), "enrollment", "T", X("enrollment", .35),
     [(X("student", .6), 585), (X("enrollment", .35), 585)], False, "", MANY),
    ("student", "B", X("student", .9), "waitlist", "T", X("waitlist", .3),
     [(X("student", .9), 600), (X("waitlist", .3), 600)], False, "", MANY),
    ("section", "B", X("section", .3), "waitlist", "T", X("waitlist", .75),
     [(X("section", .3), 615), (X("waitlist", .75), 615)], False, "", MANY),
    ("section", "B", X("section", .2), "enrollment", "T", X("enrollment", .75),
     [(X("section", .2), 630), (X("enrollment", .75), 630)], False, "", MANY),
    ("section", "B", X("section", .1), "registration_log", "T", X("registration_log", .75),
     [(X("section", .1), 645), (X("registration_log", .75), 645)], False, "", MANY),
    # ---- ส่วนขยาย v2 ----
    ("instructor", "R", R2 + 42, "instructor_availability", "L", R2 + 42, [], False, "", MANY),
    ("term", "T", X("term", .8), "instructor_availability", "T", X("instructor_availability", .25),
     [(X("term", .8), 365), (X("instructor_availability", .25), 365)], False, "", MANY),
    ("section", "B", X("section", .95), "scheduling_priority", "T", X("scheduling_priority", .5),
     [(X("section", .95), 672), (X("scheduling_priority", .5), 672)], False, "", ONE),
]

cells = []
add = cells.append
q = {'"': "&quot;"}

add('<mxCell id="title" value="ER Diagram: ระบบวางแผนและตรวจสอบการลงทะเบียนตามแผนการเรียน (20 ตาราง รวมส่วนขยาย v2 สำหรับฝ่ายจัดตาราง)" '
    'style="text;html=1;fontSize=20;fontStyle=1;align=left;verticalAlign=middle;" vertex="1" parent="1">'
    '<mxGeometry x="40" y="15" width="1400" height="40" as="geometry"/></mxCell>')

for name, x, y, cols, (fill, stroke) in tables:
    h = HEAD + ROW * len(cols)
    add(f'<mxCell id="t_{name}" value="{name}" style="swimlane;fontStyle=1;childLayout=stackLayout;horizontal=1;'
        f'startSize={HEAD};horizontalStack=0;resizeParent=1;resizeParentMax=0;resizeLast=0;collapsible=1;'
        f'marginBottom=0;html=1;fillColor={fill};strokeColor={stroke};fontSize=13;" vertex="1" parent="1">'
        f'<mxGeometry x="{x}" y="{y}" width="{W}" height="{h}" as="geometry"/></mxCell>')
    for i, (key, col, typ) in enumerate(cols):
        style = 4 if "PK" in key else 0
        new = col.endswith("(v2)")
        col = col.replace(" (v2)", "")
        value = escape(f"{key + '  ' if key else ''}{col} : {typ}", q)
        fillc = "fillColor=#fff2cc;" if new else "fillColor=none;"
        add(f'<mxCell id="c_{name}_{i}" value="{value}" style="text;strokeColor=none;{fillc}align=left;'
            f'verticalAlign=middle;spacingLeft=8;spacingRight=4;overflow=hidden;rotatable=0;'
            f'points=[[0,0.5],[1,0.5]];portConstraint=eastwest;fontStyle={style};fontSize=12;html=1;" '
            f'vertex="1" parent="t_{name}">'
            f'<mxGeometry y="{HEAD + ROW * i}" width="{W}" height="{ROW}" as="geometry"/></mxCell>')

for n, (p, ps, pv, c, cs, cv, pts, opt, label, end) in enumerate(rels):
    sx, sy = side(p, ps, pv)
    tx, ty = side(c, cs, cv)
    start = "ERzeroToOne" if opt else "ERmandOne"
    pts_xml = "".join(f'<mxPoint x="{px:g}" y="{py:g}"/>' for px, py in pts)
    arr = f'<Array as="points">{pts_xml}</Array>' if pts else ""
    add(f'<mxCell id="r{n}" value="{label}" style="edgeStyle=none;rounded=0;html=1;endArrow={end};'
        f'startArrow={start};endFill=0;startFill=0;endSize=10;startSize=10;fontSize=10;'
        f'labelBackgroundColor=#ffffff;exitX={sx:.4f};exitY={sy:.4f};exitDx=0;exitDy=0;exitPerimeter=0;'
        f'entryX={tx:.4f};entryY={ty:.4f};entryDx=0;entryDy=0;entryPerimeter=0;" '
        f'edge="1" parent="1" source="t_{p}" target="t_{c}">'
        f'<mxGeometry relative="1" as="geometry">{arr}</mxGeometry></mxCell>')

legend = ("สัญลักษณ์: PK = Primary Key (ขีดเส้นใต้), FK = Foreign Key, เส้น ||—o{ = 1 ต่อหลายแถว, "
          "|o—o{ = ห้องเป็น NULL ได้, ||—o| = 1 ต่อ 0..1<br>สี: เหลือง = ตารางและคอลัมน์ที่เพิ่มในส่วนขยาย v2, "
          "เขียว = ตาราง program, ฟ้า = ข้อมูลหลัก, ส้ม = รายวิชาที่เปิดสอน, ม่วง = การลงทะเบียนของนักศึกษา")
add(f'<mxCell id="legend" value="{escape(legend, q)}" style="text;html=1;fontSize=12;align=left;'
    'verticalAlign=top;whiteSpace=wrap;strokeColor=#999999;fillColor=#f5f5f5;spacing=8;" vertex="1" parent="1">'
    '<mxGeometry x="40" y="900" width="900" height="60" as="geometry"/></mxCell>')

xml = ('<mxfile host="drawio" type="device">\n<diagram name="ER v2" id="registration-er-v2">\n'
       '<mxGraphModel dx="1600" dy="1100" grid="1" gridSize="10" guides="1" tooltips="1" connect="1" arrows="1" '
       'fold="1" page="1" pageScale="1" pageWidth="2240" pageHeight="1000" math="0" shadow="0">\n<root>\n'
       '<mxCell id="0"/>\n<mxCell id="1" parent="0"/>\n' + "\n".join(cells) +
       '\n</root>\n</mxGraphModel>\n</diagram>\n</mxfile>\n')
with open(OUT, "w", encoding="utf-8") as f:
    f.write(xml)
print("tables", len(tables), "relationships", len(rels))

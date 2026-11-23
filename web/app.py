"""หน้าเว็บของระบบลงทะเบียนตามแผนการเรียน (Flask + SQLite)

ผู้ใช้ 3 บทบาท: นักศึกษา / ฝ่ายทะเบียน (admin) / อาจารย์ผู้จัดตาราง (scheduler)
- กฎทางธุรกิจทั้งหมดอยู่ใน trigger ของ schema.sql แอปแค่ส่งคำสั่งแล้วแสดงข้อความ error จาก RAISE(ABORT)
- แอปตรวจสิทธิ์ (ใครเข้าหน้าไหน แก้ข้อมูลของใครได้) และบอกฐานข้อมูลว่าใครทำรายการผ่านตาราง app_session

รัน:  python web/app.py   แล้วเปิด http://127.0.0.1:5000  (บัญชีทดสอบอยู่ใน seed.sql)
"""
import secrets

from markupsafe import Markup
from flask import (Flask, abort, flash, g, redirect, render_template, request,
                   session, url_for)
from werkzeug.security import check_password_hash, generate_password_hash

from core import BASE, DAYS, HOME, ROLE_NAME, close_db, one
from views_admin import bp as admin_bp
from views_scheduler import bp as scheduler_bp
from views_student import bp as student_bp

SECRET_FILE = BASE / ".secret_key"

app = Flask(__name__)


def _secret_key() -> str:
    """สร้าง secret key แบบสุ่มครั้งแรกแล้วเก็บไว้ในไฟล์ (ไม่ขึ้น git) เพื่อให้ session อยู่ข้ามการรีสตาร์ต"""
    if not SECRET_FILE.exists():
        SECRET_FILE.write_text(secrets.token_hex(32), encoding="utf-8")
    return SECRET_FILE.read_text(encoding="utf-8").strip()


app.secret_key = _secret_key()
app.config.update(SESSION_COOKIE_HTTPONLY=True, SESSION_COOKIE_SAMESITE="Lax")
app.jinja_env.globals.update(DAYS=DAYS, ROLE_NAME=ROLE_NAME)
app.teardown_appcontext(close_db)


@app.context_processor
def layout_context():
    """ข้อมูลที่ทุกหน้าใช้ใน base.html: ภาคเรียนปัจจุบัน และเลขเวอร์ชันไฟล์ static (กัน browser ใช้ไฟล์เก่า)"""
    term = None
    if g.get("user") is not None:
        term = one("SELECT term_id, reg_is_open, reg_open_at, reg_close_at, max_credits "
                   "FROM v_term_status WHERE is_current = 1")
    return {"current_term": term, "static_v": _static_version() if app.debug else _STATIC_V}


def _static_version() -> str:
    files = list((BASE / "static").rglob("*.*"))
    return str(int(max((f.stat().st_mtime for f in files), default=0)))


_STATIC_V = _static_version()
app.register_blueprint(student_bp)
app.register_blueprint(admin_bp)
app.register_blueprint(scheduler_bp)


# ------------------------------------------------------------------ login และสิทธิ์
@app.before_request
def load_user():
    g.user = None
    uid = session.get("uid")
    if uid is not None:
        user = one("SELECT * FROM app_user WHERE user_id = :uid AND is_active = 1", uid=uid)
        if user is None:
            session.clear()
        else:
            g.user = user


def csrf_token() -> str:
    if "csrf" not in session:
        session["csrf"] = secrets.token_urlsafe(32)
    return session["csrf"]


app.jinja_env.globals["csrf_token"] = csrf_token
app.jinja_env.globals["csrf_field"] = lambda: Markup(
    f'<input type="hidden" name="csrf_token" value="{csrf_token()}">')


@app.before_request
def check_csrf():
    if request.method == "POST":
        token = request.form.get("csrf_token", "")
        if not token or not secrets.compare_digest(token, session.get("csrf", "")):
            abort(400, "CSRF token ไม่ถูกต้อง กรุณาโหลดหน้าใหม่แล้วลองอีกครั้ง")


def _safe_next(target: str) -> bool:
    """อนุญาตเฉพาะ path ภายในเว็บนี้ (กัน open redirect เช่น //evil.com หรือ /\\evil.com)"""
    return target.startswith("/") and not target.startswith(("//", "/\\"))


# ใช้ตรวจรหัสผ่านกับ username ที่ไม่มีอยู่ เพื่อให้เวลาตอบสนองใกล้เคียงกัน (กันการเดาว่ามี username นี้หรือไม่)
_DUMMY_HASH = generate_password_hash("not-a-real-password")


@app.route("/")
def index():
    if g.user is None:
        return redirect(url_for("login"))
    return redirect(url_for(HOME[g.user["role"]]))


@app.route("/login", methods=["GET", "POST"])
def login():
    if request.method == "POST":
        username = request.form.get("username", "").strip()
        password = request.form.get("password", "")
        user = one("SELECT * FROM app_user WHERE username = :u", u=username)
        ok = check_password_hash(user["password_hash"] if user else _DUMMY_HASH, password)
        if user and ok and user["is_active"]:
            session.clear()                      # กัน session fixation
            session["uid"] = user["user_id"]
            nxt = request.args.get("next", "")
            if _safe_next(nxt):
                return redirect(nxt)
            return redirect(url_for(HOME[user["role"]]))
        flash("ชื่อผู้ใช้หรือรหัสผ่านไม่ถูกต้อง", "error")
    return render_template("login.html")


@app.post("/logout")
def logout():
    session.clear()
    return redirect(url_for("login"))


@app.errorhandler(403)
def forbidden(_e):
    return render_template("error.html", code=403, message="บัญชีนี้ไม่มีสิทธิ์เข้าหน้านี้"), 403


@app.errorhandler(404)
def not_found(_e):
    return render_template("error.html", code=404, message="ไม่พบหน้าหรือข้อมูลที่ต้องการ"), 404


@app.errorhandler(400)
def bad_request(e):
    return render_template("error.html", code=400, message=e.description), 400


if __name__ == "__main__":
    app.run(debug=True)

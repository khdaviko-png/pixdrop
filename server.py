import hashlib
import hmac
import os
import re
import secrets
import sqlite3
from datetime import datetime, timedelta
from functools import wraps

from flask import (
    Flask,
    jsonify,
    redirect,
    render_template_string,
    request,
    send_from_directory,
    session,
    url_for,
)
from waitress import serve
from werkzeug.security import check_password_hash, generate_password_hash
from werkzeug.utils import secure_filename

try:
    from ai_engine import get_color_fingerprint, get_visual_fingerprint, rank_matches
except Exception as e:
    print('AI engine load error:', e)
    get_color_fingerprint = None
    get_visual_fingerprint = None
    rank_matches = None

APP_DIR = os.path.abspath(os.path.dirname(__file__))
DB_PATH = os.path.join(APP_DIR, 'store.db')
UPLOAD_FOLDER = os.path.join(APP_DIR, 'uploads')
PRIMARY_ADMIN_PHONE = '+998995442358'
ADMIN_PHONES = {
    PRIMARY_ADMIN_PHONE,
    '+998943219444',
}
TOKEN_DAYS = 90

os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 30 * 1024 * 1024
app.secret_key = os.environ.get('PIXDrop_SECRET_KEY') or secrets.token_hex(32)
app.config.update(
    SESSION_COOKIE_HTTPONLY=True,
    SESSION_COOKIE_SAMESITE='Lax',
)


def now_str():
    return datetime.now().strftime('%Y-%m-%d %H:%M:%S')


def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.execute('PRAGMA foreign_keys=ON;')
    return conn


def table_columns(conn, table):
    return {r['name'] for r in conn.execute(f'PRAGMA table_info({table})').fetchall()}


def ensure_column(conn, table, name, definition):
    if name not in table_columns(conn, table):
        conn.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')


def init_db():
    conn = get_db()

    conn.execute('''
        CREATE TABLE IF NOT EXISTS users (
            phone TEXT PRIMARY KEY,
            name TEXT,
            district TEXT,
            password_hash TEXT,
            is_blocked INTEGER DEFAULT 1,
            sub_end_date TEXT,
            last_active TEXT,
            is_admin INTEGER DEFAULT 0
        )
    ''')
    ensure_column(conn, 'users', 'is_admin', 'INTEGER DEFAULT 0')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS auth_tokens (
            token TEXT PRIMARY KEY,
            phone TEXT NOT NULL,
            expires_at TEXT NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY(phone) REFERENCES users(phone) ON DELETE CASCADE
        )
    ''')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            shop_id TEXT NOT NULL,
            name TEXT NOT NULL,
            price TEXT DEFAULT '0',
            code TEXT,
            image_path TEXT,
            color_data BLOB,
            visual_data BLOB,
            quantity REAL DEFAULT 0,
            created_at TEXT,
            FOREIGN KEY(shop_id) REFERENCES users(phone) ON DELETE CASCADE
        )
    ''')
    for col, definition in [
        ('quantity', 'REAL DEFAULT 0'),
        ('created_at', 'TEXT'),
        ('visual_data', 'BLOB'),
    ]:
        ensure_column(conn, 'products', col, definition)

    conn.execute('''
        CREATE TABLE IF NOT EXISTS product_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            product_id INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            sort_order INTEGER DEFAULT 0,
            FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE
        )
    ''')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS catalog_products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            price TEXT DEFAULT '0',
            code TEXT,
            image_path TEXT,
            color_data BLOB,
            visual_data BLOB,
            created_at TEXT,
            updated_at TEXT
        )
    ''')
    ensure_column(conn, 'catalog_products', 'visual_data', 'BLOB')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS catalog_images (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            catalog_product_id INTEGER NOT NULL,
            image_path TEXT NOT NULL,
            sort_order INTEGER DEFAULT 0,
            FOREIGN KEY(catalog_product_id) REFERENCES catalog_products(id) ON DELETE CASCADE
        )
    ''')

    conn.execute('''
        CREATE TABLE IF NOT EXISTS search_stats (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            phone TEXT,
            product_name TEXT NOT NULL,
            search_count INTEGER DEFAULT 1,
            last_searched TEXT,
            UNIQUE(phone, product_name)
        )
    ''')

    # Eski bazalar bilan moslik uchun saqlanadi.
    conn.execute('''
        CREATE TABLE IF NOT EXISTS global_products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            default_price TEXT,
            code TEXT,
            image_path TEXT,
            color_data BLOB
        )
    ''')

    # Eski global katalog bo'lsa, faqat bir marta yangi katalogga ko'chiriladi.
    if conn.execute('SELECT COUNT(*) c FROM catalog_products').fetchone()['c'] == 0:
        rows = conn.execute(
            'SELECT name, default_price, code, image_path, color_data FROM global_products'
        ).fetchall()
        for r in rows:
            conn.execute('''
                INSERT INTO catalog_products(
                    name, price, code, image_path, color_data, created_at, updated_at
                ) VALUES(?,?,?,?,?,?,?)
            ''', (
                r['name'], r['default_price'], r['code'], r['image_path'],
                r['color_data'], now_str(), now_str()
            ))

    conn.execute('CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_products_shop_code ON products(shop_id, code)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_catalog_name ON catalog_products(name)')
    conn.executemany(
        'UPDATE users SET is_admin=1, is_blocked=0 WHERE phone=?',
        [(phone,) for phone in ADMIN_PHONES],
    )
    conn.commit()
    conn.close()


init_db()


def validate_phone(phone):
    return re.fullmatch(r'\+998\d{9}', phone or '') is not None


def is_legacy_sha256(value):
    return bool(re.fullmatch(r'[0-9a-fA-F]{64}', value or ''))


def verify_password(stored_hash, password):
    if not stored_hash:
        return False

    if is_legacy_sha256(stored_hash):
        legacy = hashlib.sha256(password.encode('utf-8')).hexdigest()
        return hmac.compare_digest(stored_hash.lower(), legacy.lower())

    try:
        return check_password_hash(stored_hash, password)
    except Exception:
        return False


def issue_token(conn, phone):
    token = secrets.token_urlsafe(32)
    expires_at = (datetime.now() + timedelta(days=TOKEN_DAYS)).strftime('%Y-%m-%d %H:%M:%S')
    conn.execute(
        'INSERT INTO auth_tokens(token,phone,expires_at,created_at) VALUES(?,?,?,?)',
        (token, phone, expires_at, now_str()),
    )
    return token


def subscription_state(conn, phone):
    row = conn.execute('''
        SELECT phone, is_blocked, sub_end_date, is_admin
        FROM users WHERE phone=?
    ''', (phone,)).fetchone()

    if not row:
        return {'status': 'error', 'message': 'Foydalanuvchi topilmadi.'}, 404

    if row['is_admin'] or phone in ADMIN_PHONES:
        return {'status': 'active', 'days_left': 9999, 'warning': None}, 200

    if row['is_blocked']:
        return {'status': 'blocked', 'message': 'Akkaunt bloklangan. Admin bilan bog\'laning.'}, 403

    if not row['sub_end_date']:
        return {'status': 'blocked', 'message': 'Obuna aktiv emas. Admin bilan bog\'laning.'}, 403

    try:
        end = datetime.strptime(row['sub_end_date'], '%Y-%m-%d %H:%M:%S')
    except Exception:
        return {'status': 'blocked', 'message': 'Obuna sanasi xato.'}, 403

    now = datetime.now()
    if now > end:
        conn.execute('UPDATE users SET is_blocked=1 WHERE phone=?', (phone,))
        conn.commit()
        return {'status': 'blocked', 'message': 'Obuna muddati tugadi. Admin bilan bog\'laning.'}, 403

    days_left = max(1, (end - now).days + 1)
    warning = None
    if days_left <= 3:
        warning = f'Diqqat! Obunangiz tugashiga {days_left} kun qoldi.'

    return {
        'status': 'active',
        'days_left': days_left,
        'warning': warning,
        'sub_end_date': row['sub_end_date'],
    }, 200


def bearer_token():
    value = request.headers.get('Authorization', '')
    if value.lower().startswith('bearer '):
        return value[7:].strip()
    return ''


def auth_required(admin=False):
    def decorator(fn):
        @wraps(fn)
        def wrapped(*args, **kwargs):
            token = bearer_token()
            if not token:
                return jsonify(status='error', message='Token kerak.'), 401

            conn = get_db()
            row = conn.execute('''
                SELECT t.phone, t.expires_at, u.is_admin
                FROM auth_tokens t
                JOIN users u ON u.phone=t.phone
                WHERE t.token=?
            ''', (token,)).fetchone()

            if not row:
                conn.close()
                return jsonify(status='error', message='Sessiya topilmadi.'), 401

            try:
                expired = datetime.now() > datetime.strptime(row['expires_at'], '%Y-%m-%d %H:%M:%S')
            except Exception:
                expired = True

            if expired:
                conn.execute('DELETE FROM auth_tokens WHERE token=?', (token,))
                conn.commit()
                conn.close()
                return jsonify(status='error', message='Sessiya tugagan.'), 401

            subscription, code = subscription_state(conn, row['phone'])
            is_admin = bool(row['is_admin'] or row['phone'] in ADMIN_PHONES)

            if code != 200 and not is_admin:
                conn.close()
                return jsonify(subscription), code

            if admin and not is_admin:
                conn.close()
                return jsonify(status='error', message='Admin ruxsati kerak.'), 403

            conn.execute('UPDATE users SET last_active=? WHERE phone=?', (now_str(), row['phone']))
            conn.commit()
            conn.close()

            request.user_phone = row['phone']
            request.user_is_admin = is_admin
            request.subscription = subscription
            return fn(*args, **kwargs)

        return wrapped
    return decorator


def save_uploaded(file_obj, prefix='img'):
    ext = os.path.splitext(secure_filename(file_obj.filename or ''))[1].lower() or '.jpg'
    name = f'{prefix}_{datetime.now().strftime("%Y%m%d%H%M%S%f")}_{secrets.token_hex(4)}{ext}'
    path = os.path.join(UPLOAD_FOLDER, name)
    file_obj.save(path)
    return name, path


def raw_image_name(value):
    value = (value or '').replace('\\', '/').strip()
    if value.startswith('/uploads/'):
        return value[len('/uploads/'):]
    if value.startswith('uploads/'):
        return value[len('uploads/'):]
    return value


def public_image_path(value):
    name = raw_image_name(value)
    return f'uploads/{name}' if name else ''


def product_json(row, images=None):
    raw_images = images or ([] if not row['image_path'] else [row['image_path']])
    return {
        'id': row['id'],
        'name': row['name'],
        'price': row['price'],
        'code': row['code'] or '',
        'image_path': public_image_path(row['image_path']),
        'images': [public_image_path(x) for x in raw_images if x],
        'quantity': row['quantity'] if 'quantity' in row.keys() else 0,
        'created_at': row['created_at'] if 'created_at' in row.keys() else None,
    }


def ensure_visual_for_row(conn, row):
    if 'visual_data' in row.keys() and row['visual_data']:
        return row['visual_data']

    if not get_visual_fingerprint:
        return None

    image_name = raw_image_name(row['image_path'])
    if not image_name:
        return None

    path = os.path.join(UPLOAD_FOLDER, image_name)
    if not os.path.exists(path):
        return None

    try:
        visual = get_visual_fingerprint(path)
        if visual:
            conn.execute('UPDATE products SET visual_data=? WHERE id=?', (visual, row['id']))
            conn.commit()
        return visual
    except Exception:
        return None


def find_product_for_request(conn, product_id=None, code=None, shop_id=None):
    if product_id:
        return conn.execute('SELECT * FROM products WHERE id=?', (product_id,)).fetchone()

    if code and shop_id:
        return conn.execute('''
            SELECT * FROM products
            WHERE shop_id=? AND code=?
            ORDER BY id DESC LIMIT 1
        ''', (shop_id, code)).fetchone()

    return None


@app.get('/health')
def health():
    return jsonify(
        status='ok',
        service='PixDrop API',
        ai='v2' if rank_matches else 'unavailable',
        time=now_str(),
    )


@app.post('/register')
def register():
    phone = request.form.get('phone', '').strip()
    name = request.form.get('name', '').strip()
    district = request.form.get('district', '').strip()
    password = request.form.get('password', '')

    errors = []
    if not name:
        errors.append('Ism va familiya kiritilmagan.')
    elif len(name) < 2:
        errors.append('Ism juda qisqa.')

    if not phone:
        errors.append('Telefon raqami kiritilmagan.')
    elif not validate_phone(phone):
        errors.append('Telefon formati xato. Masalan: +998901234567')

    if not district:
        errors.append('Tuman yoki shahar kiritilmagan.')

    if not password:
        errors.append('Parol kiritilmagan.')
    elif len(password) < 4:
        errors.append('Parol kamida 4 ta belgidan iborat bo\'lsin.')

    if errors:
        return jsonify(status='error', message='\n'.join(errors), errors=errors), 400

    conn = get_db()
    if conn.execute('SELECT 1 FROM users WHERE phone=?', (phone,)).fetchone():
        conn.close()
        return jsonify(status='error', message='Bu telefon raqami avval ro\'yxatdan o\'tgan.'), 400

    is_admin = 1 if phone in ADMIN_PHONES else 0
    is_blocked = 0
    free_days = 3650 if is_admin else 30
    sub_end = (datetime.now() + timedelta(days=free_days)).strftime('%Y-%m-%d %H:%M:%S')

    conn.execute('''
        INSERT INTO users(
            phone, name, district, password_hash,
            is_blocked, sub_end_date, last_active, is_admin
        ) VALUES(?,?,?,?,?,?,?,?)
    ''', (
        phone, name, district, generate_password_hash(password),
        is_blocked, sub_end, now_str(), is_admin
    ))
    conn.commit()
    conn.close()

    return jsonify(
        status='success',
        message='Ro\'yxatdan o\'tdingiz. 30 kunlik bepul foydalanish yoqildi!'
    )


@app.post('/login')
def login():
    phone = request.form.get('phone', '').strip()
    password = request.form.get('password', '')

    if not phone:
        return jsonify(status='error', message='Telefon raqamini kiriting.'), 400
    if not password:
        return jsonify(status='error', message='Parolni kiriting.'), 400

    conn = get_db()
    user = conn.execute('SELECT * FROM users WHERE phone=?', (phone,)).fetchone()

    if not user:
        conn.close()
        return jsonify(status='error', message='Bu telefon raqami ro\'yxatdan o\'tmagan.'), 401

    if not verify_password(user['password_hash'], password):
        conn.close()
        return jsonify(status='error', message='Parol noto\'g\'ri.'), 401

    # Eski SHA256 parollarni xavfsiz hash formatiga avtomatik o'tkazadi.
    if is_legacy_sha256(user['password_hash']):
        conn.execute(
            'UPDATE users SET password_hash=? WHERE phone=?',
            (generate_password_hash(password), phone),
        )

    subscription, status_code = subscription_state(conn, phone)
    is_admin = bool(user['is_admin'] or phone in ADMIN_PHONES)

    if status_code != 200 and not is_admin:
        conn.commit()
        conn.close()
        return jsonify(subscription), status_code

    token = issue_token(conn, phone)
    conn.execute('UPDATE users SET last_active=? WHERE phone=?', (now_str(), phone))
    conn.commit()
    conn.close()

    return jsonify(
        status='success',
        token=token,
        user={
            'phone': user['phone'],
            'name': user['name'],
            'district': user['district'],
            'is_admin': is_admin,
        },
        subscription=subscription,
    )


@app.get('/auth/check')
@auth_required()
def auth_check():
    conn = get_db()
    user = conn.execute('''
        SELECT phone, name, district, is_admin
        FROM users WHERE phone=?
    ''', (request.user_phone,)).fetchone()
    conn.close()

    return jsonify(
        status='success',
        user={
            'phone': user['phone'],
            'name': user['name'],
            'district': user['district'],
            'is_admin': bool(user['is_admin'] or user['phone'] in ADMIN_PHONES),
        },
        subscription=request.subscription,
    )


@app.post('/logout')
def logout():
    token = bearer_token()
    if token:
        conn = get_db()
        conn.execute('DELETE FROM auth_tokens WHERE token=?', (token,))
        conn.commit()
        conn.close()
    return jsonify(status='success')


@app.get('/uploads/<path:name>')
def uploads(name):
    return send_from_directory(UPLOAD_FOLDER, name)


@app.get('/products')
@auth_required()
def products():
    requested_shop = request.args.get('shop_id', '').strip()
    shop_id = requested_shop if request.user_is_admin and requested_shop else request.user_phone

    conn = get_db()
    rows = conn.execute('''
        SELECT * FROM products
        WHERE shop_id=?
        ORDER BY name COLLATE NOCASE
    ''', (shop_id,)).fetchall()

    result = []
    for row in rows:
        images = [x['image_path'] for x in conn.execute('''
            SELECT image_path FROM product_images
            WHERE product_id=?
            ORDER BY sort_order, id
        ''', (row['id'],)).fetchall()]
        result.append(product_json(row, images))

    conn.close()
    return jsonify(result)


@app.post('/add_product')
@auth_required()
def add_product():
    name = request.form.get('name', '').strip()
    price = request.form.get('price', '0').strip()
    code = request.form.get('code', '').strip()
    qty_raw = request.form.get('quantity', request.form.get('qty', '0'))

    if not name:
        return jsonify(status='error', message='Mahsulot nomi kerak.'), 400

    try:
        quantity = float(qty_raw or 0)
    except Exception:
        quantity = 0

    requested_shop = request.form.get('shop_id', '').strip()
    shop_id = requested_shop if request.user_is_admin and requested_shop else request.user_phone

    files = request.files.getlist('images')
    if not files and 'image' in request.files:
        files = [request.files['image']]

    saved = []
    color_data = None
    visual_data = None

    for file_obj in files:
        if not file_obj or not file_obj.filename:
            continue

        name_on_disk, path = save_uploaded(file_obj, 'product')
        saved.append(name_on_disk)

        if color_data is None and get_color_fingerprint:
            try:
                color_data = get_color_fingerprint(path)
            except Exception:
                pass

        if visual_data is None and get_visual_fingerprint:
            try:
                visual_data = get_visual_fingerprint(path)
            except Exception:
                pass

    conn = get_db()
    cursor = conn.execute('''
        INSERT INTO products(
            shop_id, name, price, code, image_path,
            color_data, visual_data, quantity, created_at
        ) VALUES(?,?,?,?,?,?,?,?,?)
    ''', (
        shop_id, name, price, code,
        saved[0] if saved else '',
        color_data, visual_data, quantity, now_str()
    ))
    product_id = cursor.lastrowid

    for index, image_name in enumerate(saved):
        conn.execute('''
            INSERT INTO product_images(product_id,image_path,sort_order)
            VALUES(?,?,?)
        ''', (product_id, image_name, index))

    conn.commit()
    conn.close()

    return jsonify(
        status='success',
        id=product_id,
        message='Mahsulot qo\'shildi.'
    )


@app.post('/update_price')
@auth_required()
def update_price():
    # Yangi ilova: id/product_id + price
    # Eski ilova: kod + yangi_narx
    product_id = request.form.get('id') or request.form.get('product_id')
    code = (request.form.get('code') or request.form.get('kod') or '').strip()
    price = (request.form.get('price') or request.form.get('yangi_narx') or '').strip()

    if not price:
        return jsonify(status='error', message='Yangi narx kiritilmagan.'), 400

    requested_shop = request.form.get('shop_id', '').strip()
    shop_id = requested_shop if request.user_is_admin and requested_shop else request.user_phone

    conn = get_db()
    row = find_product_for_request(conn, product_id=product_id, code=code, shop_id=shop_id)

    if not row:
        conn.close()
        return jsonify(status='error', message='Mahsulot topilmadi.'), 404

    if not request.user_is_admin and row['shop_id'] != request.user_phone:
        conn.close()
        return jsonify(status='error', message='Ruxsat yo\'q.'), 403

    conn.execute('UPDATE products SET price=? WHERE id=?', (price, row['id']))
    conn.commit()
    conn.close()

    return jsonify(status='success', id=row['id'], price=price)


@app.post('/delete_product')
@auth_required()
def delete_product():
    # Yangi ilova: id/product_id
    # Eski ilova: kod
    product_id = request.form.get('id') or request.form.get('product_id')
    code = (request.form.get('code') or request.form.get('kod') or '').strip()

    requested_shop = request.form.get('shop_id', '').strip()
    shop_id = requested_shop if request.user_is_admin and requested_shop else request.user_phone

    conn = get_db()
    row = find_product_for_request(conn, product_id=product_id, code=code, shop_id=shop_id)

    if not row:
        conn.close()
        return jsonify(status='error', message='Mahsulot topilmadi.'), 404

    if not request.user_is_admin and row['shop_id'] != request.user_phone:
        conn.close()
        return jsonify(status='error', message='Ruxsat yo\'q.'), 403

    image_names = [x['image_path'] for x in conn.execute('''
        SELECT image_path FROM product_images WHERE product_id=?
    ''', (row['id'],)).fetchall()]
    if row['image_path']:
        image_names.append(row['image_path'])

    conn.execute('DELETE FROM products WHERE id=?', (row['id'],))
    conn.commit()
    conn.close()

    # Faqat shu mahsulotga tegishli rasmlarni tozalashga urinamiz.
    for image_name in set(image_names):
        path = os.path.join(UPLOAD_FOLDER, raw_image_name(image_name))
        try:
            if os.path.isfile(path):
                os.remove(path)
        except Exception:
            pass

    return jsonify(status='success', id=row['id'])


@app.post('/predict')
@auth_required()
def predict():
    if 'image' not in request.files:
        return jsonify(status='error', message='Rasm kerak.'), 400

    if not rank_matches:
        return jsonify(status='error', message='AI engine yuklanmagan.'), 503

    _, scan_path = save_uploaded(request.files['image'], 'scan')

    try:
        requested_shop = request.form.get('shop_id', '').strip()
        shop_id = requested_shop if request.user_is_admin and requested_shop else request.user_phone

        conn = get_db()
        rows = conn.execute('SELECT * FROM products WHERE shop_id=?', (shop_id,)).fetchall()
        products_for_ai = []

        for row in rows:
            visual = ensure_visual_for_row(conn, row)
            products_for_ai.append({
                'id': row['id'],
                'name': row['name'],
                'price': row['price'],
                'code': row['code'] or '',
                'image_path': public_image_path(row['image_path']),
                'color_data': row['color_data'],
                'visual_data': visual,
            })

        conn.close()
        result = rank_matches(scan_path, products_for_ai, top_k=3)

        if result['status'] == 'empty':
            return jsonify(
                status='not_found',
                message='Omboringizda mahsulot yo\'q.',
                suggestions=[],
            ), 404

        if result['status'] == 'success':
            match = result['match']
            return jsonify(
                status='success',
                match=match,
                name=match['name'],
                price=match['price'],
                code=match.get('code', ''),
                score=result['score'],
                detected=result['detected'],
                suggestions=result['suggestions'],
            )

        return jsonify(
            status='similar',
            message='Aniq topilmadi. O\'xshash mahsulotlardan birini tanlang.',
            score=result['score'],
            detected=result['detected'],
            suggestions=result['suggestions'],
        )
    finally:
        try:
            os.remove(scan_path)
        except Exception:
            pass


@app.get('/catalog')
@auth_required()
def catalog():
    query = request.args.get('q', '').strip()
    conn = get_db()

    if query:
        rows = conn.execute('''
            SELECT * FROM catalog_products
            WHERE name LIKE ?
            ORDER BY name COLLATE NOCASE
        ''', (query + '%',)).fetchall()
    else:
        rows = conn.execute('''
            SELECT * FROM catalog_products
            ORDER BY name COLLATE NOCASE
        ''').fetchall()

    result = []
    for row in rows:
        images = [x['image_path'] for x in conn.execute('''
            SELECT image_path FROM catalog_images
            WHERE catalog_product_id=?
            ORDER BY sort_order, id
        ''', (row['id'],)).fetchall()]

        result.append({
            'id': row['id'],
            'name': row['name'],
            'price': row['price'],
            'code': row['code'] or '',
            'image_path': public_image_path(row['image_path']),
            'images': [public_image_path(x) for x in images],
        })

    conn.close()
    return jsonify(result)


@app.post('/catalog/search')
@auth_required()
def catalog_search_stat():
    name = request.form.get('name', '').strip()
    if name:
        conn = get_db()
        conn.execute('''
            INSERT INTO search_stats(phone,product_name,search_count,last_searched)
            VALUES(?,?,1,?)
            ON CONFLICT(phone,product_name)
            DO UPDATE SET
                search_count=search_count+1,
                last_searched=excluded.last_searched
        ''', (request.user_phone, name, now_str()))
        conn.commit()
        conn.close()

    return jsonify(status='success')


@app.get('/catalog/popular')
@auth_required()
def catalog_popular():
    conn = get_db()
    rows = conn.execute('''
        SELECT product_name, SUM(search_count) cnt
        FROM search_stats
        GROUP BY product_name
        ORDER BY cnt DESC
        LIMIT 20
    ''').fetchall()
    conn.close()

    return jsonify([
        {'name': row['product_name'], 'search_count': row['cnt']}
        for row in rows
    ])


@app.post('/admin/catalog/add')
@auth_required(admin=True)
def admin_catalog_add():
    name = request.form.get('name', '').strip()
    price = request.form.get('price', '0').strip()
    code = request.form.get('code', '').strip()

    if not name:
        return jsonify(status='error', message='Nomi kerak.'), 400

    saved = []
    color_data = None
    visual_data = None

    files = request.files.getlist('images')
    if not files and 'image' in request.files:
        files = [request.files['image']]

    for file_obj in files:
        if not file_obj or not file_obj.filename:
            continue

        image_name, path = save_uploaded(file_obj, 'catalog')
        saved.append(image_name)

        if color_data is None and get_color_fingerprint:
            try:
                color_data = get_color_fingerprint(path)
            except Exception:
                pass

        if visual_data is None and get_visual_fingerprint:
            try:
                visual_data = get_visual_fingerprint(path)
            except Exception:
                pass

    conn = get_db()
    cursor = conn.execute('''
        INSERT INTO catalog_products(
            name, price, code, image_path,
            color_data, visual_data, created_at, updated_at
        ) VALUES(?,?,?,?,?,?,?,?)
    ''', (
        name, price, code,
        saved[0] if saved else '',
        color_data, visual_data, now_str(), now_str()
    ))
    catalog_id = cursor.lastrowid

    for index, image_name in enumerate(saved):
        conn.execute('''
            INSERT INTO catalog_images(catalog_product_id,image_path,sort_order)
            VALUES(?,?,?)
        ''', (catalog_id, image_name, index))

    conn.commit()
    conn.close()

    return jsonify(status='success', id=catalog_id)


@app.post('/admin/catalog/update')
@auth_required(admin=True)
def admin_catalog_update():
    catalog_id = request.form.get('id')
    conn = get_db()
    row = conn.execute('SELECT * FROM catalog_products WHERE id=?', (catalog_id,)).fetchone()

    if not row:
        conn.close()
        return jsonify(status='error', message='Topilmadi.'), 404

    name = request.form.get('name')
    price = request.form.get('price')
    code = request.form.get('code')

    conn.execute('''
        UPDATE catalog_products
        SET name=?, price=?, code=?, updated_at=?
        WHERE id=?
    ''', (
        name if name is not None else row['name'],
        price if price is not None else row['price'],
        code if code is not None else row['code'],
        now_str(), catalog_id,
    ))
    conn.commit()
    conn.close()

    return jsonify(status='success')


@app.post('/admin/catalog/delete')
@auth_required(admin=True)
def admin_catalog_delete():
    catalog_id = request.form.get('id')
    conn = get_db()
    row = conn.execute(
        'SELECT 1 FROM catalog_products WHERE id=?',
        (catalog_id,),
    ).fetchone()

    if not row:
        conn.close()
        return jsonify(status='error', message='Topilmadi.'), 404

    conn.execute('DELETE FROM catalog_products WHERE id=?', (catalog_id,))
    conn.commit()
    conn.close()
    return jsonify(status='success')


@app.post('/admin/toggle_subscription')
@auth_required(admin=True)
def toggle_subscription():
    phone = request.form.get('user_phone', '').strip()
    action = request.form.get('action', '').strip()

    conn = get_db()
    if not conn.execute('SELECT 1 FROM users WHERE phone=?', (phone,)).fetchone():
        conn.close()
        return jsonify(status='error', message='Foydalanuvchi topilmadi.'), 404

    if action == 'enable':
        end = (datetime.now() + timedelta(days=30)).strftime('%Y-%m-%d %H:%M:%S')
        conn.execute(
            'UPDATE users SET is_blocked=0, sub_end_date=? WHERE phone=?',
            (end, phone),
        )
        message = 'Obuna 30 kunga yoqildi.'
    elif action == 'disable':
        conn.execute('UPDATE users SET is_blocked=1 WHERE phone=?', (phone,))
        message = 'Foydalanuvchi bloklandi.'
    else:
        conn.close()
        return jsonify(status='error', message='action enable yoki disable bo\'lsin.'), 400

    conn.commit()
    conn.close()
    return jsonify(status='success', message=message)


@app.get('/admin/users_stat')
@auth_required(admin=True)
def users_stat():
    district = request.args.get('district', '').strip()
    status = request.args.get('status', '').strip()

    conn = get_db()
    query = '''
        SELECT phone,name,district,is_blocked,sub_end_date,last_active,is_admin
        FROM users WHERE 1=1
    '''
    params = []

    if district:
        query += ' AND district=?'
        params.append(district)

    if status == 'active':
        query += ' AND is_blocked=0'
    elif status == 'blocked':
        query += ' AND is_blocked=1'

    rows = conn.execute(query, params).fetchall()
    today = datetime.now().strftime('%Y-%m-%d')

    users = [
        {
            'phone': row['phone'],
            'name': row['name'],
            'district': row['district'],
            'is_blocked': bool(row['is_blocked']),
            'sub_end_date': row['sub_end_date'],
            'last_active': row['last_active'],
            'is_admin': bool(row['is_admin']),
        }
        for row in rows
    ]

    stats = {
        'total_users': len(rows),
        'active_users': sum(1 for row in rows if not row['is_blocked']),
        'blocked_users': sum(1 for row in rows if row['is_blocked']),
        'used_today': sum(
            1 for row in rows
            if (row['last_active'] or '').startswith(today)
        ),
    }

    conn.close()
    return jsonify(stats=stats, users=users)


def web_admin_required(fn):
    @wraps(fn)
    def wrapped(*args, **kwargs):
        phone = session.get('admin_phone', '')
        if phone not in ADMIN_PHONES:
            return redirect(url_for('admin_login'))
        return fn(*args, **kwargs)
    return wrapped


@app.route('/admin/login', methods=['GET', 'POST'])
def admin_login():
    error = ''
    if request.method == 'POST':
        phone = request.form.get('phone', '').strip()
        password = request.form.get('password', '')
        conn = get_db()
        user = conn.execute('SELECT * FROM users WHERE phone=?', (phone,)).fetchone()
        conn.close()

        if not user or not (user['is_admin'] or phone in ADMIN_PHONES):
            error = 'Admin topilmadi.'
        elif not verify_password(user['password_hash'], password):
            error = 'Parol noto‘g‘ri.'
        else:
            session.clear()
            session['admin_phone'] = phone
            return redirect(url_for('admin_page'))

    return render_template_string('''
<!doctype html>
<html lang="uz">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PixDrop Admin</title>
  <style>
    *{box-sizing:border-box} body{margin:0;min-height:100vh;display:grid;place-items:center;background:#030b12;color:#eef7fa;font-family:Arial,sans-serif;padding:20px}
    .box{width:min(430px,100%);background:#071a24;border:1px solid #0c766f;border-radius:26px;padding:30px;box-shadow:0 24px 70px #0009}
    h1{margin:0 0 8px;font-size:30px}.brand{color:#19d7c2}.muted{color:#91a4ae;margin:0 0 24px}.err{background:#5d1d2a;color:#ffd7df;padding:12px;border-radius:12px;margin-bottom:15px}
    label{display:block;margin:14px 0 7px;color:#b8c8cf}input{width:100%;padding:15px;border-radius:14px;border:1px solid #24424d;background:#06141d;color:#fff;font-size:16px}
    button{width:100%;margin-top:22px;padding:15px;border:0;border-radius:14px;background:linear-gradient(90deg,#26d9ef,#35eb91);font-size:17px;font-weight:800;color:#031119;cursor:pointer}
  </style>
</head>
<body><form class="box" method="post">
  <h1><span class="brand">Pix</span>Drop Admin</h1>
  <p class="muted">Admin telefon va paroli bilan kiring</p>
  {% if error %}<div class="err">{{ error }}</div>{% endif %}
  <label>Telefon raqam</label><input name="phone" value="{{ admin_phone }}" required>
  <label>Parol</label><input name="password" type="password" required autofocus>
  <button type="submit">KIRISH</button>
</form></body></html>
    ''', error=error, admin_phone=PRIMARY_ADMIN_PHONE)


@app.get('/admin/logout')
def admin_logout():
    session.clear()
    return redirect(url_for('admin_login'))


@app.post('/admin/web/toggle')
@web_admin_required
def admin_web_toggle():
    phone = request.form.get('user_phone', '').strip()
    action = request.form.get('action', '').strip()
    conn = get_db()
    user = conn.execute('SELECT 1 FROM users WHERE phone=?', (phone,)).fetchone()
    if not user:
        session['admin_notice'] = 'Foydalanuvchi topilmadi.'
    elif action == 'enable':
        end = (datetime.now() + timedelta(days=30)).strftime('%Y-%m-%d %H:%M:%S')
        conn.execute('UPDATE users SET is_blocked=0, sub_end_date=? WHERE phone=?', (end, phone))
        conn.commit()
        session['admin_notice'] = f'{phone}: 30 kunlik obuna yoqildi.'
    elif action == 'disable' and phone not in ADMIN_PHONES:
        conn.execute('UPDATE users SET is_blocked=1 WHERE phone=?', (phone,))
        conn.commit()
        session['admin_notice'] = f'{phone}: bloklandi.'
    else:
        session['admin_notice'] = 'Amal bajarilmadi.'
    conn.close()
    return redirect(url_for('admin_page'))


@app.get('/admin')
@web_admin_required
def admin_page():
    conn = get_db()
    rows = conn.execute('''
        SELECT phone,name,district,is_blocked,sub_end_date,last_active,is_admin
        FROM users ORDER BY is_admin DESC, last_active DESC, name
    ''').fetchall()
    conn.close()
    users = [dict(row) for row in rows]
    notice = session.pop('admin_notice', '')
    stats = {
        'total': len(users),
        'active': sum(1 for user in users if not user['is_blocked']),
        'blocked': sum(1 for user in users if user['is_blocked']),
    }
    return render_template_string('''
<!doctype html>
<html lang="uz">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width,initial-scale=1">
  <title>PixDrop boshqaruvi</title>
  <style>
    *{box-sizing:border-box}body{margin:0;background:#030b12;color:#edf7fa;font-family:Arial,sans-serif;padding:22px}.wrap{max-width:1150px;margin:auto}
    header{display:flex;align-items:center;justify-content:space-between;gap:20px;margin-bottom:22px}h1{margin:0}.brand{color:#19d7c2}.logout{color:#7de4d9;text-decoration:none}
    .stats{display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:20px}.stat{background:#071a24;border:1px solid #173844;border-radius:18px;padding:18px}.stat b{display:block;font-size:28px;color:#23ddc7}.stat span{color:#8fa5af}
    .notice{background:#0c493f;border:1px solid #18aa94;padding:13px 16px;border-radius:14px;margin-bottom:16px}.table{overflow:auto;background:#071a24;border:1px solid #173844;border-radius:20px}table{width:100%;border-collapse:collapse;min-width:850px}th,td{text-align:left;padding:14px;border-bottom:1px solid #15313b}th{color:#7edfd5;font-size:13px}td{color:#dce9ed}.active{color:#43e39f}.blocked{color:#ff758c}
    form{display:inline}button{border:0;border-radius:10px;padding:9px 12px;font-weight:800;cursor:pointer}.enable{background:#34dda0;color:#032118}.disable{background:#ff667f;color:#28030a}.admin{color:#ffd166}
    @media(max-width:650px){body{padding:12px}.stats{grid-template-columns:1fr}header{align-items:flex-start;flex-direction:column}}
  </style>
</head>
<body><div class="wrap">
  <header><div><h1><span class="brand">Pix</span>Drop boshqaruvi</h1><div style="color:#8fa5af;margin-top:5px">Yangi foydalanuvchiga avtomatik 30 kun bepul</div></div><a class="logout" href="{{ url_for('admin_logout') }}">Chiqish</a></header>
  <div class="stats"><div class="stat"><b>{{ stats.total }}</b><span>Jami foydalanuvchi</span></div><div class="stat"><b>{{ stats.active }}</b><span>Faol</span></div><div class="stat"><b>{{ stats.blocked }}</b><span>Bloklangan</span></div></div>
  {% if notice %}<div class="notice">{{ notice }}</div>{% endif %}
  <div class="table"><table><thead><tr><th>Ism</th><th>Telefon</th><th>Hudud</th><th>Holat</th><th>Obuna tugashi</th><th>Oxirgi faollik</th><th>Amal</th></tr></thead><tbody>
  {% for user in users %}<tr><td>{{ user.name or '—' }}{% if user.is_admin %} <span class="admin">ADMIN</span>{% endif %}</td><td>{{ user.phone }}</td><td>{{ user.district or '—' }}</td><td class="{{ 'blocked' if user.is_blocked else 'active' }}">{{ 'Bloklangan' if user.is_blocked else 'Faol' }}</td><td>{{ user.sub_end_date or '—' }}</td><td>{{ user.last_active or '—' }}</td><td>
    {% if not user.is_admin %}<form method="post" action="{{ url_for('admin_web_toggle') }}"><input type="hidden" name="user_phone" value="{{ user.phone }}"><input type="hidden" name="action" value="{{ 'enable' if user.is_blocked else 'disable' }}"><button class="{{ 'enable' if user.is_blocked else 'disable' }}">{{ '30 kun yoqish' if user.is_blocked else 'Bloklash' }}</button></form>{% endif %}
  </td></tr>{% else %}<tr><td colspan="7">Foydalanuvchi yo‘q.</td></tr>{% endfor %}
  </tbody></table></div>
</div></body></html>
    ''', users=users, stats=stats, notice=notice)


if __name__ == '__main__':
    port = int(os.environ.get('PORT', '5000'))
    print(f'🚀 PixDrop server AI v2 ishga tushdi: http://0.0.0.0:{port}')
    serve(app, host='0.0.0.0', port=port, threads=20)

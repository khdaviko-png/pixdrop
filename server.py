import os, re, sqlite3, secrets
from datetime import datetime, timedelta
from functools import wraps
from flask import Flask, request, jsonify, send_from_directory
from werkzeug.security import generate_password_hash, check_password_hash
from werkzeug.utils import secure_filename
from waitress import serve

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
ADMIN_PHONE = '+998995442358'
TOKEN_DAYS = 90
os.makedirs(UPLOAD_FOLDER, exist_ok=True)

app = Flask(__name__)
app.config['MAX_CONTENT_LENGTH'] = 30 * 1024 * 1024


def now_str(): return datetime.now().strftime('%Y-%m-%d %H:%M:%S')

def get_db():
    conn = sqlite3.connect(DB_PATH, timeout=30, check_same_thread=False)
    conn.row_factory = sqlite3.Row
    conn.execute('PRAGMA journal_mode=WAL;')
    conn.execute('PRAGMA foreign_keys=ON;')
    return conn

def table_columns(conn, table): return {r['name'] for r in conn.execute(f'PRAGMA table_info({table})').fetchall()}

def ensure_column(conn, table, name, definition):
    if name not in table_columns(conn, table): conn.execute(f'ALTER TABLE {table} ADD COLUMN {name} {definition}')

def init_db():
    conn=get_db()
    conn.execute('''CREATE TABLE IF NOT EXISTS users (phone TEXT PRIMARY KEY,name TEXT,district TEXT,password_hash TEXT,is_blocked INTEGER DEFAULT 1,sub_end_date TEXT,last_active TEXT,is_admin INTEGER DEFAULT 0)''')
    ensure_column(conn,'users','is_admin','INTEGER DEFAULT 0')
    conn.execute('''CREATE TABLE IF NOT EXISTS auth_tokens (token TEXT PRIMARY KEY,phone TEXT NOT NULL,expires_at TEXT NOT NULL,created_at TEXT NOT NULL,FOREIGN KEY(phone) REFERENCES users(phone) ON DELETE CASCADE)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS products (id INTEGER PRIMARY KEY AUTOINCREMENT,shop_id TEXT NOT NULL,name TEXT NOT NULL,price TEXT DEFAULT '0',code TEXT,image_path TEXT,color_data BLOB,visual_data BLOB,quantity REAL DEFAULT 0,created_at TEXT,FOREIGN KEY(shop_id) REFERENCES users(phone) ON DELETE CASCADE)''')
    for col,definition in [('quantity','REAL DEFAULT 0'),('created_at','TEXT'),('visual_data','BLOB')]: ensure_column(conn,'products',col,definition)
    conn.execute('''CREATE TABLE IF NOT EXISTS product_images (id INTEGER PRIMARY KEY AUTOINCREMENT,product_id INTEGER NOT NULL,image_path TEXT NOT NULL,sort_order INTEGER DEFAULT 0,FOREIGN KEY(product_id) REFERENCES products(id) ON DELETE CASCADE)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS catalog_products (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT NOT NULL,price TEXT DEFAULT '0',code TEXT,image_path TEXT,color_data BLOB,visual_data BLOB,created_at TEXT,updated_at TEXT)''')
    ensure_column(conn,'catalog_products','visual_data','BLOB')
    conn.execute('''CREATE TABLE IF NOT EXISTS catalog_images (id INTEGER PRIMARY KEY AUTOINCREMENT,catalog_product_id INTEGER NOT NULL,image_path TEXT NOT NULL,sort_order INTEGER DEFAULT 0,FOREIGN KEY(catalog_product_id) REFERENCES catalog_products(id) ON DELETE CASCADE)''')
    conn.execute('''CREATE TABLE IF NOT EXISTS search_stats (id INTEGER PRIMARY KEY AUTOINCREMENT,phone TEXT,product_name TEXT NOT NULL,search_count INTEGER DEFAULT 1,last_searched TEXT,UNIQUE(phone,product_name))''')
    conn.execute('''CREATE TABLE IF NOT EXISTS global_products (id INTEGER PRIMARY KEY AUTOINCREMENT,name TEXT,default_price TEXT,code TEXT,image_path TEXT,color_data BLOB)''')
    if conn.execute('SELECT COUNT(*) c FROM catalog_products').fetchone()['c']==0:
        for r in conn.execute('SELECT name,default_price,code,image_path,color_data FROM global_products').fetchall():
            conn.execute('''INSERT INTO catalog_products(name,price,code,image_path,color_data,created_at,updated_at) VALUES(?,?,?,?,?,?,?)''',(r['name'],r['default_price'],r['code'],r['image_path'],r['color_data'],now_str(),now_str()))
    conn.execute('CREATE INDEX IF NOT EXISTS idx_products_shop ON products(shop_id)')
    conn.execute('CREATE INDEX IF NOT EXISTS idx_catalog_name ON catalog_products(name)')
    conn.execute('UPDATE users SET is_admin=1 WHERE phone=?',(ADMIN_PHONE,))
    conn.commit(); conn.close()

init_db()

def validate_phone(phone): return re.fullmatch(r'\+998\d{9}',phone or '') is not None

def issue_token(conn,phone):
    token=secrets.token_urlsafe(32); exp=(datetime.now()+timedelta(days=TOKEN_DAYS)).strftime('%Y-%m-%d %H:%M:%S')
    conn.execute('INSERT INTO auth_tokens(token,phone,expires_at,created_at) VALUES(?,?,?,?)',(token,phone,exp,now_str())); return token

def subscription_state(conn,phone):
    r=conn.execute('SELECT phone,is_blocked,sub_end_date,is_admin FROM users WHERE phone=?',(phone,)).fetchone()
    if not r:return None,404
    if r['is_admin'] or phone==ADMIN_PHONE:return {'status':'active','days_left':9999,'warning':None},200
    if r['is_blocked']:return {'status':'blocked','message':'Akkaunt bloklangan. Admin bilan bog\'laning.'},403
    if not r['sub_end_date']:return {'status':'blocked','message':'Obuna aktiv emas. Admin bilan bog\'laning.'},403
    try:end=datetime.strptime(r['sub_end_date'],'%Y-%m-%d %H:%M:%S')
    except:return {'status':'blocked','message':'Obuna sanasi xato.'},403
    now=datetime.now()
    if now>end:
        conn.execute('UPDATE users SET is_blocked=1 WHERE phone=?',(phone,)); conn.commit(); return {'status':'blocked','message':'Obuna muddati tugadi. Admin bilan bog\'laning.'},403
    days=max(1,(end-now).days+1)
    return {'status':'active','days_left':days,'warning':f'Diqqat! Obunangiz tugashiga {days} kun qoldi.' if days<=3 else None,'sub_end_date':r['sub_end_date']},200

def bearer_token():
    v=request.headers.get('Authorization',''); return v[7:].strip() if v.lower().startswith('bearer ') else ''

def auth_required(admin=False):
    def deco(fn):
        @wraps(fn)
        def wrapped(*args,**kwargs):
            token=bearer_token()
            if not token:return jsonify(status='error',message='Token kerak.'),401
            conn=get_db(); r=conn.execute('''SELECT t.phone,t.expires_at,u.is_admin FROM auth_tokens t JOIN users u ON u.phone=t.phone WHERE t.token=?''',(token,)).fetchone()
            if not r:conn.close(); return jsonify(status='error',message='Sessiya topilmadi.'),401
            if datetime.now()>datetime.strptime(r['expires_at'],'%Y-%m-%d %H:%M:%S'):
                conn.execute('DELETE FROM auth_tokens WHERE token=?',(token,)); conn.commit(); conn.close(); return jsonify(status='error',message='Sessiya tugagan.'),401
            sub,code=subscription_state(conn,r['phone']); is_admin=bool(r['is_admin'] or r['phone']==ADMIN_PHONE)
            if code!=200 and not is_admin:conn.close(); return jsonify(sub),code
            if admin and not is_admin:conn.close(); return jsonify(status='error',message='Admin ruxsati kerak.'),403
            conn.execute('UPDATE users SET last_active=? WHERE phone=?',(now_str(),r['phone'])); conn.commit(); conn.close()
            request.user_phone=r['phone']; request.user_is_admin=is_admin; request.subscription=sub
            return fn(*args,**kwargs)
        return wrapped
    return deco

def save_uploaded(file_obj,prefix='img'):
    ext=os.path.splitext(secure_filename(file_obj.filename or ''))[1].lower() or '.jpg'; name=f'{prefix}_{datetime.now().strftime("%Y%m%d%H%M%S%f")}_{secrets.token_hex(4)}{ext}'; path=os.path.join(UPLOAD_FOLDER,name); file_obj.save(path); return name,path

def product_json(r,images=None):
    imgs=images or ([] if not r['image_path'] else [r['image_path']]); return {'id':r['id'],'name':r['name'],'price':r['price'],'code':r['code'] or '','image_path':r['image_path'] or '','images':imgs,'quantity':r['quantity'] or 0,'created_at':r['created_at']}

def ensure_visual_for_row(conn,row):
    if row['visual_data'] or not row['image_path'] or not get_visual_fingerprint:return row['visual_data']
    path=os.path.join(UPLOAD_FOLDER,row['image_path'])
    if not os.path.exists(path):return None
    try:
        data=get_visual_fingerprint(path)
        if data:conn.execute('UPDATE products SET visual_data=? WHERE id=?',(data,row['id'])); conn.commit()
        return data
    except:return None

@app.get('/health')
def health():return jsonify(status='ok',service='PixDrop API v2',ai=bool(rank_matches),time=now_str())

@app.post('/register')
def register():
    phone=request.form.get('phone','').strip(); name=request.form.get('name','').strip(); district=request.form.get('district','').strip(); password=request.form.get('password',''); errors=[]
    if not name:errors.append('Ism va familiya kerak.')
    if not validate_phone(phone):errors.append('Telefon raqami +998901234567 formatida bo\'lsin.')
    if not district:errors.append('Tuman yoki shahar kerak.')
    if len(password)<4:errors.append('Parol kamida 4 ta belgidan iborat bo\'lsin.')
    if errors:return jsonify(status='error',message=' '.join(errors),errors=errors),400
    conn=get_db()
    if conn.execute('SELECT 1 FROM users WHERE phone=?',(phone,)).fetchone():conn.close(); return jsonify(status='error',message='Bu raqam ro\'yxatdan o\'tgan.'),400
    adm=1 if phone==ADMIN_PHONE else 0; blocked=0 if adm else 1; sub=(datetime.now()+timedelta(days=3650)).strftime('%Y-%m-%d %H:%M:%S') if adm else None
    conn.execute('INSERT INTO users(phone,name,district,password_hash,is_blocked,sub_end_date,last_active,is_admin) VALUES(?,?,?,?,?,?,?,?)',(phone,name,district,generate_password_hash(password),blocked,sub,now_str(),adm)); conn.commit(); conn.close(); return jsonify(status='success',message='Ro\'yxatdan o\'tdingiz. Admin obunani yoqishini kuting!')

@app.post('/login')
def login():
    phone=request.form.get('phone','').strip(); password=request.form.get('password',''); conn=get_db(); u=conn.execute('SELECT * FROM users WHERE phone=?',(phone,)).fetchone()
    if not u or not check_password_hash(u['password_hash'],password):conn.close(); return jsonify(status='error',message='Telefon yoki parol xato!'),401
    sub,code=subscription_state(conn,phone)
    if code!=200 and not (u['is_admin'] or phone==ADMIN_PHONE):conn.close(); return jsonify(sub),code
    token=issue_token(conn,phone); conn.commit(); conn.close(); return jsonify(status='success',token=token,user={'phone':u['phone'],'name':u['name'],'district':u['district'],'is_admin':bool(u['is_admin'] or phone==ADMIN_PHONE)},subscription=sub)

@app.get('/auth/check')
@auth_required()
def auth_check():
    conn=get_db(); u=conn.execute('SELECT phone,name,district,is_admin FROM users WHERE phone=?',(request.user_phone,)).fetchone(); conn.close(); return jsonify(status='success',user={'phone':u['phone'],'name':u['name'],'district':u['district'],'is_admin':bool(u['is_admin'] or u['phone']==ADMIN_PHONE)},subscription=request.subscription)

@app.post('/logout')
def logout():
    token=bearer_token()
    if token:
        conn=get_db(); conn.execute('DELETE FROM auth_tokens WHERE token=?',(token,)); conn.commit(); conn.close()
    return jsonify(status='success')

@app.get('/uploads/<path:name>')
def uploads(name):return send_from_directory(UPLOAD_FOLDER,name)

@app.get('/products')
@auth_required()
def products():
    shop_id=request.args.get('shop_id','').strip() or request.user_phone
    if not request.user_is_admin:shop_id=request.user_phone
    conn=get_db(); rows=conn.execute('SELECT * FROM products WHERE shop_id=? ORDER BY name COLLATE NOCASE',(shop_id,)).fetchall(); out=[]
    for r in rows:
        imgs=[x['image_path'] for x in conn.execute('SELECT image_path FROM product_images WHERE product_id=? ORDER BY sort_order,id',(r['id'],)).fetchall()]; out.append(product_json(r,imgs))
    conn.close(); return jsonify(out)

@app.post('/add_product')
@auth_required()
def add_product():
    name=request.form.get('name','').strip(); price=request.form.get('price','0').strip(); code=request.form.get('code','').strip(); qty=request.form.get('quantity',request.form.get('qty','0'))
    if not name:return jsonify(status='error',message='Mahsulot nomi kerak.'),400
    try:qty=float(qty or 0)
    except:qty=0
    shop_id=request.form.get('shop_id','').strip() if request.user_is_admin else request.user_phone
    if not shop_id:shop_id=request.user_phone
    files=request.files.getlist('images') or ([request.files['image']] if 'image' in request.files else []); saved=[]; color=None; visual=None
    for f in files:
        if f and f.filename:
            n,p=save_uploaded(f,'product'); saved.append(n)
            if color is None and get_color_fingerprint:
                try:color=get_color_fingerprint(p)
                except:pass
            if visual is None and get_visual_fingerprint:
                try:visual=get_visual_fingerprint(p)
                except:pass
    conn=get_db(); cur=conn.execute('''INSERT INTO products(shop_id,name,price,code,image_path,color_data,visual_data,quantity,created_at) VALUES(?,?,?,?,?,?,?,?,?)''',(shop_id,name,price,code,saved[0] if saved else '',color,visual,qty,now_str())); pid=cur.lastrowid
    for i,n in enumerate(saved):conn.execute('INSERT INTO product_images(product_id,image_path,sort_order) VALUES(?,?,?)',(pid,n,i))
    conn.commit(); conn.close(); return jsonify(status='success',id=pid,message='Mahsulot qo\'shildi.')

@app.post('/update_price')
@auth_required()
def update_price():
    pid=request.form.get('id') or request.form.get('product_id'); price=request.form.get('price','').strip(); conn=get_db(); r=conn.execute('SELECT shop_id FROM products WHERE id=?',(pid,)).fetchone()
    if not r:conn.close(); return jsonify(status='error',message='Mahsulot topilmadi.'),404
    if not request.user_is_admin and r['shop_id']!=request.user_phone:conn.close(); return jsonify(status='error',message='Ruxsat yo\'q.'),403
    conn.execute('UPDATE products SET price=? WHERE id=?',(price,pid)); conn.commit(); conn.close(); return jsonify(status='success')

@app.post('/delete_product')
@auth_required()
def delete_product():
    pid=request.form.get('id') or request.form.get('product_id'); conn=get_db(); r=conn.execute('SELECT * FROM products WHERE id=?',(pid,)).fetchone()
    if not r:conn.close(); return jsonify(status='error',message='Mahsulot topilmadi.'),404
    if not request.user_is_admin and r['shop_id']!=request.user_phone:conn.close(); return jsonify(status='error',message='Ruxsat yo\'q.'),403
    conn.execute('DELETE FROM products WHERE id=?',(pid,)); conn.commit(); conn.close(); return jsonify(status='success')

@app.post('/predict')
@auth_required()
def predict():
    if 'image' not in request.files:return jsonify(status='error',message='Rasm kerak.'),400
    if not rank_matches:return jsonify(status='error',message='AI engine yuklanmagan.'),503
    _,path=save_uploaded(request.files['image'],'scan')
    try:
        conn=get_db(); rows=conn.execute('SELECT * FROM products WHERE shop_id=?',(request.user_phone,)).fetchall(); plist=[]
        for r in rows:
            visual=ensure_visual_for_row(conn,r); plist.append({'id':r['id'],'name':r['name'],'price':r['price'],'code':r['code'] or '','image_path':r['image_path'] or '','color_data':r['color_data'],'visual_data':visual})
        conn.close(); result=rank_matches(path,plist,top_k=3)
        if result['status']=='empty':return jsonify(status='not_found',message='Omboringizda mahsulot yo\'q.',suggestions=[]),404
        if result['status']=='success':
            m=result['match']; return jsonify(status='success',match=m,name=m['name'],price=m['price'],code=m.get('code',''),score=result['score'],detected=result['detected'],suggestions=result['suggestions'])
        return jsonify(status='similar',message='Aniq topilmadi. O\'xshash mahsulotlardan birini tanlang.',score=result['score'],detected=result['detected'],suggestions=result['suggestions'])
    finally:
        try:os.remove(path)
        except:pass

@app.get('/catalog')
@auth_required()
def catalog():
    q=request.args.get('q','').strip(); conn=get_db(); rows=conn.execute('SELECT * FROM catalog_products WHERE name LIKE ? ORDER BY name COLLATE NOCASE',(q+'%',)).fetchall() if q else conn.execute('SELECT * FROM catalog_products ORDER BY name COLLATE NOCASE').fetchall(); out=[]
    for r in rows:
        imgs=[x['image_path'] for x in conn.execute('SELECT image_path FROM catalog_images WHERE catalog_product_id=? ORDER BY sort_order,id',(r['id'],)).fetchall()]; out.append({'id':r['id'],'name':r['name'],'price':r['price'],'code':r['code'] or '','image_path':r['image_path'] or '','images':imgs})
    conn.close(); return jsonify(out)

@app.post('/catalog/search')
@auth_required()
def catalog_search_stat():
    name=request.form.get('name','').strip()
    if name:
        conn=get_db(); conn.execute('''INSERT INTO search_stats(phone,product_name,search_count,last_searched) VALUES(?,?,1,?) ON CONFLICT(phone,product_name) DO UPDATE SET search_count=search_count+1,last_searched=excluded.last_searched''',(request.user_phone,name,now_str())); conn.commit(); conn.close()
    return jsonify(status='success')

@app.get('/catalog/popular')
@auth_required()
def catalog_popular():
    conn=get_db(); rows=conn.execute('SELECT product_name,SUM(search_count) cnt FROM search_stats GROUP BY product_name ORDER BY cnt DESC LIMIT 20').fetchall(); conn.close(); return jsonify([{'name':r['product_name'],'search_count':r['cnt']} for r in rows])

@app.post('/admin/catalog/add')
@auth_required(admin=True)
def admin_catalog_add():
    name=request.form.get('name','').strip(); price=request.form.get('price','0').strip(); code=request.form.get('code','').strip()
    if not name:return jsonify(status='error',message='Nomi kerak.'),400
    saved=[]; color=None; visual=None
    for f in request.files.getlist('images'):
        if f and f.filename:
            n,p=save_uploaded(f,'catalog'); saved.append(n)
            if color is None and get_color_fingerprint:
                try:color=get_color_fingerprint(p)
                except:pass
            if visual is None and get_visual_fingerprint:
                try:visual=get_visual_fingerprint(p)
                except:pass
    conn=get_db(); cur=conn.execute('''INSERT INTO catalog_products(name,price,code,image_path,color_data,visual_data,created_at,updated_at) VALUES(?,?,?,?,?,?,?,?)''',(name,price,code,saved[0] if saved else '',color,visual,now_str(),now_str())); pid=cur.lastrowid
    for i,n in enumerate(saved):conn.execute('INSERT INTO catalog_images(catalog_product_id,image_path,sort_order) VALUES(?,?,?)',(pid,n,i))
    conn.commit(); conn.close(); return jsonify(status='success',id=pid)

@app.post('/admin/catalog/update')
@auth_required(admin=True)
def admin_catalog_update():
    pid=request.form.get('id'); name=request.form.get('name'); price=request.form.get('price'); code=request.form.get('code'); conn=get_db(); r=conn.execute('SELECT * FROM catalog_products WHERE id=?',(pid,)).fetchone()
    if not r:conn.close(); return jsonify(status='error',message='Topilmadi.'),404
    conn.execute('UPDATE catalog_products SET name=?,price=?,code=?,updated_at=? WHERE id=?',(name if name is not None else r['name'],price if price is not None else r['price'],code if code is not None else r['code'],now_str(),pid)); conn.commit(); conn.close(); return jsonify(status='success')

@app.post('/admin/catalog/delete')
@auth_required(admin=True)
def admin_catalog_delete():
    pid=request.form.get('id'); conn=get_db(); r=conn.execute('SELECT 1 FROM catalog_products WHERE id=?',(pid,)).fetchone()
    if not r:conn.close(); return jsonify(status='error',message='Topilmadi.'),404
    conn.execute('DELETE FROM catalog_products WHERE id=?',(pid,)); conn.commit(); conn.close(); return jsonify(status='success')

@app.post('/admin/toggle_subscription')
@auth_required(admin=True)
def toggle_subscription():
    phone=request.form.get('user_phone','').strip(); action=request.form.get('action','').strip(); conn=get_db()
    if not conn.execute('SELECT 1 FROM users WHERE phone=?',(phone,)).fetchone():conn.close(); return jsonify(status='error',message='Foydalanuvchi topilmadi.'),404
    if action=='enable':end=(datetime.now()+timedelta(days=30)).strftime('%Y-%m-%d %H:%M:%S'); conn.execute('UPDATE users SET is_blocked=0,sub_end_date=? WHERE phone=?',(end,phone)); msg='Obuna 30 kunga yoqildi.'
    elif action=='disable':conn.execute('UPDATE users SET is_blocked=1 WHERE phone=?',(phone,)); msg='Foydalanuvchi bloklandi.'
    else:conn.close(); return jsonify(status='error',message='action enable yoki disable bo\'lsin.'),400
    conn.commit(); conn.close(); return jsonify(status='success',message=msg)

@app.get('/admin/users_stat')
@auth_required(admin=True)
def users_stat():
    district=request.args.get('district',''); status=request.args.get('status',''); conn=get_db(); q='SELECT phone,name,district,is_blocked,sub_end_date,last_active,is_admin FROM users WHERE 1=1'; params=[]
    if district:q+=' AND district=?'; params.append(district)
    if status=='active':q+=' AND is_blocked=0'
    elif status=='blocked':q+=' AND is_blocked=1'
    rows=conn.execute(q,params).fetchall(); today=datetime.now().strftime('%Y-%m-%d'); users=[{'phone':u['phone'],'name':u['name'],'district':u['district'],'is_blocked':bool(u['is_blocked']),'sub_end_date':u['sub_end_date'],'last_active':u['last_active'],'is_admin':bool(u['is_admin'])} for u in rows]; stats={'total_users':len(rows),'active_users':sum(1 for u in rows if not u['is_blocked']),'blocked_users':sum(1 for u in rows if u['is_blocked']),'used_today':sum(1 for u in rows if (u['last_active'] or '').startswith(today))}; conn.close(); return jsonify(stats=stats,users=users)

if __name__=='__main__':
    print('🚀 PixDrop server AI v2 ishga tushdi: http://0.0.0.0:5000')
    serve(app,host='0.0.0.0',port=int(os.environ.get('PORT','5000')),threads=20)

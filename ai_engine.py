import cv2
import numpy as np
import easyocr
from rapidfuzz import fuzz
import re
import time
import logging
import threading
from functools import lru_cache

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s: %(message)s')
logger = logging.getLogger('PixDropAI')

class AIConfig:
    DB_HIST_SIZE = 24
    CACHE_SIZE = 4096
    USE_GPU = True
    EXACT_SCORE = 84.0
    SIMILAR_SCORE = 45.0

KNOWN_BRANDS = ['schneider','delixi','abb','iek','legrand','chint','dekraft','ekf','tengen','siemens','hager','eaton','hyundai','ls','noark','eti','dream light','dreamlight','aqara','sonoff','esenco','weicon','kvt']
CATEGORY_WORDS = {
    'breaker':['avtomat','автомат','breaker','mcb','cb','dz47','ic60','easy9','act9'],
    'rcd':['uzo','узо','rcd','rccb'],
    'rcbo':['dif','диф','rcbo','difavtomat','дифавтомат'],
    'contactor':['kontaktor','контактор','contactor','пускатель','starter'],
    'relay':['rele','реле','relay'],
    'stabilizer':['stabilizator','стабилизатор','stabilizer'],
    'driver':['driver','драйвер','blok pitaniya','блок питания','power supply'],
    'lamp':['lampa','лампа','lamp','svetilnik','светильник','light'],
    'cable':['kabel','кабель','cable','sim','провод','wire'],
}
VALID_AMPS = {1,2,3,4,5,6,8,10,13,16,20,25,32,40,50,63,80,100,125,160,200,250,315,400,500,630}
_ocr_lock = threading.Lock()

try:
    reader = easyocr.Reader(['en','ru'], gpu=AIConfig.USE_GPU)
    logger.info('EasyOCR GPU rejimi faollashtirildi.')
except Exception as e:
    logger.warning(f'GPU ishlamadi, CPU rejimiga otildi: {e}')
    reader = easyocr.Reader(['en','ru'], gpu=False)

@lru_cache(maxsize=AIConfig.CACHE_SIZE)
def clean_text(text: str) -> str:
    if not text: return ''
    text = text.lower().replace('ё','е').strip()
    return ' '.join(re.findall(r'[a-z0-9а-я]+', text))

def _compact(text: str) -> str:
    return re.sub(r'[^a-z0-9а-я]+', '', clean_text(text))

def _prepare_for_ocr(image_path: str):
    img = cv2.imread(image_path)
    if img is None: return None
    h,w = img.shape[:2]; longest=max(h,w)
    if longest < 1000:
        scale=min(1.8,1200/max(1,longest)); img=cv2.resize(img,None,fx=scale,fy=scale,interpolation=cv2.INTER_CUBIC)
    elif longest > 1800:
        scale=1800/longest; img=cv2.resize(img,None,fx=scale,fy=scale,interpolation=cv2.INTER_AREA)
    gray=cv2.cvtColor(img,cv2.COLOR_BGR2GRAY)
    return cv2.createCLAHE(clipLimit=2.0,tileGridSize=(8,8)).apply(gray)

def read_ocr_text(image_path: str) -> str:
    if not reader: return ''
    img=_prepare_for_ocr(image_path)
    if img is None: return ''
    try:
        with _ocr_lock:
            parts=reader.readtext(img,detail=0,paragraph=False,decoder='greedy',batch_size=1,workers=0)
        return clean_text(' '.join(str(x) for x in parts))
    except Exception as e:
        logger.warning(f'OCR xatosi: {e}'); return ''

def get_color_fingerprint(image_path: str):
    try:
        img=cv2.imread(image_path)
        if img is None: return None
        img=cv2.resize(img,(150,150)); hsv=cv2.cvtColor(img,cv2.COLOR_BGR2HSV)
        hist=cv2.calcHist([hsv],[0,1],None,[AIConfig.DB_HIST_SIZE,AIConfig.DB_HIST_SIZE],[0,180,0,256])
        cv2.normalize(hist,hist,0,1,cv2.NORM_MINMAX)
        return hist.astype(np.float32).tobytes()
    except Exception as e:
        logger.warning(f'Rang fingerprint xatosi: {e}'); return None

def get_visual_fingerprint(image_path: str):
    try:
        img=cv2.imread(image_path,cv2.IMREAD_GRAYSCALE)
        if img is None: return None
        img=cv2.resize(img,(32,32),interpolation=cv2.INTER_AREA)
        dct=cv2.dct(np.float32(img))[:8,:8]; vals=dct.flatten(); med=np.median(vals[1:])
        return np.packbits((vals>med).astype(np.uint8)).tobytes()
    except Exception as e:
        logger.warning(f'Visual fingerprint xatosi: {e}'); return None

def _color_similarity(a,b):
    if not a or not b: return 0.0
    try:
        aa=np.frombuffer(a,dtype=np.float32); bb=np.frombuffer(b,dtype=np.float32)
        sa=int(np.sqrt(len(aa))); sb=int(np.sqrt(len(bb)))
        ha=aa.reshape(sa,sa); hb=bb.reshape(sb,sb)
        if sa!=sb: hb=cv2.resize(hb,(sa,sa))
        return float(max(0,min(100,cv2.compareHist(ha,hb,cv2.HISTCMP_CORREL)*100)))
    except Exception: return 0.0

def _visual_similarity(a,b):
    if not a or not b: return 0.0
    try:
        aa=np.unpackbits(np.frombuffer(a,dtype=np.uint8))[:64]; bb=np.unpackbits(np.frombuffer(b,dtype=np.uint8))[:64]
        if len(aa)!=64 or len(bb)!=64: return 0.0
        return max(0.0,100.0*(1.0-np.count_nonzero(aa!=bb)/64.0))
    except Exception: return 0.0

def _detect_category(text):
    t=clean_text(text)
    for cat,words in CATEGORY_WORDS.items():
        if any(clean_text(w) in t for w in words): return cat
    return None

def _extract_brand(text):
    t=clean_text(text); compact=t.replace(' ','')
    for brand in KNOWN_BRANDS:
        b=clean_text(brand)
        if b in t or b.replace(' ','') in compact: return b
    return None

def _extract_amps(text):
    raw=(text or '').upper().replace(',','.'); found=set(); curve=None
    for m in re.finditer(r'\b([BCD])\s*[- ]?\s*(\d{1,3})\b',raw):
        v=int(m.group(2))
        if v in VALID_AMPS: curve=m.group(1); found.add(v)
    for m in re.finditer(r'\b(\d{1,3})\s*A\b',raw):
        v=int(m.group(1))
        if v in VALID_AMPS: found.add(v)
    return sorted(found),curve

def _extract_poles(text):
    m=re.search(r'\b([1-4])P(?:\+N)?\b',(text or '').upper().replace(' ','')); return m.group(0) if m else None

def _extract_voltage(text):
    vals=[]
    for m in re.finditer(r'\b(\d{2,4})V\b',(text or '').upper().replace(' ','')):
        v=int(m.group(1))
        if 12<=v<=1000: vals.append(v)
    return sorted(set(vals))

def _extract_model_tokens(text):
    tokens=re.findall(r'[A-ZА-Я0-9]{3,}',(text or '').upper().replace('-',' ')); out=set()
    for token in tokens:
        if not (re.search(r'[A-ZА-Я]',token) and re.search(r'\d',token)): continue
        if re.fullmatch(r'[BCD]\d{1,3}',token) or re.fullmatch(r'\d{2,4}V',token) or re.fullmatch(r'[1-4]P',token): continue
        out.add(token)
    return sorted(out)

def extract_features(text):
    amps,curve=_extract_amps(text)
    return {'brand':_extract_brand(text),'category':_detect_category(text),'amps':amps,'curve':curve,'poles':_extract_poles(text),'voltage':_extract_voltage(text),'models':_extract_model_tokens(text)}

def _feature_score(scan,product):
    bonus=0.0; reasons=[]; sa,pa=set(scan['amps']),set(product['amps'])
    if sa and pa:
        if sa&pa: bonus+=15; reasons.append(f'tok {sorted(sa&pa)[0]}A')
        else: bonus-=32
    if scan['curve'] and product['curve']:
        if scan['curve']==product['curve']: bonus+=6; reasons.append(f"{scan['curve']} xarakteristika")
        else: bonus-=10
    if scan['poles'] and product['poles']:
        if scan['poles']==product['poles']: bonus+=7; reasons.append(scan['poles'])
        else: bonus-=12
    if scan['brand'] and product['brand']:
        if scan['brand']==product['brand']: bonus+=9; reasons.append(scan['brand'].upper())
        else: bonus-=10
    if scan['category'] and product['category']:
        bonus += 6 if scan['category']==product['category'] else -14
    sm,pm=set(scan['models']),set(product['models'])
    if sm and pm:
        inter=sm&pm
        if inter: bonus+=18; reasons.append(next(iter(inter)))
        else: bonus-=8
    if set(scan['voltage']) and set(product['voltage']) and set(scan['voltage'])&set(product['voltage']): bonus+=3
    return bonus,reasons

def rank_matches(image_path: str, db_products: list, top_k: int = 3):
    start=time.time()
    if not db_products: return {'status':'empty','score':0.0,'match':None,'suggestions':[],'detected':{}}
    scanned_text=read_ocr_text(image_path); scan_features=extract_features(scanned_text)
    target_color=get_color_fingerprint(image_path); target_visual=get_visual_fingerprint(image_path); scan_compact=_compact(scanned_text)
    ranked=[]
    for product in db_products:
        name=str(product.get('name') or ''); code=str(product.get('code') or ''); text=f'{name} {code}'.strip(); pf=extract_features(text)
        text_score=max(float(fuzz.WRatio(scanned_text,clean_text(text))),float(fuzz.token_set_ratio(scanned_text,clean_text(text)))) if scanned_text and text else 0.0
        visual_score=_visual_similarity(target_visual,product.get('visual_data')); color_score=_color_similarity(target_color,product.get('color_data'))
        score=text_score*0.58+visual_score*0.24+color_score*0.05 if target_visual and product.get('visual_data') else text_score*0.78+color_score*0.05
        bonus,reasons=_feature_score(scan_features,pf); score+=bonus
        cc=_compact(code)
        if cc and len(cc)>=4 and cc in scan_compact: score=max(score,99.0); reasons.insert(0,'artikul aniq')
        sa,pa=set(scan_features['amps']),set(pf['amps'])
        if sa and pa and not(sa&pa): score=min(score,62.0)
        if scan_features['poles'] and pf['poles'] and scan_features['poles']!=pf['poles']: score=min(score,67.0)
        score=max(0,min(100,score))
        ranked.append({'id':product.get('id'),'name':name,'price':product.get('price','0'),'code':code,'image_path':product.get('image_path','') or '','score':round(score,1),'text_score':round(text_score,1),'visual_score':round(visual_score,1),'color_score':round(color_score,1),'reason':', '.join(reasons[:4])})
    ranked.sort(key=lambda x:x['score'],reverse=True); suggestions=ranked[:max(1,top_k)]; best=suggestions[0] if suggestions else None; best_score=float(best['score']) if best else 0.0
    status='success' if best_score>=AIConfig.EXACT_SCORE else ('similar' if suggestions else 'not_found')
    logger.info('AI v2: %.3fs | OCR="%s" | best=%.1f | status=%s',time.time()-start,scanned_text[:120],best_score,status)
    return {'status':status,'score':round(best_score,1),'match':best if status=='success' else None,'suggestions':suggestions,'detected':{'text':scanned_text,**scan_features}}

def find_best_match(image_path: str, db_products: list):
    normalized=[]
    for item in db_products:
        if isinstance(item,dict): normalized.append(item)
        elif isinstance(item,(list,tuple)) and len(item)>=3: normalized.append({'name':item[0],'price':item[1],'color_data':item[2],'code':'','visual_data':None,'image_path':''})
    result=rank_matches(image_path,normalized,top_k=3)
    return (result['match'],result['score']) if result['status']=='success' and result['match'] else (None,result['score'])

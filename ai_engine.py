import cv2
import numpy as np
import easyocr
from rapidfuzz import fuzz
import re
import time
import logging
from functools import lru_cache

logging.basicConfig(level=logging.INFO, format='[%(asctime)s] %(levelname)s: %(message)s')
logger = logging.getLogger('SmartAI')

class AIConfig:
    DB_HIST_SIZE = 24
    MIN_MATCH_SCORE = 35.0
    CACHE_SIZE = 4096
    TEXT_WEIGHT = 0.80
    COLOR_WEIGHT = 0.20
    USE_GPU = True

try:
    reader = easyocr.Reader(['en', 'ru'], gpu=AIConfig.USE_GPU)
    logger.info('EasyOCR GPU rejimi faollashtirildi.')
except Exception as e:
    logger.error(f'GPU xatosi, CPU ga otildi: {e}')
    reader = easyocr.Reader(['en', 'ru'], gpu=False)

@lru_cache(maxsize=AIConfig.CACHE_SIZE)
def clean_text(text: str) -> str:
    if not text:
        return ''
    text = text.lower().strip()
    return ' '.join(re.findall(r'[a-z0-9а-я]+', text))

def get_color_fingerprint(image_path: str):
    try:
        img = cv2.imread(image_path)
        if img is None:
            return None
        img = cv2.resize(img, (150, 150))
        hsv = cv2.cvtColor(img, cv2.COLOR_BGR2HSV)
        hist = cv2.calcHist([hsv], [0, 1], None, [AIConfig.DB_HIST_SIZE, AIConfig.DB_HIST_SIZE], [0, 180, 0, 256])
        cv2.normalize(hist, hist, 0, 1, cv2.NORM_MINMAX)
        return hist.tobytes()
    except Exception as e:
        logger.error(f'Rang olishda xato: {e}')
        return None

def find_best_match(image_path: str, db_products: list):
    if not reader or not db_products:
        return None, 0
    start_time = time.time()
    try:
        raw_result = reader.readtext(image_path, detail=0, paragraph=True)
        scanned_text = clean_text(' '.join(raw_result))
    except Exception as e:
        logger.warning(f'Skanerlash xatosi: {e}')
        scanned_text = ''
    target_dna = get_color_fingerprint(image_path)
    best_match = None
    max_score = 0.0
    for name, price, db_dna_blob in db_products:
        db_name_clean = clean_text(name)
        text_sim = fuzz.token_set_ratio(scanned_text, db_name_clean) if scanned_text else 0.0
        color_sim = 0.0
        if target_dna and db_dna_blob:
            try:
                t_arr = np.frombuffer(target_dna, dtype=np.float32)
                d_arr = np.frombuffer(db_dna_blob, dtype=np.float32)
                t_size = int(np.sqrt(len(t_arr)))
                d_size = int(np.sqrt(len(d_arr)))
                t_h = t_arr.reshape(t_size, t_size)
                d_h = d_arr.reshape(d_size, d_size)
                if t_size != d_size:
                    d_h = cv2.resize(d_h, (t_size, t_size))
                color_sim = max(0, cv2.compareHist(t_h, d_h, cv2.HISTCMP_CORREL) * 100)
            except Exception:
                color_sim = 0.0
        if text_sim > 95:
            current_total = text_sim
        elif not scanned_text:
            current_total = color_sim
        else:
            current_total = (text_sim * AIConfig.TEXT_WEIGHT) + (color_sim * AIConfig.COLOR_WEIGHT)
        if current_total > max_score:
            max_score = current_total
            best_match = {'name': name, 'price': price}
    logger.info(f'AI Tahlili: {time.time()-start_time:.3f}s | Natija: {max_score:.1f}%')
    if max_score >= AIConfig.MIN_MATCH_SCORE:
        return best_match, max_score
    return None, max_score

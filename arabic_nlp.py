import re
import unicodedata
from typing import List, Tuple, Optional
import langdetect
from langdetect import DetectorFactory, detect_langs
# Set seed for consistent results
DetectorFactory.seed = 0

class ArabicTextNormalizer:
    """
    Arabic text normalization component for news processing pipeline.
    Handles preprocessing steps as specified in the requirements.
    """
    
    def __init__(self, normalize_taa_marbouta: bool = False):
        """
        Initialize the normalizer.
        
        Args:
            normalize_taa_marbouta: Whether to convert ة to ه (semantic mode)
        """
        self.normalize_taa_marbouta = normalize_taa_marbouta
        
        # Arabic diacritics (tashkeel) to remove
        self.tashkeel = re.compile(r'[\u064B-\u065F\u0670\u0640]')
        
        # Alef variants to normalize to plain alef (ا)
        self.alef_variants = re.compile(r'[أإآ]')
        
        # Taa marbouta to normalize (optional)
        self.taa_marbouta = re.compile(r'ة')
        
        # Yaa/alef maqsoura to normalize
        self.yaa_alef_maqsoura = re.compile(r'ى')
        
        # Tatweel (kashida) to remove
        self.tatweel = re.compile(r'\u0640')
        
        # Arabic-Indic digits to normalize to Western Arabic numerals
        self.arabic_digits = str.maketrans('٠١٢٣٤٥٦٧٨٩', '0123456789')
        
        # Extended Arabic-Indic digits (Persian/Urdu) 
        self.extended_arabic_digits = str.maketrans('۰۱۲۳۴۵۶۷۸۹', '0123456789')
        
        # Common punctuation normalization
        self.punctuation_patterns = [
            (r'[،،،]+', '،'),  # Multiple Arabic commas
            (r'[؛؛؛]+', '؛'),  # Multiple Arabic semicolons
            (r'[؟؟؟]+', '؟'),  # Multiple Arabic question marks
            (r'[!！!]+', '!'),  # Multiple exclamation marks
            (r'[？?]+', '؟'),  # Mixed question marks
            (r'[\.\.]+', '.'),  # Multiple periods
            (r'[\s\xa0]+', ' '),  # Multiple whitespace including non-breaking space
        ]
        
        # Compile punctuation patterns
        self.punctuation_regex = [(re.compile(pattern), replacement) for pattern, replacement in self.punctuation_patterns]
    
    def normalize(self, text: str) -> str:
        """
        Apply all normalization steps to Arabic text.
        
        Args:
            text: Input Arabic text
            
        Returns:
            Normalized text
        """
        if not text:
            return ""
            
        # 1. Remove tashkeel (diacritics)
        text = self.tashkeel.sub('', text)
        
        # 2. Normalize alef variants: أ إ آ -> ا
        text = self.alef_variants.sub('ا', text)
        
        # 3. Normalize taa marbouta: ة -> ه (if enabled)
        if self.normalize_taa_marbouta:
            text = self.taa_marbouta.sub('ه', text)
        
        # 4. Normalize yaa/alef maqsoura: ى -> ي
        text = self.yaa_alef_maqsoura.sub('ي', text)
        
        # 5. Remove tatweel (kashida)
        text = self.tatweel.sub('', text)
        
        # 6. Normalize Arabic numerals to Western Arabic numerals
        text = text.translate(self.arabic_digits)
        text = text.translate(self.extended_arabic_digits)
        
        # 7. Normalize punctuation
        for pattern, replacement in self.punctuation_regex:
            text = pattern.sub(replacement, text)
        
        # 8. Remove duplicated whitespace
        text = re.sub(r'\s+', ' ', text).strip()
        
        return text
    
    def detect_spam_clickbait(self, text: str) -> float:
        """
        Detect likelihood of spam/clickbait in headlines.
        
        Args:
            text: Input text (typically headline)
            
        Returns:
            Spam score between 0.0 and 1.0
        """
        if not text:
            return 0.0
            
        spam_indicators = [
            # Excessive punctuation
            r'[!?؟]{3,}',
            # ALL CAPS-like patterns (in Arabic context, repeated characters)
            r'(.)\1{4,}',  # Same character repeated 5+ times
            # Common clickbait phrases in Arabic
            r'(صدم|صاعق|لا يصدق|Чем|سينفعك|سيغير|الحقيقة|ما لم يخبرك|ما لا تعرفه)',
            # Excessive numbers or lists
            r'\d+[\.\-]\s*.*?\d+[\.\-]\s*.*?\d+',
            # Religious/political sensationalism
            r'(الله أكبر|الفتنة|المؤامرة|اليهود|الصهيون|الغنائم)',
        ]
        
        score = 0.0
        text_lower = text.lower()
        
        for pattern in spam_indicators:
            if re.search(pattern, text_lower, re.IGNORECASE):
                score += 0.2
                
        # Check for excessive exclamation/question marks
        if len(re.findall(r'[!?؟]', text)) > 3:
            score += 0.3
            
        # Check for repeated words (common in clickbait)
        words = text.split()
        if len(words) > 3:
            unique_words = set(words)
            repetition_ratio = 1.0 - (len(unique_words) / len(words))
            if repetition_ratio > 0.5:
                score += 0.3
                
        return min(score, 1.0)


class LanguageDetector:
    """
    Language detection for Arabic/French/English mixed content.
    """
    
    def __init__(self):
        # Language patterns for quick detection
        self.arabic_pattern = re.compile(r'[\u0600-\u06FF\u0750-\u077F\u08A0-\u08FF]+')
        self.french_pattern = re.compile(r'\b(?:et|ou|mais|donc|or|ni|car| parce que|quelle|quelle|les|des|du|au|aux|un|une|des|ce|cette|cetes|mon|ton|son|ma|ta|sa|mes|tes|ses|nos|vos|leurs)\b', re.IGNORECASE)
        self.english_pattern = re.compile(r'\b(?:the|and|or|but|in|on|at|to|for|of|with|by|is|are|was|were|be|been|have|has|had|do|does|did|will|would|should|could|may|might|must|can)\b', re.IGNORECASE)
        
    def detect_language(self, text: str) -> dict:
        """
        Detect language(s) in text.
        
        Args:
            text: Input text
            
        Returns:
            Dictionary with language detection results
        """
        if not text or not text.strip():
            return {
                'primary': 'unknown',
                'confidence': 0.0,
                'languages': [],
                'is_mixed': False
            }
        
        try:
            # Use langdetect for primary detection
            detected = detect_langs(text)
            
            # Get top prediction
            if detected:
                primary_lang = detected[0].lang
                primary_confidence = detected[0].prob
            else:
                primary_lang = 'unknown'
                primary_confidence = 0.0
                
            # Extract all detected languages with confidence > 0.1
            languages = [{'lang': d.lang, 'confidence': d.prob} for d in detected if d.prob > 0.1]
            
            # Check for mixed content using pattern matching
            arabic_chars = len(self.arabic_pattern.findall(text))
            french_matches = len(self.french_pattern.findall(text))
            english_matches = len(self.english_pattern.findall(text))
            
            total_matches = arabic_chars + french_matches + english_matches
            
            # Determine if content is mixed
            is_mixed = False
            if total_matches > 0:
                arabic_ratio = arabic_chars / max(len(text), 1)
                non_arabic_ratio = (french_matches + english_matches) / max(len(text), 1)
                
                # Consider mixed if significant non-Arabic content
                is_mixed = non_arabic_ratio > 0.1 and arabic_ratio > 0.3
                
            return {
                'primary': primary_lang,
                'confidence': primary_confidence,
                'languages': languages,
                'is_mixed': is_mixed,
                'arabic_chars': arabic_chars,
                'french_matches': french_matches,
                'english_matches': english_matches
            }
            
        except Exception as e:
            # Fallback to pattern-based detection
            return self._fallback_detection(text)
    
    def _fallback_detection(self, text: str) -> dict:
        """
        Fallback language detection using pattern matching.
        """
        arabic_chars = len(self.arabic_pattern.findall(text))
        french_matches = len(self.french_pattern.findall(text))
        english_matches = len(self.english_pattern.findall(text))
        
        total = arabic_chars + french_matches + english_matches
        
        if total == 0:
            return {
                'primary': 'unknown',
                'confidence': 0.0,
                'languages': [],
                'is_mixed': False
            }
        
        # Determine primary language
        if arabic_chars > french_matches and arabic_chars > english_matches:
            primary = 'ar'
            confidence = arabic_chars / total
        elif french_matches > arabic_chars and french_matches > english_matches:
            primary = 'fr'
            confidence = french_matches / total
        elif english_matches > arabic_chars and english_matches > french_matches:
            primary = 'en'
            confidence = english_matches / total
        else:
            # Tie or unclear
            primary = 'mixed'
            confidence = 0.5
            
        # Check if mixed
        is_mixed = (arabic_chars > 0 and (french_matches > 0 or english_matches > 0)) or \
                   (french_matches > 0 and english_matches > 0)
                   
        return {
            'primary': primary,
            'confidence': confidence,
            'languages': [
                {'lang': 'ar', 'confidence': arabic_chars / total if total > 0 else 0},
                {'lang': 'fr', 'confidence': french_matches / total if total > 0 else 0},
                {'lang': 'en', 'confidence': english_matches / total if total > 0 else 0}
            ],
            'is_mixed': is_mixed,
            'arabic_chars': arabic_chars,
            'french_matches': french_matches,
            'english_matches': english_matches
        }


# Example usage
if __name__ == "__main__":
    # Test the normalizer
    normalizer = ArabicTextNormalizer(normalize_taa_marbouta=True)
    
    test_texts = [
        "الْأَحْدَاثُ الْجِلْسِيَّةُ",  # With tashkeel
        "إِسْتِثْمَارٌ فِي الْأَمْرِيكَةِ",  # Alef variants
        "مُسْتَثْمَرَةٌ",  # Taa marbouta
        "رِجَالٌ",  # Yaa/alef maqsoura
        "نَصّ‎‎‎‎‎‎مُتَّصِل",  # Tatweel
        "الرقم٠١٢٣",  # Arabic numerals
        "مرحبا!! كيف حالك???",  # Punctuation
        "هذا   نص   يحتوي   مسافات   متعددة",  # Whitespace
    ]
    
    print("=== Arabic Text Normalization Tests ===")
    for text in test_texts:
        normalized = normalizer.normalize(text)
        spam_score = normalizer.detect_spam_clickbait(text)
        # Safely print Unicode text
        try:
            print(f"Original: {text}")
            print(f"Normalized: {normalized}")
            print(f"Spam Score: {spam_score:.2f}")
        except UnicodeEncodeError:
            print(f"Original: {text.encode('utf-8', errors='replace').decode('utf-8')}")
            print(f"Normalized: {normalized.encode('utf-8', errors='replace').decode('utf-8')}")
            print(f"Spam Score: {spam_score:.2f}")
        print()
    
    # Test language detector
    detector = LanguageDetector()
    
    lang_test_texts = [
        "مرحبا بالعالم",  # Pure Arabic
        "Hello world",  # Pure English
        "Bonjour le monde",  # Pure French
        "مرحبا Hello bonjour",  # Mixed
        "الحدث مهم اليوم في السوق",  # Arabic with some English-like words
        "Les prix du pétrole augmentent aujourd'hui",  # French with Arabic numbers?
    ]
    
    print("=== Language Detection Tests ===")
    for text in lang_test_texts:
        result = detector.detect_language(text)
        # Safely print Unicode text
        try:
            print(f"Text: {text}")
            print(f"Primary: {result['primary']} (confidence: {result['confidence']:.2f})")
            print(f"Mixed: {result['is_mixed']}")
            print(f"Details: {result['languages']}")
        except UnicodeEncodeError:
            print(f"Text: {text.encode('utf-8', errors='replace').decode('utf-8')}")
            print(f"Primary: {result['primary']} (confidence: {result['confidence']:.2f})")
            print(f"Mixed: {result['is_mixed']}")
            print(f"Details: {result['languages']}")
        print()
"""Local ONNX CAPTCHA solver service for Simkuliah logins.

Consumes raw image bytes (PNG/JPEG) from Simkuliah
``/index.php/login/captcha_image`` and produces a cleaned 5-digit string.
"""

from __future__ import annotations

import ddddocr

# Common OCR confusable normalizations for digit-only CAPTCHAs.
_CONFUSABLE_MAP = {
    "O": "0",
    "o": "0",
    "B": "8",
    "I": "1",
    "l": "1",
    "S": "5",
    "Z": "2",
    "G": "6",
}

_CAPTCHA_LENGTH = 5

_ocr_engine: ddddocr.DdddOcr | None = None


def clean_captcha_digits(text: str) -> str:
    """Normalize OCR output to a digit-only string.

    Confusable characters (``O``/``o`` -> ``0``, ``B`` -> ``8``, ``I``/``l`` ->
    ``1``, ``S`` -> ``5``, ``Z`` -> ``2``, ``G`` -> ``6``) are mapped to their
    digit equivalents; everything else that is not a digit is dropped.
    """
    digits: list[str] = []
    for ch in text:
        if ch.isdigit():
            digits.append(ch)
        elif ch in _CONFUSABLE_MAP:
            digits.append(_CONFUSABLE_MAP[ch])
    return "".join(digits)


def get_ocr_engine() -> ddddocr.DdddOcr:
    """Return a lazy singleton :class:`ddddocr.DdddOcr` engine.

    The ONNX model is loaded once and reused to avoid the multi-instance
    overhead of creating a new engine per request.
    """
    global _ocr_engine
    if _ocr_engine is None:
        _ocr_engine = ddddocr.DdddOcr(show_ad=False)
    return _ocr_engine


def solve_captcha(image_bytes: bytes) -> str:
    """Solve a CAPTCHA from raw image bytes.

    Returns a guaranteed 5-character digit string: the OCR result is cleaned
    with :func:`clean_captcha_digits`, padded with ``0`` on the right when
    shorter than 5 characters, and truncated to the first 5 characters when
    longer.
    """
    engine = get_ocr_engine()
    raw = engine.classification(image_bytes)
    digits = clean_captcha_digits(raw)
    if len(digits) < _CAPTCHA_LENGTH:
        digits = digits.ljust(_CAPTCHA_LENGTH, "0")
    return digits[:_CAPTCHA_LENGTH]

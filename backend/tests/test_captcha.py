from unittest.mock import MagicMock, patch

from app.services.captcha import clean_captcha_digits, solve_captcha


def test_clean_captcha_digits_strips_spaces_and_keeps_digits():
    assert clean_captcha_digits(" 4 6 2 7 2 ") == "46272"


def test_clean_captcha_digits_normalizes_confusables():
    assert clean_captcha_digits("O123B") == "01238"


def test_clean_captcha_digits_ignores_non_digits():
    assert clean_captcha_digits("a4b6c2d7e2!") == "46272"


def test_clean_captcha_digits_empty_input():
    assert clean_captcha_digits("") == ""
    assert clean_captcha_digits("abc") == ""


def test_solve_captcha_delegation():
    with patch("app.services.captcha.get_ocr_engine") as mock_engine:
        instance = MagicMock()
        instance.classification.return_value = "46272"
        mock_engine.return_value = instance

        result = solve_captcha(b"fake_image_bytes")

        assert result == "46272"
        assert len(result) == 5
        instance.classification.assert_called_once_with(b"fake_image_bytes")


def test_solve_captcha_pads_short_result_to_five():
    with patch("app.services.captcha.get_ocr_engine") as mock_engine:
        instance = MagicMock()
        instance.classification.return_value = "462"
        mock_engine.return_value = instance

        result = solve_captcha(b"fake_image_bytes")

        assert len(result) == 5
        assert result.startswith("462")


def test_solve_captcha_truncates_long_result_to_five():
    with patch("app.services.captcha.get_ocr_engine") as mock_engine:
        instance = MagicMock()
        instance.classification.return_value = "462728901"
        mock_engine.return_value = instance

        result = solve_captcha(b"fake_image_bytes")

        assert result == "46272"
        assert len(result) == 5

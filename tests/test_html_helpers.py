"""Unit tests for module-level helper functions in excel_to_html_report.py."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from excel_to_html_report import clnrevstat_to_stars, _clinvar_sig_badge, _intervar_badge


class TestClnrevstatToStars:
    def test_practice_guideline(self):
        result = clnrevstat_to_stars("practice_guideline")
        assert "★★★★" in result
        assert "practice_guideline" in result

    def test_expert_panel(self):
        result = clnrevstat_to_stars("reviewed_by_expert_panel")
        assert "★★★" in result

    def test_multiple_submitters(self):
        result = clnrevstat_to_stars("criteria_provided,_multiple_submitters,_no_conflicts")
        assert "★★" in result

    def test_single_submitter(self):
        result = clnrevstat_to_stars("criteria_provided,_single_submitter")
        assert "★" in result
        assert "★★" not in result

    def test_no_assertion_criteria(self):
        result = clnrevstat_to_stars("no_assertion_criteria_provided")
        assert "☆" in result

    def test_no_assertion_provided(self):
        result = clnrevstat_to_stars("no_assertion_provided")
        assert "☆" in result

    def test_conflicting(self):
        result = clnrevstat_to_stars("conflicting_interpretations_of_pathogenicity")
        assert "⚠" in result
        assert "conflict" in result

    def test_unknown_value_returns_empty(self):
        assert clnrevstat_to_stars("some_unknown_value") == ""

    def test_empty_string_returns_empty(self):
        assert clnrevstat_to_stars("") == ""

    def test_none_returns_empty(self):
        assert clnrevstat_to_stars(None) == ""

    def test_returns_span_element(self):
        result = clnrevstat_to_stars("practice_guideline")
        assert result.startswith("<span")
        assert result.endswith("</span>")


class TestClinvarSigBadge:
    def test_pathogenic(self):
        result = _clinvar_sig_badge("Pathogenic")
        assert "badge-pathogenic" in result
        assert "Pathogenic" in result

    def test_likely_pathogenic(self):
        result = _clinvar_sig_badge("Likely pathogenic")
        assert "badge-likely-pathogenic" in result

    def test_benign(self):
        result = _clinvar_sig_badge("Benign")
        assert "badge-benign" in result

    def test_likely_benign(self):
        result = _clinvar_sig_badge("Likely benign")
        assert "badge-likely-benign" in result

    def test_vus(self):
        result = _clinvar_sig_badge("Uncertain significance")
        assert "badge-vus" in result

    def test_empty_returns_empty(self):
        assert _clinvar_sig_badge("") == ""

    def test_dot_returns_empty(self):
        assert _clinvar_sig_badge(".") == ""

    def test_not_provided_returns_empty(self):
        assert _clinvar_sig_badge("not_provided") == ""

    def test_none_returns_empty(self):
        assert _clinvar_sig_badge(None) == ""


class TestIntervarBadge:
    def test_pathogenic(self):
        result = _intervar_badge("Pathogenic")
        assert "badge-pathogenic" in result

    def test_likely_pathogenic(self):
        result = _intervar_badge("Likely pathogenic")
        assert "badge-likely-pathogenic" in result

    def test_uncertain(self):
        result = _intervar_badge("Uncertain significance")
        assert "badge-vus" in result

    def test_empty_returns_empty(self):
        assert _intervar_badge("") == ""

    def test_dot_returns_empty(self):
        assert _intervar_badge(".") == ""

    def test_none_returns_empty(self):
        assert _intervar_badge(None) == ""

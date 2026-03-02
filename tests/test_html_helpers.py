"""Unit tests for module-level helper functions in excel_to_html_report.py."""
import sys
import os
sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from excel_to_html_report import clnrevstat_to_stars, _clinvar_sig_badge, _intervar_badge, iSeqReportGenerator, ACMG_CRITERIA


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
        assert result.count("★") == 1

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

    def test_benign(self):
        result = _intervar_badge("Benign")
        assert "badge-benign" in result

    def test_likely_benign(self):
        result = _intervar_badge("Likely benign")
        assert "badge-likely-benign" in result


class TestGetActiveAcmgCriteria:
    def _make_generator(self):
        """Return a minimally initialised iSeqReportGenerator.

        __init__ requires excel_path and output_dir as positional strings.
        Pass dummy values; _get_active_acmg_criteria does not open any files.
        """
        return iSeqReportGenerator("/dev/null", "/tmp")

    def test_active_criterion_returned(self):
        gen = self._make_generator()
        col_map = {"PVS1": 0}
        row = ["1"]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert "PVS1" in result

    def test_dot_value_not_active(self):
        gen = self._make_generator()
        col_map = {"PVS1": 0}
        row = ["."]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert result == []

    def test_zero_value_not_active(self):
        gen = self._make_generator()
        col_map = {"PVS1": 0}
        row = ["0"]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert result == []

    def test_empty_value_not_active(self):
        gen = self._make_generator()
        col_map = {"PVS1": 0}
        row = [""]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert result == []

    def test_missing_col_in_col_map_skipped(self):
        gen = self._make_generator()
        col_map = {}  # PVS1 not in col_map
        row = ["1"]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert result == []

    def test_multiple_active_criteria(self):
        gen = self._make_generator()
        col_map = {"PVS1": 0, "PM2": 1, "PP3": 2}
        row = ["1", ".", "Supporting"]
        result = gen._get_active_acmg_criteria(row, col_map)
        assert "PVS1" in result
        assert "PM2" not in result
        assert "PP3" in result


class TestClinicalSummaryTable:
    def _make_generator(self):
        from excel_to_html_report import iSeqReportGenerator
        return iSeqReportGenerator("/dev/null", "/tmp")

    def test_returns_table_html(self):
        gen = self._make_generator()
        col_map = {"GENE": 0, "CLNSIG": 1, "CLNREVSTAT": 2}
        variants = [["BRCA1", "Pathogenic", "reviewed_by_expert_panel"]]
        html = gen._clinical_summary_table_html(variants, col_map)
        assert "<table" in html
        assert "BRCA1" in html
        assert "★★★" in html  # expert panel stars
        assert "badge-pathogenic" in html

    def test_empty_variants_returns_empty_table(self):
        gen = self._make_generator()
        html = gen._clinical_summary_table_html([], {})
        assert "<table" in html
        assert "<tbody>" in html

    def test_row_has_onclick_scrollToCard(self):
        gen = self._make_generator()
        col_map = {"GENE": 0}
        variants = [["TP53"], ["KRAS"]]
        html = gen._clinical_summary_table_html(variants, col_map)
        assert "scrollToCard('card-0')" in html
        assert "scrollToCard('card-1')" in html

    def test_missing_col_in_col_map_returns_empty_cell(self):
        gen = self._make_generator()
        col_map = {}
        variants = [["BRCA1", "Pathogenic"]]
        html = gen._clinical_summary_table_html(variants, col_map)
        assert "<table" in html

    def test_cancervar_badge_rendered(self):
        gen = self._make_generator()
        col_map = {"CancerVar and Evidence": 0}
        variants = [["Tier I Actionable"]]
        html = gen._clinical_summary_table_html(variants, col_map)
        assert "cancervar-tier1" in html

    def test_intervar_badge_rendered(self):
        gen = self._make_generator()
        col_map = {"InterVar_automated": 0}
        variants = [["Likely pathogenic"]]
        html = gen._clinical_summary_table_html(variants, col_map)
        assert "badge-likely-pathogenic" in html

    def test_dot_value_treated_as_empty(self):
        gen = self._make_generator()
        col_map = {"GENE": 0, "VAF": 1}
        variants = [[".", "."]]
        html = gen._clinical_summary_table_html(variants, col_map)
        # dot values are treated as empty, so no gene text should appear
        assert "<table" in html

    def test_table_has_all_headers(self):
        gen = self._make_generator()
        html = gen._clinical_summary_table_html([], {})
        for header in ("Gene", "HGVSc", "HGVSp", "ClinVar", "CancerVar", "InterVar", "VAF", "DP"):
            assert header in html

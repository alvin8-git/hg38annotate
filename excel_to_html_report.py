#!/usr/bin/env python3
"""
iSeq Excel to HTML Variant Report Converter

Converts Combine.xlsx from iSeq pipeline to interactive HTML reports.
Matches the processVCF.sh HTML report style with colored panels, ACMG chips,
and gene hero sections.

Column Structure (based on iSeq Combine.xlsx):
- Col 1: SAMPLE
- Col 2-19: Basic variant information
- Col 20-21: Sample Comparison Data
- Col 22-30: Additional Variant Information
- Col 31-88: Population Frequency Database
- Col 89-122: ACMG Criteria & ClinVar
- Col 123-152: Computational Predictions

Usage:
    python3 excel_to_html_report.py <input_excel_file> [output_directory] [snapshots_directory]
"""

import os
import sys
import re
from pathlib import Path
from typing import Dict, List, Any, Optional
from html import escape
from collections import defaultdict

try:
    import openpyxl
except ImportError:
    print("Error: openpyxl is required. Install with: pip install openpyxl")
    sys.exit(1)


# Column group definitions (1-indexed)
COLUMN_GROUPS = {
    "basic_info": list(range(2, 20)),
    "sample_comparison": list(range(20, 22)),
    "additional_info": list(range(22, 31)),
    "population_freq": list(range(31, 89)),
    "acmg_criteria": list(range(89, 123)),
    "computational": list(range(123, 153)),
}

# Key column indices (1-indexed)
KEY_COLS = {
    "sample": 1, "chr": 2, "pos": 3, "ref": 4, "alt": 5, "gt": 6,
    "gene": 7, "transcript": 8, "hgvsg": 9, "hgvsc": 10, "hgvsp": 11,
    "ad": 12, "dp": 13, "qual": 14, "vaf": 15,
}

# ACMG criteria chip definitions: (col_index, label, css_class)
ACMG_GROUPS = {
    "Very Strong Pathogenic": [(90, "PVS1", "pvs")],
    "Strong Pathogenic": [(91, "PS1", "ps"), (92, "PS2", "ps"), (93, "PS3", "ps"), (94, "PS4", "ps")],
    "Moderate Pathogenic": [(95, "PM1", "pm"), (96, "PM2", "pm"), (97, "PM3", "pm"), (98, "PM4", "pm"), (99, "PM5", "pm"), (100, "PM6", "pm")],
    "Supporting Pathogenic": [(101, "PP1", "pp"), (102, "PP2", "pp"), (103, "PP3", "pp"), (104, "PP4", "pp"), (105, "PP5", "pp")],
    "Stand-Alone Benign": [(106, "BA1", "ba")],
    "Strong Benign": [(107, "BS1", "bs"), (108, "BS2", "bs"), (109, "BS3", "bs"), (110, "BS4", "bs")],
    "Supporting Benign": [(111, "BP1", "bp"), (112, "BP2", "bp"), (113, "BP3", "bp"), (114, "BP4", "bp"), (115, "BP5", "bp"), (116, "BP6", "bp"), (117, "BP7", "bp")],
}

# ClinVar columns
CLINVAR_COLS = [118, 119, 120, 121, 122]

# Prediction score columns: (score_col, pred_col or None, label)
PREDICTION_SCORES = [
    (123, None, "M-CAP"),
    (124, None, "REVEL"),
    (125, 126, "SIFT"),
    (127, 128, "PolyPhen2 HDIV"),
    (129, 130, "PolyPhen2 HVAR"),
    (131, 132, "LRT"),
    (133, 134, "MutationTaster"),
    (135, 136, "MutationAssessor"),
    (137, 138, "FATHMM"),
    (139, 140, "RadialSVM"),
    (141, 142, "LR"),
    (143, None, "VEST3"),
    (144, 145, "CADD"),
    (146, None, "GERP++"),
    (147, None, "phyloP46way"),
    (148, None, "phyloP100way"),
    (149, None, "SiPhy"),
    (150, None, "phastCons30way"),
    (151, None, "phastCons100way"),
    (152, None, "targetScanS"),
]


def get_css_styles() -> str:
    return """
:root {
    --primary-color: #2c3e50;
    --secondary-color: #3498db;
    --accent-color: #e74c3c;
    --success-color: #27ae60;
    --warning-color: #f39c12;
    --light-bg: #f8f9fa;
    --border-color: #dee2e6;
    --text-muted: #6c757d;
    --tier1-color: #dc3545;
    --tier2-color: #fd7e14;
    --tier3-color: #ffc107;
    --tier4-color: #28a745;
    --pathogenic-color: #dc3545;
    --likely-pathogenic-color: #fd7e14;
    --vus-color: #6c757d;
    --likely-benign-color: #17a2b8;
    --benign-color: #28a745;
}

* { box-sizing: border-box; }

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, 'Helvetica Neue', Arial, sans-serif;
    line-height: 1.5;
    color: #212529;
    background-color: #f5f6fa;
    margin: 0;
    padding: 0;
}

.container {
    max-width: 1600px;
    margin: 0 auto;
    padding: 20px;
}

/* Header */
.header {
    background: linear-gradient(135deg, var(--primary-color) 0%, #34495e 100%);
    color: white;
    padding: 20px 30px;
    margin-bottom: 20px;
    border-radius: 8px;
    box-shadow: 0 4px 6px rgba(0,0,0,0.1);
}
.header h1 { margin: 0 0 10px 0; font-size: 1.8rem; font-weight: 600; }
.header .subtitle { opacity: 0.9; font-size: 0.95rem; }

/* Breadcrumb */
.breadcrumb {
    background: white;
    padding: 12px 20px;
    border-radius: 6px;
    margin-bottom: 20px;
    box-shadow: 0 1px 3px rgba(0,0,0,0.08);
}
.breadcrumb a { color: var(--secondary-color); text-decoration: none; }
.breadcrumb a:hover { text-decoration: underline; }

/* Gene Hero */
.gene-hero {
    background: white;
    border-radius: 10px;
    padding: 25px 30px;
    margin-bottom: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    display: flex;
    flex-wrap: wrap;
    align-items: center;
    gap: 20px;
}
.gene-name { font-size: 2.8rem; font-weight: 700; color: var(--primary-color); margin: 0; }
.variant-notation { font-size: 1.4rem; color: var(--text-muted); font-family: 'Monaco','Menlo',monospace; }

/* Panel Styles */
.panel {
    background: white;
    border-radius: 10px;
    margin-bottom: 20px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    overflow: hidden;
}
.panel-header {
    background: var(--light-bg);
    padding: 15px 20px;
    border-bottom: 1px solid var(--border-color);
    cursor: pointer;
    display: flex;
    justify-content: space-between;
    align-items: center;
    transition: background-color 0.2s;
}
.panel-header:hover { background: #e9ecef; }
.panel-title { font-size: 1.1rem; font-weight: 600; color: var(--primary-color); margin: 0; }
.panel-toggle { font-size: 1.2rem; color: var(--text-muted); transition: transform 0.3s; }
.panel.collapsed .panel-toggle { transform: rotate(-90deg); }
.panel.collapsed .panel-content { display: none; }
.panel-content { padding: 20px; }

/* Data Grid */
.data-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(280px, 1fr));
    gap: 15px;
}
.data-item {
    padding: 10px 15px;
    background: var(--light-bg);
    border-radius: 6px;
    border-left: 3px solid var(--secondary-color);
}
.data-label {
    font-size: 0.75rem;
    color: var(--text-muted);
    text-transform: uppercase;
    letter-spacing: 0.5px;
    margin-bottom: 4px;
}
.data-value { font-size: 0.95rem; color: #212529; word-break: break-word; }
.data-value.large { font-size: 1.2rem; font-weight: 600; }
.data-value.monospace { font-family: 'Monaco','Menlo',monospace; font-size: 0.9rem; }

/* Population Frequency Bars */
.freq-bar-container {
    width: 100%; height: 6px; background: #e9ecef;
    border-radius: 3px; margin-top: 5px; overflow: hidden;
}
.freq-bar { height: 100%; border-radius: 3px; transition: width 0.3s; }
.freq-bar.rare { background: var(--success-color); }
.freq-bar.low { background: var(--warning-color); }
.freq-bar.common { background: var(--accent-color); }

/* ACMG Criteria Chips */
.acmg-grid { display: flex; flex-wrap: wrap; gap: 8px; margin-bottom: 15px; }
.acmg-chip {
    display: inline-flex; align-items: center;
    padding: 6px 12px; border-radius: 20px;
    font-size: 0.8rem; font-weight: 600;
}
.acmg-chip.inactive { background: #e9ecef; color: #adb5bd; }
.acmg-chip.pvs { background: #721c24; color: white; }
.acmg-chip.ps { background: var(--pathogenic-color); color: white; }
.acmg-chip.pm { background: var(--likely-pathogenic-color); color: white; }
.acmg-chip.pp { background: #f8d7da; color: #721c24; }
.acmg-chip.ba { background: #155724; color: white; }
.acmg-chip.bs { background: var(--benign-color); color: white; }
.acmg-chip.bp { background: #d4edda; color: #155724; }

/* Prediction Score Table */
.score-table { width: 100%; border-collapse: collapse; font-size: 0.9rem; }
.score-table th, .score-table td {
    padding: 10px 12px; text-align: left;
    border-bottom: 1px solid var(--border-color);
}
.score-table th { background: var(--light-bg); font-weight: 600; color: var(--primary-color); }
.score-table tr:hover { background: #f8f9fa; }
.pred-badge {
    display: inline-block; padding: 3px 10px; border-radius: 12px;
    font-size: 0.75rem; font-weight: 600; text-transform: uppercase;
}
.pred-d, .pred-deleterious { background: #f8d7da; color: #721c24; }
.pred-t, .pred-tolerated { background: #d4edda; color: #155724; }
.pred-p, .pred-possibly { background: #fff3cd; color: #856404; }
.pred-b, .pred-benign { background: #d4edda; color: #155724; }
.pred-n, .pred-neutral { background: #e9ecef; color: #495057; }

/* Population DB Sub-panels */
.pop-db-section { margin-bottom: 20px; }
.pop-db-title {
    font-size: 0.9rem; font-weight: 600; color: var(--primary-color);
    margin-bottom: 10px; padding-bottom: 5px;
    border-bottom: 1px solid var(--border-color);
}

/* Panel Color Themes */
.panel.panel-basic { border-left: 4px solid #3498db; }
.panel.panel-basic .panel-header { background: linear-gradient(135deg, #3498db 0%, #2980b9 100%); color: white; }
.panel.panel-basic .panel-header:hover { background: linear-gradient(135deg, #2980b9 0%, #1f6dad 100%); }
.panel.panel-basic .panel-title { color: white; font-weight: 700; }
.panel.panel-basic .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-basic .panel-content { background: linear-gradient(180deg, #ebf5fb 0%, #d6eaf8 100%); }

.panel.panel-comparison { border-left: 4px solid #27ae60; }
.panel.panel-comparison .panel-header { background: linear-gradient(135deg, #27ae60 0%, #1e8449 100%); color: white; }
.panel.panel-comparison .panel-header:hover { background: linear-gradient(135deg, #1e8449 0%, #196f3d 100%); }
.panel.panel-comparison .panel-title { color: white; font-weight: 700; }
.panel.panel-comparison .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-comparison .panel-content { background: linear-gradient(180deg, #e9f7ef 0%, #d4efdf 100%); }

.panel.panel-additional { border-left: 4px solid #546e7a; }
.panel.panel-additional .panel-header { background: linear-gradient(135deg, #607d8b 0%, #546e7a 100%); color: white; }
.panel.panel-additional .panel-header:hover { background: linear-gradient(135deg, #546e7a 0%, #455a64 100%); }
.panel.panel-additional .panel-title { color: white; font-weight: 700; }
.panel.panel-additional .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-additional .panel-content { background: linear-gradient(180deg, #eceff1 0%, #cfd8dc 100%); }

.panel.panel-population { border-left: 4px solid #5c6bc0; }
.panel.panel-population .panel-header { background: linear-gradient(135deg, #5c6bc0 0%, #3f51b5 100%); color: white; }
.panel.panel-population .panel-header:hover { background: linear-gradient(135deg, #3f51b5 0%, #303f9f 100%); }
.panel.panel-population .panel-title { color: white; font-weight: 700; }
.panel.panel-population .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-population .panel-content { background: linear-gradient(180deg, #e8eaf6 0%, #c5cae9 100%); }

.panel.panel-acmg { border-left: 4px solid #8e24aa; }
.panel.panel-acmg .panel-header { background: linear-gradient(135deg, #ab47bc 0%, #8e24aa 100%); color: white; }
.panel.panel-acmg .panel-header:hover { background: linear-gradient(135deg, #8e24aa 0%, #7b1fa2 100%); }
.panel.panel-acmg .panel-title { color: white; font-weight: 700; }
.panel.panel-acmg .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-acmg .panel-content { background: linear-gradient(180deg, #f3e5f5 0%, #e1bee7 100%); }

.panel.panel-computational { border-left: 4px solid #e67e22; }
.panel.panel-computational .panel-header { background: linear-gradient(135deg, #e67e22 0%, #ca6f1e 100%); color: white; }
.panel.panel-computational .panel-header:hover { background: linear-gradient(135deg, #ca6f1e 0%, #b9770e 100%); }
.panel.panel-computational .panel-title { color: white; font-weight: 700; }
.panel.panel-computational .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-computational .panel-content { background: linear-gradient(180deg, #fef5e7 0%, #fdebd0 100%); }

.panel.panel-igv { border-left: 4px solid #8e44ad; }
.panel.panel-igv .panel-header { background: linear-gradient(135deg, #9b59b6 0%, #8e44ad 100%); color: white; }
.panel.panel-igv .panel-header:hover { background: linear-gradient(135deg, #8e44ad 0%, #7d3c98 100%); }
.panel.panel-igv .panel-title { color: white; font-weight: 700; }
.panel.panel-igv .panel-toggle { color: rgba(255,255,255,0.8); }
.panel.panel-igv .panel-content { background: linear-gradient(180deg, #f5eef8 0%, #e8daef 100%); text-align: center; }
.panel.panel-igv .igv-image {
    max-width: 100%; height: auto; border-radius: 8px;
    box-shadow: 0 4px 12px rgba(0,0,0,0.15); margin: 10px 0;
}
.panel.panel-igv .igv-no-image {
    color: var(--text-muted); font-style: italic; padding: 40px 20px;
}

/* Dashboard Stats */
.dashboard-stats {
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
    gap: 15px;
    margin-bottom: 25px;
}
.stat-card {
    background: white; border-radius: 10px; padding: 20px;
    text-align: center; box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    transition: transform 0.2s, box-shadow 0.2s;
}
.stat-card.clickable { cursor: pointer; }
.stat-card.clickable:hover { transform: translateY(-3px); box-shadow: 0 6px 20px rgba(0,0,0,0.15); }
.stat-value { font-size: 2.5rem; font-weight: 700; color: var(--primary-color); }
.stat-label { font-size: 0.85rem; color: var(--text-muted); text-transform: uppercase; letter-spacing: 0.5px; }

/* Sample Cards */
.sample-grid {
    display: grid;
    grid-template-columns: repeat(auto-fill, minmax(300px, 1fr));
    gap: 20px;
    margin-bottom: 30px;
}
.sample-card {
    background: white; border-radius: 10px;
    box-shadow: 0 2px 8px rgba(0,0,0,0.08);
    overflow: hidden; transition: transform 0.2s, box-shadow 0.2s;
    cursor: pointer; text-decoration: none; color: inherit; display: block;
}
.sample-card:hover { transform: translateY(-3px); box-shadow: 0 6px 20px rgba(0,0,0,0.15); }
.sample-card-header {
    background: linear-gradient(135deg, var(--primary-color) 0%, #34495e 100%);
    color: white; padding: 20px;
}
.sample-card-header h3 { margin: 0; font-size: 1.2em; }
.sample-card-body { padding: 15px 20px; }
.sample-stat {
    display: flex; justify-content: space-between;
    padding: 8px 0; border-bottom: 1px solid var(--border-color);
}
.sample-stat:last-child { border-bottom: none; }
.sample-stat-label { color: var(--text-muted); font-size: 0.85rem; }
.sample-stat-value { font-weight: 600; }

/* Variant Table */
.variant-table {
    width: 100%; border-collapse: collapse; background: white;
    border-radius: 10px; overflow: hidden; box-shadow: 0 2px 8px rgba(0,0,0,0.08);
}
.variant-table th, .variant-table td {
    padding: 14px 16px; text-align: left;
    border-bottom: 1px solid var(--border-color);
}
.variant-table th {
    background: var(--primary-color); color: white; font-weight: 600;
    font-size: 0.85rem; text-transform: uppercase; letter-spacing: 0.5px;
}
.variant-table tr:hover { background: #f8f9fa; }
.variant-table td.gene { font-weight: 600; color: var(--primary-color); }
.variant-table a { color: var(--secondary-color); text-decoration: none; }
.variant-table a:hover { text-decoration: underline; }

/* Back button */
.back-btn {
    display: inline-flex; align-items: center; gap: 8px;
    padding: 10px 18px; background: white;
    border: 1px solid var(--border-color); border-radius: 6px;
    color: var(--primary-color); text-decoration: none;
    font-size: 0.9rem; font-weight: 500; cursor: pointer; transition: all 0.2s;
}
.back-btn:hover { background: var(--secondary-color); color: white; border-color: var(--secondary-color); }

/* Responsive */
@media (max-width: 768px) {
    .container { padding: 10px; }
    .gene-hero { flex-direction: column; align-items: flex-start; }
    .gene-name { font-size: 2rem; }
    .data-grid { grid-template-columns: 1fr; }
    .sample-grid { grid-template-columns: 1fr; }
}

@media print {
    .panel.collapsed .panel-content { display: block !important; }
    .breadcrumb { display: none; }
    .panel { break-inside: avoid; }
}
"""


def get_javascript() -> str:
    return """
function togglePanel(header) {
    header.parentElement.classList.toggle('collapsed');
}
"""


def _is_empty(val):
    """Check if value is empty/missing"""
    if val is None:
        return True
    s = str(val).strip()
    return s in ("", ".", "-", "NA", "N/A", "None")


def _pred_badge_class(pred_str):
    """Get CSS class for prediction badge"""
    if not pred_str:
        return ""
    p = pred_str.strip().upper()[0] if pred_str.strip() else ""
    mapping = {"D": "pred-d", "T": "pred-t", "P": "pred-p", "B": "pred-b", "N": "pred-n"}
    return mapping.get(p, "")


class iSeqReportGenerator:
    def __init__(self, excel_path: str, output_dir: str, snapshots_dir: Optional[str] = None):
        self.excel_path = Path(excel_path)
        self.output_dir = Path(output_dir)
        self.snapshots_dir = Path(snapshots_dir) if snapshots_dir else None
        self.headers: List[str] = []
        self.rows: List[List[Any]] = []
        self.samples: Dict[str, List[int]] = defaultdict(list)

    def load_excel(self):
        print(f"Loading Excel file: {self.excel_path}")
        wb = openpyxl.load_workbook(self.excel_path, read_only=True, data_only=True)
        ws = wb.active
        header_row = next(ws.iter_rows(min_row=1, max_row=1, values_only=True))
        self.headers = [str(h) if h else f"Column_{i+1}" for i, h in enumerate(header_row)]
        print(f"Found {len(self.headers)} columns")

        for row_idx, row in enumerate(ws.iter_rows(min_row=2, values_only=True)):
            row_data = list(row)
            while len(row_data) < len(self.headers):
                row_data.append(None)
            self.rows.append(row_data)
            sample_name = str(row_data[0]).strip() if row_data[0] else "Unknown"
            self.samples[sample_name].append(row_idx)

        wb.close()
        print(f"Loaded {len(self.rows)} variants from {len(self.samples)} samples")

    def _val(self, row_idx: int, col_idx: int) -> str:
        """Get cell value (1-indexed col), returns '' if empty"""
        if col_idx < 1 or col_idx > len(self.headers) or row_idx < 0 or row_idx >= len(self.rows):
            return ""
        val = self.rows[row_idx][col_idx - 1]
        if _is_empty(val):
            return ""
        return str(val).strip()

    def _header(self, col_idx: int) -> str:
        if col_idx < 1 or col_idx > len(self.headers):
            return f"Column_{col_idx}"
        return self.headers[col_idx - 1]

    def find_igv_screenshot(self, sample: str, chrom: str, pos: str) -> Optional[str]:
        if not self.snapshots_dir or not self.snapshots_dir.exists():
            return None
        sample = sample.strip()
        chrom = chrom.strip()
        pos = pos.strip()
        chr_num = chrom.replace("chr", "")

        for filename in [f"{sample}-{chr_num}-{pos}.png", f"{sample}-chr{chr_num}-{pos}.png",
                         f"{sample}_{chr_num}_{pos}.png", f"{sample}_{chrom}_{pos}.png"]:
            filepath = self.snapshots_dir / filename
            if filepath.exists():
                return str(filepath.resolve())
        return None

    def _data_grid_html(self, row_idx: int, col_indices: List[int]) -> str:
        """Generate data grid HTML, skipping empty values"""
        items = []
        for col_idx in col_indices:
            value = self._val(row_idx, col_idx)
            if not value:
                continue
            label = escape(self._header(col_idx))
            items.append(f'''
                    <div class="data-item">
                        <div class="data-label">{label}</div>
                        <div class="data-value monospace">{escape(value)}</div>
                    </div>''')
        if not items:
            return '<div style="padding:10px;color:var(--text-muted);font-style:italic;">No data available</div>'
        return '<div class="data-grid">' + ''.join(items) + '\n</div>'

    def _panel_html(self, title: str, panel_class: str, content: str, collapsed: bool = False) -> str:
        cls = f"panel {panel_class}" + (" collapsed" if collapsed else "")
        return f'''
        <div class="{cls}">
            <div class="panel-header" onclick="togglePanel(this)">
                <h3 class="panel-title">{escape(title)}</h3>
                <span class="panel-toggle">&#9662;</span>
            </div>
            <div class="panel-content">
                {content}
            </div>
        </div>'''

    def _acmg_section_html(self, row_idx: int) -> str:
        """Generate ACMG section with chip buttons"""
        html = ''

        # InterVar classification
        intervar = self._val(row_idx, 89)
        if intervar:
            html += f'''
                <div style="margin-bottom: 20px;">
                    <div class="data-label">InterVar Classification</div>
                    <div class="data-value large">{escape(intervar)}</div>
                </div>'''

        # ACMG Criteria chips
        html += '<div style="margin-bottom: 25px;">\n'
        html += '    <div class="data-label" style="margin-bottom: 10px;">ACMG Criteria</div>\n'

        for group_name, criteria in ACMG_GROUPS.items():
            html += f'    <div style="margin-bottom: 8px;">\n'
            html += f'        <small style="color: var(--text-muted);">{escape(group_name)}</small>\n'
            html += '        <div class="acmg-grid">\n'

            for col_idx, label, css_class in criteria:
                value = self._val(row_idx, col_idx)
                # Active if value is truthy and not "0"
                is_active = bool(value) and value != "0"
                chip_class = css_class if is_active else "inactive"
                html += f'            <span class="acmg-chip {chip_class}">{label}</span>\n'

            html += '        </div>\n'
            html += '    </div>\n'

        html += '</div>\n'

        # ClinVar data
        clinvar_items = []
        for col_idx in CLINVAR_COLS:
            value = self._val(row_idx, col_idx)
            if value:
                label = escape(self._header(col_idx))
                clinvar_items.append(f'''
                    <div class="data-item">
                        <div class="data-label">{label}</div>
                        <div class="data-value monospace">{escape(value)}</div>
                    </div>''')

        if clinvar_items:
            html += '<div class="data-label" style="margin-bottom: 10px;">ClinVar</div>\n'
            html += '<div class="data-grid">' + ''.join(clinvar_items) + '</div>\n'

        return html

    def _computational_section_html(self, row_idx: int) -> str:
        """Generate computational predictions as a score table"""
        rows_html = ''
        has_data = False

        for score_col, pred_col, label in PREDICTION_SCORES:
            score = self._val(row_idx, score_col)
            pred = self._val(row_idx, pred_col) if pred_col else ""

            if not score and not pred:
                continue

            has_data = True
            score_display = escape(score) if score else "-"

            if pred:
                badge_cls = _pred_badge_class(pred)
                pred_display = f'<span class="pred-badge {badge_cls}">{escape(pred)}</span>'
            else:
                pred_display = "-"

            rows_html += f'''
                <tr>
                    <td style="font-weight:600;">{escape(label)}</td>
                    <td style="font-family:monospace;">{score_display}</td>
                    <td>{pred_display}</td>
                </tr>'''

        if not has_data:
            return '<div style="padding:10px;color:var(--text-muted);font-style:italic;">No prediction data available</div>'

        return f'''
            <table class="score-table">
                <thead>
                    <tr><th>Tool</th><th>Score</th><th>Prediction</th></tr>
                </thead>
                <tbody>{rows_html}
                </tbody>
            </table>'''

    def _pop_freq_html(self, row_idx: int) -> str:
        """Generate population frequency section, skipping empty values"""
        items = []
        for col_idx in COLUMN_GROUPS["population_freq"]:
            value = self._val(row_idx, col_idx)
            if not value:
                continue
            label = escape(self._header(col_idx))

            # Try to add frequency bar
            bar_html = ""
            try:
                freq = float(value)
                pct = min(freq * 100, 100)
                bar_class = "rare" if freq < 0.01 else ("low" if freq < 0.05 else "common")
                bar_html = f'''
                            <div class="freq-bar-container">
                                <div class="freq-bar {bar_class}" style="width: {pct}%"></div>
                            </div>'''
            except (ValueError, TypeError):
                pass

            items.append(f'''
                    <div class="data-item">
                        <div class="data-label">{label}</div>
                        <div class="data-value monospace">{escape(value)}</div>{bar_html}
                    </div>''')

        if not items:
            return '<div style="padding:10px;color:var(--text-muted);font-style:italic;">No population frequency data available</div>'
        return '<div class="data-grid">' + ''.join(items) + '\n</div>'

    # ---- Page generators ----

    def generate_landing_page(self) -> str:
        html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>iSeq Variant Report</title>
    <style>{get_css_styles()}</style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>iSeq Variant Analysis Report</h1>
            <div class="subtitle">Generated from {escape(self.excel_path.name)}</div>
        </div>

        <div class="dashboard-stats">
            <div class="stat-card">
                <div class="stat-value">{len(self.samples)}</div>
                <div class="stat-label">Total Samples</div>
            </div>
            <div class="stat-card">
                <div class="stat-value">{len(self.rows)}</div>
                <div class="stat-label">Total Variants</div>
            </div>
        </div>

        <div class="sample-grid">'''

        for sample_name in sorted(self.samples.keys()):
            row_indices = self.samples[sample_name]
            genes = set()
            for idx in row_indices:
                g = self._val(idx, KEY_COLS["gene"])
                if g:
                    genes.add(g)

            safe_sample = re.sub(r'[^\w\-_]', '_', sample_name)

            html += f'''
            <a href="samples/{safe_sample}.html" class="sample-card">
                <div class="sample-card-header">
                    <h3>{escape(sample_name)}</h3>
                </div>
                <div class="sample-card-body">
                    <div class="sample-stat">
                        <span class="sample-stat-label">Variants</span>
                        <span class="sample-stat-value">{len(row_indices)}</span>
                    </div>
                    <div class="sample-stat">
                        <span class="sample-stat-label">Genes Affected</span>
                        <span class="sample-stat-value">{len(genes)}</span>
                    </div>
                </div>
            </a>'''

        html += '''
        </div>
    </div>
</body>
</html>'''
        return html

    def generate_sample_page(self, sample_name: str) -> str:
        row_indices = self.samples[sample_name]
        safe_sample = re.sub(r'[^\w\-_]', '_', sample_name)

        html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Variant Report - {escape(sample_name)}</title>
    <style>{get_css_styles()}</style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Variant Analysis Report</h1>
            <div class="subtitle">Sample: {escape(sample_name)}</div>
        </div>

        <div class="breadcrumb">
            <a href="../index.html">&#8592; All Samples</a> &gt; {escape(sample_name)}
        </div>

        <div class="dashboard-stats">
            <div class="stat-card">
                <div class="stat-value">{len(row_indices)}</div>
                <div class="stat-label">Total Variants</div>
            </div>'''

        genes = set()
        for idx in row_indices:
            g = self._val(idx, KEY_COLS["gene"])
            if g:
                genes.add(g)

        html += f'''
            <div class="stat-card">
                <div class="stat-value" style="color: var(--secondary-color);">{len(genes)}</div>
                <div class="stat-label">Genes Affected</div>
            </div>
        </div>

        <table class="variant-table">
            <thead>
                <tr>
                    <th>#</th>
                    <th>Gene</th>
                    <th>Variant</th>
                    <th>HGVSc</th>
                    <th>HGVSp</th>
                    <th>VAF</th>
                    <th>DP</th>
                    <th>Action</th>
                </tr>
            </thead>
            <tbody>'''

        for i, row_idx in enumerate(row_indices):
            gene = self._val(row_idx, KEY_COLS["gene"]) or "-"
            chrom = self._val(row_idx, KEY_COLS["chr"]) or "-"
            pos = self._val(row_idx, KEY_COLS["pos"]) or "-"
            ref = self._val(row_idx, KEY_COLS["ref"]) or "-"
            alt = self._val(row_idx, KEY_COLS["alt"]) or "-"
            hgvsc = self._val(row_idx, KEY_COLS["hgvsc"]) or "-"
            hgvsp = self._val(row_idx, KEY_COLS["hgvsp"]) or "-"
            vaf = self._val(row_idx, KEY_COLS["vaf"]) or "-"
            dp = self._val(row_idx, KEY_COLS["dp"]) or "-"

            try:
                vaf_num = float(vaf)
                vaf = f"{vaf_num*100:.1f}%" if vaf_num <= 1 else vaf
            except (ValueError, TypeError):
                pass

            hgvsc_short = hgvsc[:30] + "..." if len(hgvsc) > 30 else hgvsc
            hgvsp_short = hgvsp[:20] + "..." if len(hgvsp) > 20 else hgvsp

            html += f'''
                <tr>
                    <td>{i+1}</td>
                    <td class="gene">{escape(gene)}</td>
                    <td style="font-family:monospace;">{escape(chrom)}:{escape(pos)} {escape(ref)}&gt;{escape(alt)}</td>
                    <td style="font-family:monospace;" title="{escape(hgvsc)}">{escape(hgvsc_short)}</td>
                    <td style="font-family:monospace;" title="{escape(hgvsp)}">{escape(hgvsp_short)}</td>
                    <td>{escape(vaf)}</td>
                    <td>{escape(dp)}</td>
                    <td><a href="variants/{safe_sample}_var{row_idx}.html">View Details</a></td>
                </tr>'''

        html += '''
            </tbody>
        </table>
    </div>
</body>
</html>'''
        return html

    def generate_variant_page(self, sample_name: str, row_idx: int) -> str:
        safe_sample = re.sub(r'[^\w\-_]', '_', sample_name)

        gene = self._val(row_idx, KEY_COLS["gene"]) or "Unknown"
        chrom = self._val(row_idx, KEY_COLS["chr"]) or "-"
        pos = self._val(row_idx, KEY_COLS["pos"]) or "-"
        ref = self._val(row_idx, KEY_COLS["ref"]) or "-"
        alt = self._val(row_idx, KEY_COLS["alt"]) or "-"
        hgvsc = self._val(row_idx, KEY_COLS["hgvsc"]) or "-"
        hgvsp = self._val(row_idx, KEY_COLS["hgvsp"]) or "-"

        igv_path = self.find_igv_screenshot(sample_name, chrom, pos)
        variant_html_dir = (self.output_dir / "samples" / "variants").resolve()

        html = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>{escape(gene)} {escape(hgvsp)} - {escape(sample_name)}</title>
    <style>{get_css_styles()}</style>
    <script>{get_javascript()}</script>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>Variant Analysis Report</h1>
            <div class="subtitle">Sample: {escape(sample_name)}</div>
        </div>

        <div class="breadcrumb">
            <a href="../../index.html">All Samples</a> &gt;
            <a href="../{safe_sample}.html">{escape(sample_name)}</a> &gt;
            {escape(gene)} {escape(chrom)}:{escape(pos)}
        </div>

        <div class="gene-hero">
            <div>
                <h1 class="gene-name">{escape(gene)}</h1>
                <div class="variant-notation">{escape(hgvsp) if hgvsp != "-" else escape(hgvsc)}</div>
            </div>
        </div>'''

        # 1. Basic Variant Information
        html += self._panel_html(
            "Basic Variant Information", "panel-basic",
            self._data_grid_html(row_idx, COLUMN_GROUPS["basic_info"]),
            collapsed=False
        )

        # 2. IGV Screenshot (after Basic Info)
        if igv_path:
            rel_igv = os.path.relpath(igv_path, str(variant_html_dir))
            igv_content = f'''
                <img src="{rel_igv}" alt="IGV Screenshot for {escape(gene)} at {escape(chrom)}:{escape(pos)}"
                     class="igv-image" onerror="this.style.display='none'; this.nextElementSibling.style.display='block';">
                <div class="igv-no-image" style="display: none;">
                    Screenshot not available
                </div>'''
        else:
            igv_content = '<div class="igv-no-image">No IGV screenshot available for this variant</div>'

        html += self._panel_html("IGV Screenshot", "panel-igv", igv_content, collapsed=False)

        # 3. Sample Comparison
        html += self._panel_html(
            "Sample Comparison Data", "panel-comparison",
            self._data_grid_html(row_idx, COLUMN_GROUPS["sample_comparison"]),
            collapsed=False
        )

        # 4. Additional Variant Information
        html += self._panel_html(
            "Additional Variant Information", "panel-additional",
            self._data_grid_html(row_idx, COLUMN_GROUPS["additional_info"]),
            collapsed=False
        )

        # 5. Population Frequency Databases
        html += self._panel_html(
            "Population Frequency Databases", "panel-population",
            self._pop_freq_html(row_idx),
            collapsed=True
        )

        # 6. ACMG Classification Criteria
        html += self._panel_html(
            "ACMG Classification Criteria", "panel-acmg",
            self._acmg_section_html(row_idx),
            collapsed=True
        )

        # 7. Computational Predictions
        html += self._panel_html(
            "Computational Predictions", "panel-computational",
            self._computational_section_html(row_idx),
            collapsed=True
        )

        html += '''
    </div>
</body>
</html>'''
        return html

    def generate_reports(self):
        self.output_dir.mkdir(parents=True, exist_ok=True)
        samples_dir = self.output_dir / "samples"
        samples_dir.mkdir(exist_ok=True)
        variants_dir = samples_dir / "variants"
        variants_dir.mkdir(exist_ok=True)

        print("Generating landing page...")
        (self.output_dir / "index.html").write_text(self.generate_landing_page())

        for sample_name in sorted(self.samples.keys()):
            safe_sample = re.sub(r'[^\w\-_]', '_', sample_name)
            print(f"Generating pages for sample: {sample_name}")
            (samples_dir / f"{safe_sample}.html").write_text(self.generate_sample_page(sample_name))

            for row_idx in self.samples[sample_name]:
                (variants_dir / f"{safe_sample}_var{row_idx}.html").write_text(
                    self.generate_variant_page(sample_name, row_idx))

        print(f"\nHTML reports generated in: {self.output_dir}")
        print(f"  - Landing page: {self.output_dir / 'index.html'}")
        print(f"  - Sample pages: {samples_dir}")
        print(f"  - Variant pages: {variants_dir}")


def main():
    if len(sys.argv) < 2:
        print("Usage: python3 excel_to_html_report.py <input_excel_file> [output_directory] [snapshots_directory]")
        sys.exit(1)

    excel_path = sys.argv[1]
    if not os.path.isfile(excel_path):
        print(f"Error: File not found: {excel_path}")
        sys.exit(1)

    output_dir = sys.argv[2] if len(sys.argv) > 2 else "html_report"
    snapshots_dir = sys.argv[3] if len(sys.argv) > 3 else None

    generator = iSeqReportGenerator(excel_path, output_dir, snapshots_dir)
    generator.load_excel()
    generator.generate_reports()


if __name__ == "__main__":
    main()

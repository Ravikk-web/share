"""
Complete Production Word Document (.docx) Generator for ARO Cluster Upgrade Automation.
Constructs all 34 sections specified in context/feature-spec/18-doc.md plus Complete Module Wirings.
Saves to ARO_Cluster_Upgrade_Production_Documentation.docx.
"""

import os
import sys
import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor
from docx.enum.text import WD_ALIGN_PARAGRAPH
from docx.enum.table import WD_TABLE_ALIGNMENT
from docx.oxml import parse_xml
from docx.oxml.ns import nsdecls

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
DIAGRAMS_DIR = os.path.join(WORKSPACE_DIR, "ARO_Cluster_Upgrade_Diagrams")
OUTPUT_DOCX = os.path.join(WORKSPACE_DIR, "ARO_Cluster_Upgrade_Production_Documentation.docx")

# Brand colors
C_NAVY = RGBColor(15, 39, 68)       # #0F2744
C_BLUE = RGBColor(29, 78, 216)      # #1D4ED8
C_GREEN = RGBColor(26, 127, 55)     # #1A7F37
C_AMBER = RGBColor(180, 83, 9)      # #B45309
C_RED = RGBColor(180, 35, 24)       # #B42318
C_SLATE = RGBColor(51, 65, 85)      # #334155
C_BODY = RGBColor(30, 41, 59)       # #1E293B
C_MUTED = RGBColor(100, 116, 139)   # #64748B

HEX_NAVY = "0F2744"
HEX_LIGHT_BLUE = "EFF6FF"
HEX_LIGHT_GREEN = "E6F4EA"
HEX_LIGHT_AMBER = "FFF8E1"
HEX_LIGHT_RED = "FDECEA"
HEX_LIGHT_SLATE = "F8FAFC"
HEX_BORDER = "CBD5E1"

def set_cell_background(cell, fill_hex):
    tcPr = cell._element.get_or_add_tcPr()
    shd = parse_xml(f'<w:shd {nsdecls("w")} w:val="clear" w:color="auto" w:fill="{fill_hex}"/>')
    tcPr.append(shd)

def set_cell_margins(cell, top=100, bottom=100, left=150, right=150):
    tcPr = cell._element.get_or_add_tcPr()
    tcMar = parse_xml(f'<w:tcMar {nsdecls("w")}><w:top w:w="{top}" w:type="dxa"/><w:bottom w:w="{bottom}" w:type="dxa"/><w:left w:w="{left}" w:type="dxa"/><w:right w:w="{right}" w:type="dxa"/></w:tcMar>')
    tcPr.append(tcMar)

def set_table_borders(table, color="CBD5E1", sz="4", val="single"):
    tblPr = table._element.xpath('w:tblPr')
    if tblPr:
        borders = parse_xml(
            f'<w:tblBorders {nsdecls("w")}>'
            f'<w:top w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'<w:bottom w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'<w:insideH w:val="{val}" w:sz="{sz}" w:space="0" w:color="{color}"/>'
            f'<w:insideV w:val="none"/>'
            f'<w:left w:val="none"/>'
            f'<w:right w:val="none"/>'
            f'</w:tblBorders>'
        )
        tblPr[0].append(borders)

def add_h(doc, text, level):
    h = doc.add_heading(text, level=level)
    h.paragraph_format.keep_with_next = True
    run = h.runs[0]
    run.font.name = 'Arial'
    if level == 1:
        run.font.size = Pt(16)
        run.font.bold = True
        run.font.color.rgb = C_NAVY
        h.paragraph_format.space_before = Pt(18)
        h.paragraph_format.space_after = Pt(4)
    elif level == 2:
        run.font.size = Pt(12.5)
        run.font.bold = True
        run.font.color.rgb = C_BLUE
        h.paragraph_format.space_before = Pt(13)
        h.paragraph_format.space_after = Pt(3)
    elif level == 3:
        run.font.size = Pt(10.5)
        run.font.bold = True
        run.font.color.rgb = C_NAVY
        h.paragraph_format.space_before = Pt(9)
        h.paragraph_format.space_after = Pt(2)
    return h

def add_p(doc, text="", bold_prefix="", italic=False):
    p = doc.add_paragraph()
    p.paragraph_format.space_after = Pt(4)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        r_pre = p.add_run(bold_prefix)
        r_pre.font.name = 'Arial'
        r_pre.font.size = Pt(9.5)
        r_pre.font.bold = True
        r_pre.font.color.rgb = C_NAVY
    if text:
        r = p.add_run(text)
        r.font.name = 'Arial'
        r.font.size = Pt(9.5)
        r.font.italic = italic
        r.font.color.rgb = C_BODY
    return p

def add_b(doc, text, bold_prefix=""):
    p = doc.add_paragraph(style='List Bullet')
    p.paragraph_format.space_after = Pt(2)
    p.paragraph_format.line_spacing = 1.15
    if bold_prefix:
        r_pre = p.add_run(bold_prefix)
        r_pre.font.name = 'Arial'
        r_pre.font.size = Pt(9)
        r_pre.font.bold = True
        r_pre.font.color.rgb = C_NAVY
    r = p.add_run(text)
    r.font.name = 'Arial'
    r.font.size = Pt(9)
    r.font.color.rgb = C_BODY
    return p

def add_alert(doc, text, title="NOTE", alert_type="note"):
    tbl = doc.add_table(rows=1, cols=1)
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    cell = tbl.cell(0, 0)
    cell.width = Inches(6.5)
    
    bg_color = HEX_LIGHT_BLUE
    border_color = "1D4ED8"
    title_rgb = C_BLUE
    if alert_type == "important":
        bg_color = HEX_LIGHT_AMBER
        border_color = "B45309"
        title_rgb = C_AMBER
    elif alert_type == "warning":
        bg_color = HEX_LIGHT_RED
        border_color = "B42318"
        title_rgb = C_RED
    elif alert_type == "success":
        bg_color = HEX_LIGHT_GREEN
        border_color = "1A7F37"
        title_rgb = C_GREEN
        
    set_cell_background(cell, bg_color)
    set_cell_margins(cell, top=100, bottom=100, left=150, right=150)
    
    tcPr = cell._element.get_or_add_tcPr()
    borders = parse_xml(
        f'<w:tcBorders {nsdecls("w")}>'
        f'<w:left w:val="single" w:sz="24" w:space="0" w:color="{border_color}"/>'
        f'<w:top w:val="none"/><w:right w:val="none"/><w:bottom w:val="none"/>'
        f'</w:tcBorders>'
    )
    tcPr.append(borders)
    
    p = cell.paragraphs[0]
    p.paragraph_format.space_after = Pt(0)
    p.paragraph_format.line_spacing = 1.15
    r_title = p.add_run(f"[{title}] ")
    r_title.font.name = 'Arial'
    r_title.font.size = Pt(9)
    r_title.font.bold = True
    r_title.font.color.rgb = title_rgb
    
    r_text = p.add_run(text)
    r_text.font.name = 'Arial'
    r_text.font.size = Pt(9)
    r_text.font.color.rgb = C_BODY
    doc.add_paragraph().paragraph_format.space_after = Pt(2)

def add_fig(doc, img_filename, fig_num, title, caption):
    img_path = os.path.join(DIAGRAMS_DIR, img_filename)
    if os.path.exists(img_path):
        p_img = doc.add_paragraph()
        p_img.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_img.paragraph_format.space_before = Pt(6)
        p_img.paragraph_format.space_after = Pt(2)
        run_img = p_img.add_run()
        run_img.add_picture(img_path, width=Inches(6.2))
        
        p_cap = doc.add_paragraph()
        p_cap.alignment = WD_ALIGN_PARAGRAPH.CENTER
        p_cap.paragraph_format.space_after = Pt(8)
        
        r_num = p_cap.add_run(f"Figure {fig_num}: {title}. ")
        r_num.font.name = 'Arial'
        r_num.font.size = Pt(8.5)
        r_num.font.bold = True
        r_num.font.color.rgb = C_NAVY
        
        r_desc = p_cap.add_run(caption)
        r_desc.font.name = 'Arial'
        r_desc.font.size = Pt(8.5)
        r_desc.font.italic = True
        r_desc.font.color.rgb = C_MUTED
    else:
        add_alert(doc, f"Figure {fig_num}: {title} (Referenced asset: {img_filename})", "FIGURE REFERENCE", "note")

def add_tbl(doc, headers, data, col_widths=None):
    tbl = doc.add_table(rows=len(data) + 1, cols=len(headers))
    tbl.alignment = WD_TABLE_ALIGNMENT.CENTER
    tbl.autofit = False
    set_table_borders(tbl)
    
    hdr_row = tbl.rows[0]
    hdr_row._element.get_or_add_trPr().append(parse_xml(f'<w:tblHeader {nsdecls("w")}/>'))
    for idx, heading in enumerate(headers):
        cell = hdr_row.cells[idx]
        set_cell_background(cell, HEX_NAVY)
        set_cell_margins(cell, top=80, bottom=80, left=100, right=100)
        p = cell.paragraphs[0]
        p.alignment = WD_ALIGN_PARAGRAPH.LEFT
        p.paragraph_format.space_after = Pt(0)
        r = p.add_run(heading)
        r.font.name = 'Arial'
        r.font.size = Pt(8.5)
        r.font.bold = True
        r.font.color.rgb = RGBColor(255, 255, 255)
        if col_widths and idx < len(col_widths):
            cell.width = Inches(col_widths[idx])
            
    for r_idx, row_data in enumerate(data):
        row = tbl.rows[r_idx + 1]
        bg_color = HEX_LIGHT_SLATE if r_idx % 2 == 1 else "FFFFFF"
        for c_idx, cell_value in enumerate(row_data):
            cell = row.cells[c_idx]
            set_cell_background(cell, bg_color)
            set_cell_margins(cell, top=60, bottom=60, left=100, right=100)
            p = cell.paragraphs[0]
            p.alignment = WD_ALIGN_PARAGRAPH.LEFT
            p.paragraph_format.space_after = Pt(0)
            p.paragraph_format.line_spacing = 1.1
            r = p.add_run(str(cell_value))
            r.font.name = 'Arial'
            r.font.size = Pt(8)
            r.font.color.rgb = C_BODY
            if col_widths and c_idx < len(col_widths):
                cell.width = Inches(col_widths[c_idx])
                
    doc.add_paragraph().paragraph_format.space_after = Pt(4)
    return tbl

print("build_complete_word_doc engine ready.")

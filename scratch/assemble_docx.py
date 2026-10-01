"""
Master Document Assembler for ARO Cluster Upgrade Production Documentation.
Executes parts 1 through 4 and saves to ARO_Cluster_Upgrade_Production_Documentation.docx.
"""

import os
import sys
import docx
from docx import Document
from docx.shared import Inches, Pt, RGBColor

WORKSPACE_DIR = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
OUTPUT_DOCX = os.path.join(WORKSPACE_DIR, "ARO_Cluster_Upgrade_Production_Documentation.docx")

# Add workspace to path
sys.path.insert(0, WORKSPACE_DIR)

from scratch.sections_part1 import build_part1
from scratch.sections_part2 import build_part2
from scratch.sections_part3 import build_part3
from scratch.sections_part4 import build_part4

def assemble_document():
    print("Initializing Microsoft Word document...")
    doc = Document()

    # Set page margins to 0.8 inches for optimal table and diagram fitting
    for section in doc.sections:
        section.top_margin = Inches(0.8)
        section.bottom_margin = Inches(0.8)
        section.left_margin = Inches(0.8)
        section.right_margin = Inches(0.8)
        section.page_width = Inches(8.5)
        section.page_height = Inches(11.0)

    # Set base normal style font to Arial
    style = doc.styles['Normal']
    font = style.font
    font.name = 'Arial'
    font.size = Pt(9.5)
    font.color.rgb = RGBColor(30, 41, 59)

    print("Building Part 1: Sections 1-10 (Cover, Control, Overview, Architecture, Process)...")
    build_part1(doc)

    print("Building Part 2: Sections 11-18 (Roles, Workflow, Multi-Hop, Preval, Remediation, Monitoring, Postval, Operators)...")
    build_part2(doc)

    print("Building Part 3: Sections 19-25 (Complete Module Wirings, Vars, Security, Deployment, Runbook, Reporting, Logging)...")
    build_part3(doc)

    print("Building Part 4: Sections 26-34 & Appendices (Error Handling, Portability, Testing, Readiness, Risks, Glossary, Appendices A-K)...")
    build_part4(doc)

    print(f"Saving final production document to: {OUTPUT_DOCX}...")
    doc.save(OUTPUT_DOCX)
    size_mb = os.path.getsize(OUTPUT_DOCX) / (1024 * 1024)
    print(f"[OK] Production Word document generated successfully! Size: {size_mb:.2f} MB")

if __name__ == "__main__":
    assemble_document()

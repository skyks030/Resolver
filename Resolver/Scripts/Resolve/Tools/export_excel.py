#!/usr/bin/env python3
import sys
import json
import os
import subprocess

try:
    import xlsxwriter
except ImportError:
    print(json.dumps({"error": "MISSING_DEP:xlsxwriter", "message": "xlsxwriter not found. Resolver can auto-install it."}))
    sys.exit(1)

# Target on-screen size for an embedded thumbnail (px) — the row/column are sized to this once,
# and every image is scaled down (preserving aspect ratio, never upscaled) to fit inside it.
TARGET_THUMB_WIDTH_PX = 160
TARGET_THUMB_HEIGHT_PX = 100


def image_pixel_size(path):
    """Native pixel dimensions via macOS's `sips` (already relied on elsewhere in this codebase
    for thumbnail resizing) — avoids adding an image-library dependency just to read a JPEG/PNG
    header. Returns None if it can't be determined, so callers can fall back gracefully."""
    try:
        result = subprocess.run(["sips", "-g", "pixelWidth", "-g", "pixelHeight", path],
                                 capture_output=True, text=True, check=False)
        width = height = None
        for line in result.stdout.splitlines():
            line = line.strip()
            if line.startswith("pixelWidth:"):
                width = int(line.split(":", 1)[1].strip())
            elif line.startswith("pixelHeight:"):
                height = int(line.split(":", 1)[1].strip())
        if width and height:
            return width, height
    except Exception:
        pass
    return None


def export_excel(payload_path):
    try:
        with open(payload_path, 'r') as f:
            payload = json.load(f)
            
        headers = payload.get("headers", [])
        clips = payload.get("clips", [])
        output_path = payload.get("outputPath")
        
        if not output_path:
            print(json.dumps({"error": "No output path provided"}))
            return

        workbook = xlsxwriter.Workbook(output_path)
        worksheet = workbook.add_worksheet("Indexing Run")
        
        # Formats
        header_format = workbook.add_format({
            'bold': True,
            'bg_color': '#D7E4BC',
            'border': 1,
            'align': 'center',
            'valign': 'vcenter'
        })
        
        cell_format = workbook.add_format({
            'valign': 'vcenter',
            'border': 1
        })

        # Track max length for each column to auto-adjust width
        col_widths = {}
        for col, header in enumerate(headers):
            worksheet.write(0, col, header, header_format)
            col_widths[col] = len(header) + 2

        # Thumbnail column width and row height — sized once to fit TARGET_THUMB_*_PX.
        thumb_col = -1
        if "Thumbnail" in headers:
            thumb_col = headers.index("Thumbnail")
            col_widths[thumb_col] = TARGET_THUMB_WIDTH_PX / 8  # ~8px per Excel column-width unit

        # Write Data
        for row_idx, clip in enumerate(clips, start=1):
            row_height = 20 # Default
            if thumb_col != -1:
                row_height = TARGET_THUMB_HEIGHT_PX * 0.75 + 8  # px -> points, plus a little margin

            worksheet.set_row(row_idx, row_height)

            for col_idx, header in enumerate(headers):
                if header == "Thumbnail":
                    img_path = clip.get("Thumbnail")
                    if img_path and os.path.exists(img_path):
                        # A normal floating image anchored to the cell — works in every Excel
                        # version (2007+), LibreOffice, Numbers, and Google Sheets imports. The
                        # newer worksheet.embed_image() ("Place in Cell") produces an Excel-365-only
                        # rich-value/DISPIMG cell that shows as blank or #UNKNOWN! anywhere else,
                        # which is why this didn't reliably work before.
                        size = image_pixel_size(img_path)
                        if size:
                            native_w, native_h = size
                            scale = min(TARGET_THUMB_WIDTH_PX / native_w, TARGET_THUMB_HEIGHT_PX / native_h, 1.0)
                        else:
                            scale = 0.3  # Couldn't read dimensions — still insert it, just conservatively sized.
                        worksheet.insert_image(row_idx, col_idx, img_path, {
                            'x_scale': scale,
                            'y_scale': scale,
                            'object_position': 1,  # move and size with the cell
                            'description': 'Thumbnail',
                            'url': None,
                        })
                    continue
                else:
                    val = clip.get(header, "")
                
                worksheet.write(row_idx, col_idx, val, cell_format)
                
                # Update max width for this column
                val_str = str(val or "")
                col_widths[col_idx] = max(col_widths.get(col_idx, 0), len(val_str) + 2)

        # Set final column widths
        for col, width in col_widths.items():
            # Cap width at 50 to avoid crazy long columns
            worksheet.set_column(col, col, min(width, 50))
                
        workbook.close()
        print(json.dumps({"status": "success", "message": f"Excel exported to {output_path}"}))

    except Exception as e:
        print(json.dumps({"error": str(e)}))

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No payload file provided"}))
        sys.exit(1)
    
    export_excel(sys.argv[1])

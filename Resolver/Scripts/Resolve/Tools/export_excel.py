#!/usr/bin/env python3
import sys
import json
import os

try:
    import xlsxwriter
except ImportError:
    print(json.dumps({"error": "MISSING_DEP:xlsxwriter", "message": "xlsxwriter not found. Resolver can auto-install it."}))
    sys.exit(1)

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
        workbook.set_calc_mode('auto') # Ensure formulas (like DISPIMG) are calculated
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

        # Thumbnail column width and row height
        thumb_col = -1
        if "Thumbnail" in headers:
            thumb_col = headers.index("Thumbnail")
            col_widths[thumb_col] = 20 # Fixed width for thumbnails (approx 160px)

        # Write Data
        for row_idx, clip in enumerate(clips, start=1):
            row_height = 20 # Default
            if thumb_col != -1:
                row_height = 80 # Height for thumbnails
            
            worksheet.set_row(row_idx, row_height)

            for col_idx, header in enumerate(headers):
                if header == "Thumbnail":
                    img_path = clip.get("Thumbnail")
                    if img_path and os.path.exists(img_path):
                        # Restoring the "better" version (Place in Cell)
                        # We add 'description' which is reported to help with #UNKNOWN! errors on some Excel versions
                        worksheet.embed_image(row_idx, col_idx, img_path, {
                            'description': f'Thumbnail',
                            'url': None,
                            'tip': 'Clip Thumbnail'
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

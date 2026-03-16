import os
import sys
import json
import argparse
import subprocess
import shutil

def setup_addax_paths(addax_path):
    """
    Configures Python search paths and environment variables for Addax-AI.
    Ensures correct priority for YOLOv5 and MegaDetector modules.
    """
    cameratraps_path = os.path.join(addax_path, "cameratraps")
    megadetector_path = os.path.join(cameratraps_path, "megadetector")
    addax_ai_path = os.path.join(addax_path, "AddaxAI")
    
    # Define primary YOLOv5 and MegaDetector paths to prevent naming collisions
    yolo_versions_path = os.path.join(addax_path, "yolov5_versions", "yolov5_new", "yolov5")
    yolov5_path = os.path.join(megadetector_path, "yolov5")
    
    # Priority order for module discovery
    priority_paths = [
        yolo_versions_path,
        megadetector_path,
        cameratraps_path,
        yolov5_path,
        addax_ai_path,
        addax_path
    ]
    
    for p in reversed(priority_paths):
        if os.path.isdir(p) and p not in sys.path:
            sys.path.insert(0, p)
            
    os.environ["PYTHONPATH"] = os.pathsep.join(sys.path)
    
    # Standard YOLOv5 operation requires being in the repository root
    if os.path.isdir(megadetector_path):
        os.chdir(megadetector_path)

def main():
    parser = argparse.ArgumentParser(description="Addax-AI Bridge for Lightroom Integration")
    parser.add_argument("--addax-path", required=True, help="Root directory of Addax-AI files")
    parser.add_argument("--model-path", required=True, help="Path to the classification model .pt file")
    parser.add_argument("--image-dir", required=True, help="Directory containing temporary JPEG previews")
    parser.add_argument("--output-json", required=True, help="Path to save the final results JSON")
    parser.add_argument("--exclude", default="", help="Comma-separated list of classes to exclude")
    args = parser.parse_args()
    
    args.addax_path = os.path.abspath(args.addax_path)
    args.image_dir = os.path.abspath(args.image_dir)
    
    print(f"Project Path: {args.addax_path}")
    print(f"Session Folder: {args.image_dir}")
    print(f"Excluded Classes: {args.exclude if args.exclude else 'None'}")
    
    setup_addax_paths(args.addax_path)
    
    try:
        from megadetector.data_management import read_exif
        from megadetector.detection.run_detector_batch import load_and_run_detector_batch
    except ImportError as e:
        print(f"CRITICAL: Failed to import Addax-AI/MegaDetector modules: {e}")
        print("Detailed search paths:")
        for p in sys.path: print(f"  {p}")
        return

    # --- PHASE 1: Detection (MegaDetector) ---
    # Locate the standard MegaDetector model
    md_model = os.path.join(args.addax_path, "models/det/MegaDetector 5a/md_v5a.0.0.pt")
    
    # Discover images in the session directory
    images = [os.path.join(args.image_dir, f) for f in os.listdir(args.image_dir) if f.lower().endswith(('.jpg', '.jpeg'))]
    print(f"Starting object detection on {len(images)} images...")

    md_results = load_and_run_detector_batch(
        model_file=md_model,
        image_file_names=images,
        checkpoint_path=None,
        confidence_threshold=0.1,
        quiet=False
    )

    # --- PHASE 2: Species Classification (Addax-AI) ---
    print("Preparing species classification...")
    
    # Write intermediate detection results for the classifier
    temp_md_json = os.path.join(args.image_dir, "md_results.json")
    with open(temp_md_json, 'w') as f:
        json.dump({"images": md_results, "detection_categories": {"1": "animal", "2": "person", "3": "vehicle"}}, f)

    try:
        # Create a temporary model configuration to properly handle Excluded Classes
        orig_model_dir = os.path.dirname(args.model_path)
        temp_model_dir = os.path.join(args.image_dir, "temp_model")
        os.makedirs(temp_model_dir, exist_ok=True)
        
        # Load the original configuration
        with open(os.path.join(orig_model_dir, "variables.json"), 'r') as f:
            model_vars = json.load(f)
        
        # Apply exclusions by filtering 'selected_classes'
        if args.exclude:
            exclude_list = [x.strip().lower() for x in args.exclude.split(',')]
            if "selected_classes" in model_vars:
                model_vars["selected_classes"] = [c for c in model_vars["selected_classes"] if c.lower() not in exclude_list]
        
        # Save the modified configuration to the temporary model directory
        with open(os.path.join(temp_model_dir, "variables.json"), 'w') as f:
            json.dump(model_vars, f, indent=4)
        
        # Link weight files and mapping data to the temporary directory
        for filename in os.listdir(orig_model_dir):
            if filename != "variables.json":
                src = os.path.join(orig_model_dir, filename)
                dst = os.path.join(temp_model_dir, filename)
                if not os.path.exists(dst):
                    try: os.symlink(src, dst)
                    except OSError: shutil.copy2(src, dst)
        
        # Invoke the official Addax-AI classification wrapper
        model_type = model_vars.get("type", "addax-sdzwa-pt")
        script_path = os.path.join(args.addax_path, "AddaxAI", "classification_utils", "model_types", model_type, "classify_detections.py")
        temp_model_file = os.path.join(temp_model_dir, os.path.basename(args.model_path))

        print(f"Invoking classifier: {model_type}")
        subprocess.run([
            sys.executable, script_path, args.addax_path, temp_model_file,
            "0.1", "0.1", "False", temp_md_json, args.image_dir, "True", "0"
        ], check=True)
        print("Classification completed successfully.")
        
    except Exception as e:
        print(f"ERROR: Species classification failed: {e}")

    # --- PHASE 3: Taxonomic Mapping & Keyword Export ---
    try:
        # Load classification results
        with open(temp_md_json, 'r') as f:
            final_data = json.load(f)
        
        # Load taxonomy database for keyword enrichment
        tax_map = {}
        tax_csv = os.path.join(os.path.dirname(args.model_path), "taxon-mapping.csv")
        if os.path.exists(tax_csv):
            import pandas as pd
            df = pd.read_csv(tax_csv)
            def strip_prefix(s):
                s = str(s)
                for p in ['species ', 'genus ', 'family ', 'order ', 'class ']:
                    if s.lower().startswith(p): return s[len(p):]
                return s

            def to_title_case(s):
                """Converts strings to Title Case for professional keywords."""
                return str(s).strip().title()

            for _, row in df.iterrows():
                details = {
                    'family': to_title_case(strip_prefix(row.get('level_family', 'Unknown'))),
                    'species': to_title_case(strip_prefix(row.get('level_species', row['model_class']))),
                    'common': to_title_case(row.get('common_name', row['model_class']))
                }
                tax_map[str(row['model_class']).lower()] = details
                if 'level_species' in row:
                    tax_map[str(row['level_species']).lower()] = details
                    tax_map[strip_prefix(row['level_species']).lower()] = details

        cat_map = final_data.get('detection_categories', {})
        kw_export_data = []
        
        print("\n--- RESULTS PREVIEW ---")
        for img in final_data.get('images', []):
            img_filename = os.path.basename(img['file'])
            img_keywords = set()
            for det in img.get('detections', []):
                cat_name = cat_map.get(det['category'], 'animal')
                
                # Exclude internal or general categories
                if cat_name.lower() in ["person", "vehicle", "unidentified animal"]:
                    continue
                
                # Match against taxonomy map
                details = tax_map.get(cat_name.lower())
                if not details and cat_name.lower().startswith("species "):
                    details = tax_map.get(cat_name.lower()[8:])
                
                if details:
                    img_keywords.add(f"{details['family']}|{details['species']}|{details['common']}|{det['conf']}")
                else:
                    clean_name = to_title_case(cat_name[8:] if cat_name.lower().startswith("species ") else cat_name)
                    img_keywords.add(f"Unknown|{clean_name}|{clean_name}|{det['conf']}")
            
            if img_keywords:
                kw_export_data.append(f"{img_filename}|{';'.join(img_keywords)}")
                print(f"Image: {img_filename}")
                for kw in img_keywords: print(f"  Result: {kw.replace('|', ' > ')}")
        print("--- END PREVIEW ---\n")

        # Save processed keywords for the Lightroom importer
        with open(os.path.join(args.image_dir, "keywords.txt"), "w") as f:
            f.write("\n".join(kw_export_data))

    except Exception as e:
        print(f"ERROR: Final post-processing failed: {e}")

    # Synchronize excluded classes metadata for the final JSON report
    if args.exclude:
        user_excludes = [x.strip().lower() for x in args.exclude.split(',')]
        model_excludes = final_data.get('forbidden_classes', [])
        for x in user_excludes:
            if x not in model_excludes: model_excludes.append(x)
        final_data['forbidden_classes'] = model_excludes

    # Save the final consolidated JSON report
    with open(args.output_json, "w") as f:
        json.dump(final_data, f, indent=4)
    
    print("Addax-AI Analysis Completed.")

if __name__ == "__main__":
    main()

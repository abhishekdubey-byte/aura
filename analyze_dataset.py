import os
import json
import numpy as np
import pandas as pd

UPLOADS_DIR = "uploads"

def load_data():
    records = []
    for filename in os.listdir(UPLOADS_DIR):
        if not filename.endswith(".json"):
            continue
        
        filepath = os.path.join(UPLOADS_DIR, filename)
        with open(filepath, "r") as f:
            try:
                data = json.load(f)
                
                # Extract key metrics
                record = {
                    "filename": filename,
                    "finalScore": data.get("finalScore", 0),
                    "isLikelyFemale": data.get("isLikelyFemale", False),
                    "faceScore": data.get("face", {}).get("score", 0) if data.get("face") else 0,
                    "bodyScore": data.get("body", {}).get("score", 0) if data.get("body") else 0,
                    "poseScore": data.get("pose", {}).get("score", 0) if data.get("pose") else 0,
                    "advancedScore": data.get("advanced", {}).get("score", 0) if data.get("advanced") else 0,
                    "objectsScore": data.get("objects", {}).get("score", 0) if data.get("objects") else 0,
                }
                
                # Extract advanced traits
                advanced = data.get("advanced", {})
                if advanced and "components" in advanced:
                    for comp in advanced["components"]:
                        if comp.get("attribute") == "Symmetry":
                            record["emotionScore"] = comp.get("scoreImpact", 0)
                        elif comp.get("attribute") == "Racy Score":
                            record["racyScore"] = float(comp.get("measurement", "0").replace("%", ""))
                        elif comp.get("attribute") == "Nudity Score":
                            record["nudityScore"] = float(comp.get("measurement", "0").replace("%", ""))
                
                # Extract body proportions if available
                body = data.get("body", {})
                if body and "components" in body:
                    for comp in body["components"]:
                        if comp.get("attribute") == "True Shape Ratio":
                            record["shapeRatio"] = float(comp.get("measurement", "0").replace("Ratio: ", ""))
                            
                records.append(record)
            except Exception as e:
                print(f"Error reading {filename}: {e}")
                
    return pd.DataFrame(records)

def derive_formula(df):
    if df.empty:
        print("No data available yet.")
        return
        
    print(f"--- Analyzing {len(df)} images ---")
    
    # Filter only female data as requested by the user
    female_df = df[df["isLikelyFemale"] == True]
    if female_df.empty:
        female_df = df # Fallback if gender detection failed
        print("Note: Could not isolate female-only images, using entire dataset.")
    else:
        print(f"Found {len(female_df)} female images.")
    
    # Calculate Mean and Standard Deviation for all metrics
    metrics = ["faceScore", "bodyScore", "poseScore", "advancedScore"]
    stats = female_df[metrics].describe().T
    print("\n--- Aesthetic Distributions ---")
    print(stats[['mean', 'std', 'min', 'max']])
    
    # Shape Ratio Analysis
    if "shapeRatio" in female_df.columns:
        shape_stats = female_df["shapeRatio"].describe()
        optimal_ratio = shape_stats["mean"]
        ratio_std = shape_stats["std"]
        print(f"\nOptimal Body Shape Ratio derived from dataset: {optimal_ratio:.2f} (±{ratio_std:.2f})")
    
    # Deriving the formula
    print("\n--- Derived Mathematical Formula ---")
    print("Based on this dataset, the optimized AURA score formula is:")
    
    face_weight = (stats.loc["faceScore", "mean"] / 1000) * 100
    body_weight = (stats.loc["bodyScore", "mean"] / 1000) * 100
    pose_weight = (stats.loc["poseScore", "mean"] / 1000) * 100
    
    total = face_weight + body_weight + pose_weight
    
    # Normalize weights
    fw = (face_weight / total) * 100
    bw = (body_weight / total) * 100
    pw = (pose_weight / total) * 100
    
    print(f"AURA_SCORE = (FaceScore * {fw:.1f}%) + (BodyScore * {bw:.1f}%) + (PoseScore * {pw:.1f}%)")
    print("\nFormula Enhancements (Dataset Boosts):")
    if "shapeRatio" in female_df.columns and not np.isnan(optimal_ratio):
        print(f"1. Body Shape Boost: If user's shape ratio is between {optimal_ratio - ratio_std:.2f} and {optimal_ratio + ratio_std:.2f}, add +15% Boost.")
    
    if "racyScore" in female_df.columns:
        racy_mean = female_df["racyScore"].mean()
        print(f"2. Aesthetic Risk Boost: The dataset averages a {racy_mean:.1f}% racy score. If user matches this range, add +50 points.")
        
    print("\nTo apply this to Flutter, we will map these exact statistical thresholds into aura_calculator.dart!")

if __name__ == "__main__":
    df = load_data()
    derive_formula(df)

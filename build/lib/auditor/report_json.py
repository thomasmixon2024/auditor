import datetime
import json
import os

def generate_json_report(results, bundle_path):
    json_path = os.path.join(bundle_path, "report.json")
    with open(json_path, "w") as f:
        json.dump(results, f, indent=4)
    print(f"JSON report saved to: {json_path}")

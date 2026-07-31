import json
import os

from auditor.paths import LATEST_SARIF

def generate_sarif_report(results, bundle_path):
    sarif_path = os.path.join(bundle_path, "report.sarif")

    sarif = {
        "version": "2.1.0",
        "runs": []
    }

    for project, tools in results.items():
        sarif["runs"].append({
            "tool": {
                "driver": {
                    "name": "Auditor",
                    "informationUri": "https://example.com",
                    "rules": []
                }
            },
            "results": [
                {
                    "ruleId": tool,
                    "message": {"text": output},
                    "level": "warning"
                }
                for tool, output in tools.items()
            ]
        })

    with open(sarif_path, "w") as f:
        json.dump(sarif, f, indent=4)

    # Create/update a "latest.sarif" pointer for the VSCode SARIF viewer.
    # Symlinks aren't reliably creatable on Windows without dev mode/admin,
    # so fall back to a plain copy instead of crashing the whole audit.
    try:
        if os.path.islink(LATEST_SARIF) or os.path.exists(LATEST_SARIF):
            os.remove(LATEST_SARIF)
        os.symlink(sarif_path, LATEST_SARIF)
    except OSError:
        import shutil
        shutil.copyfile(sarif_path, LATEST_SARIF)

    print(f"SARIF report saved to: {sarif_path}")

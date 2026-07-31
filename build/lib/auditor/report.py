import datetime
import os

def generate_report(results, bundle_path):
    ts = datetime.datetime.now().strftime("%Y-%m-%d_%H-%M-%S")
    report_path = os.path.join(bundle_path, "report.txt")

    with open(report_path, "w") as f:
        f.write("=== AUDIT REPORT ===\n")

        for project, tools in results.items():
            f.write(f"\n\n## PROJECT: {project}\n")
            for tool, output in tools.items():
                f.write(f"\n--- {tool.upper()} ---\n")
                f.write(output + "\n")

    print(f"Text report saved to: {report_path}")

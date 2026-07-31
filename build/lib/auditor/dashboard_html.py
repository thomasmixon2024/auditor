import html
import json
import os


def generate_dashboard(results, bundle_path):
    dashboard_path = os.path.join(bundle_path, "dashboard.html")

    summary_rows = []
    for project, tools in results.items():
        ruff_len = len((tools.get("ruff") or "").strip().splitlines())
        bandit_len = len((tools.get("bandit") or "").strip().splitlines())
        semgrep_len = len((tools.get("semgrep") or "").strip().splitlines())
        summary_rows.append((project, ruff_len, bandit_len, semgrep_len))

    projects = [p for p, *_ in summary_rows]
    ruff_counts = [r for _, r, _, _ in summary_rows]
    bandit_counts = [b for _, _, b, _ in summary_rows]
    semgrep_counts = [s for _, _, _, s in summary_rows]

    page = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Audit Dashboard</title>
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<style>
body { font-family: Arial, sans-serif; background: #202124; color: #e8eaed; margin: 0; padding: 20px; }
table { border-collapse: collapse; width: 100%; margin-bottom: 20px; }
th, td { border: 1px solid #5f6368; padding: 8px; word-break: break-all; }
.section { background: #303134; padding: 15px; border-radius: 8px; margin-bottom: 20px; }
pre { background: #1e1f21; padding: 10px; border-radius: 6px; overflow-x: auto; white-space: pre-wrap; word-break: break-word; }
</style>
</head>
<body>

<h1>Audit Dashboard</h1>

<h2>Visual Summary</h2>
<canvas id="projectChart" height="120"></canvas>

<h2>Summary Table</h2>
<table>
<tr><th>Project</th><th>Ruff</th><th>Bandit</th><th>Semgrep</th></tr>
"""

    for project, ruff_len, bandit_len, semgrep_len in summary_rows:
        safe_project = html.escape(project)
        page += f"<tr><td>{safe_project}</td><td>{ruff_len}</td><td>{bandit_len}</td><td>{semgrep_len}</td></tr>"

    page += "</table>"

    for project, tools in results.items():
        safe_project = html.escape(project)
        page += f"<div class='section'><h2>{safe_project}</h2>"
        for tool, output in tools.items():
            safe_tool = html.escape(str(tool).upper())
            # Same stored-XSS issue as report_html.py: raw tool stdout
            # (which can contain scanned source/filenames) must be escaped
            # before landing in the page.
            safe_output = html.escape(str(output))
            page += f"<h3>{safe_tool}</h3><pre>{safe_output}</pre>"
        page += "</div>"

    def js_safe(value):
        """json.dumps() correctly escapes for JS string syntax, but knows
        nothing about the surrounding <script> tag: a project path
        containing literal '</script>' would still close the tag early
        and let the rest of the string be parsed as raw HTML/JS by the
        browser. Escaping the forward slash neutralizes that without
        changing the decoded value."""
        return json.dumps(value).replace("</", "<\\/")

    chart_script = f"""
<script>
new Chart(document.getElementById('projectChart'), {{
    type: 'bar',
    data: {{
        labels: {js_safe(projects)},
        datasets: [
            {{ label: 'Ruff', data: {js_safe(ruff_counts)}, backgroundColor: '#4285F4' }},
            {{ label: 'Bandit', data: {js_safe(bandit_counts)}, backgroundColor: '#DB4437' }},
            {{ label: 'Semgrep', data: {js_safe(semgrep_counts)}, backgroundColor: '#F4B400' }}
        ]
    }},
    options: {{ responsive: true }}
}});
</script>

</body></html>
"""
    page += chart_script

    with open(dashboard_path, "w") as f:
        f.write(page)

    print(f"Dashboard HTML saved to: {dashboard_path}")

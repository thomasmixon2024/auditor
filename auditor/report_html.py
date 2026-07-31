import html
import os


def generate_html_report(results, bundle_path):
    html_path = os.path.join(bundle_path, "report.html")

    page = """
<!DOCTYPE html>
<html>
<head>
<meta charset="UTF-8">
<title>Audit Report</title>
<style>
:root {
    --bg: #f5f5f5;
    --text: #000;
    --sidebar-bg: #222;
    --sidebar-text: #eee;
    --section-bg: #fff;
    --code-bg: #111;
    --code-text: #eee;
}
body.dark {
    --bg: #111;
    --text: #eee;
    --sidebar-bg: #000;
    --sidebar-text: #fff;
    --section-bg: #222;
    --code-bg: #000;
    --code-text: #0f0;
}
body {
    margin: 0;
    font-family: Arial, sans-serif;
    background: var(--bg);
    color: var(--text);
}
.sidebar {
    position: fixed;
    width: 240px;
    height: 100%;
    background: var(--sidebar-bg);
    color: var(--sidebar-text);
    padding: 20px;
    overflow-y: auto;
}
.sidebar a {
    color: var(--sidebar-text);
    text-decoration: none;
    display: block;
    margin-bottom: 10px;
    word-break: break-all;
}
.toggle {
    margin-top: 20px;
    padding: 10px;
    background: var(--section-bg);
    color: var(--text);
    border-radius: 6px;
    cursor: pointer;
}
.content {
    margin-left: 260px;
    padding: 20px;
}
.section {
    background: var(--section-bg);
    padding: 15px;
    margin-bottom: 20px;
    border-radius: 8px;
}
pre {
    background: var(--code-bg);
    color: var(--code-text);
    padding: 10px;
    border-radius: 6px;
    overflow-x: auto;
    white-space: pre-wrap;
    word-break: break-word;
}
</style>
<script>
function toggleTheme() {
    document.body.classList.toggle('dark');
    localStorage.setItem('theme', document.body.classList.contains('dark') ? 'dark' : 'light');
}
window.onload = () => {
    if (localStorage.getItem('theme') === 'dark') {
        document.body.classList.add('dark');
    }
};
</script>
</head>
<body>

<div class="sidebar">
<h2>Projects</h2>
"""

    for project in results.keys():
        # Anchor ids and hrefs must be escaped too - a project path
        # containing a quote could otherwise break out of the attribute.
        safe_id = html.escape(project.replace("/", "_"), quote=True)
        safe_label = html.escape(project)
        page += f'<a href="#{safe_id}">{safe_label}</a>'

    page += """
<div class="toggle" onclick="toggleTheme()">Toggle Theme</div>
</div>
<div class="content">
"""

    for project, tools in results.items():
        safe_id = html.escape(project.replace("/", "_"), quote=True)
        safe_project = html.escape(project)
        page += f"<div class='section' id='{safe_id}'><h2>{safe_project}</h2>"
        for tool, output in tools.items():
            safe_tool = html.escape(str(tool).upper())
            # This is the important one: tool output can contain filenames,
            # code snippets, or literal '<script>' strings from whatever
            # was scanned. Previously this went into the page unescaped,
            # which is a stored-XSS hole in a *security report*.
            safe_output = html.escape(str(output))
            page += f"<h3>{safe_tool}</h3><pre>{safe_output}</pre>"
        page += "</div>"

    page += "</div></body></html>"

    with open(html_path, "w") as f:
        f.write(page)

    print(f"HTML report saved to: {html_path}")

import hmac
import os
import sys

from flask import Flask, send_from_directory, jsonify, request, abort

from auditor.paths import LOGS_DIR

# Allow unauthenticated local access when no token is configured. This keeps
# the report server usable for quick local auditing without blocking the flow.
API_TOKEN = os.environ.get("AUDITOR_API_TOKEN")
AUTH_ENABLED = bool(API_TOKEN)


def token_is_valid(provided_token: str) -> bool:
    if not AUTH_ENABLED:
        return True
    return hmac.compare_digest(provided_token or "", API_TOKEN)

app = Flask(__name__)


@app.before_request
def require_token():
    token = request.headers.get("X-Auditor-Token", "")
    if AUTH_ENABLED and not token_is_valid(token):
        abort(401)


def _bundles():
    if not LOGS_DIR.is_dir():
        return []
    return sorted([d for d in os.listdir(LOGS_DIR) if d.startswith("audit_")], reverse=True)


@app.get("/bundles")
def bundles():
    return jsonify(_bundles())


@app.get("/latest/dashboard")
def latest_dashboard():
    all_bundles = _bundles()
    if not all_bundles:
        return {"error": "No bundles found"}, 404
    return send_from_directory(LOGS_DIR / all_bundles[0], "dashboard.html")


@app.get("/latest/json")
def latest_json():
    all_bundles = _bundles()
    if not all_bundles:
        return {"error": "No bundles found"}, 404
    return send_from_directory(LOGS_DIR / all_bundles[0], "report.json")


@app.get("/latest/sarif")
def latest_sarif():
    all_bundles = _bundles()
    if not all_bundles:
        return {"error": "No bundles found"}, 404
    return send_from_directory(LOGS_DIR / all_bundles[0], "report.sarif")


if __name__ == "__main__":
    # debug=True on 0.0.0.0 exposes Werkzeug's interactive debugger, which
    # is remote-code-execution-capable to anyone who can reach this port.
    # Default is now localhost-only with debug off; both are explicitly
    # opt-in via environment variables for anyone who really wants LAN
    # access, so it's a deliberate choice rather than an accident.
    host = os.environ.get("AUDITOR_SERVER_HOST", "127.0.0.1")
    debug = os.environ.get("AUDITOR_SERVER_DEBUG", "false").lower() == "true"
    app.run(host=host, port=5000, debug=debug)

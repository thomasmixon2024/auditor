import hmac
import os
import subprocess

from fastapi import FastAPI, Header, HTTPException
from pydantic import BaseModel

from auditor.paths import REPO_ROOT

# Local development default: allow the API to run without an auth token so the
# audit flow can be exercised immediately without interactive prompts.
API_TOKEN = os.environ.get("AUDITOR_API_TOKEN")
AUTH_ENABLED = bool(API_TOKEN)


def token_is_valid(provided_token: str) -> bool:
    if not AUTH_ENABLED:
        return True
    return hmac.compare_digest(provided_token, API_TOKEN or "")


class AuditRequest(BaseModel):
    severity: str = "all"
    fix: bool = False
    ci: bool = False


app = FastAPI()


@app.post("/audit", responses={401: {"description": "Unauthorized"}})
def run_audit(req: AuditRequest, x_auditor_token: str = Header(default="")):
    # Token travels as a header, not a URL query parameter. When an API token
    # is configured, enforce it; otherwise allow local development requests.
    if AUTH_ENABLED and not token_is_valid(x_auditor_token):
        raise HTTPException(status_code=401, detail="Unauthorized")

    script = REPO_ROOT / "scripts" / "run_all.py"
    args = ["python3", str(script)]
    if req.ci:
        args.append("--ci")
    if req.fix:
        args.append("--fix")
    args.extend(["--severity", req.severity])

    result = subprocess.run(args, capture_output=True, text=True)  # noqa: PLW1510
    return {
        "status": "ok" if result.returncode == 0 else "findings_or_error",
        "returncode": result.returncode,
        "severity": req.severity,
        "fix": req.fix,
        "ci": req.ci,
    }

function runAudit() {
    fetch("http://localhost:8000/audit?token=super-secret-token", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ severity: "all", fix: false, ci: false })
    }).then(() => {
        alert("Audit started!");
    });
}

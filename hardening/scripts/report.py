#!/usr/bin/env python3
"""Builds the BEFORE / AFTER markdown reports, the before/after diff, and the
gate verdict from the raw scanner outputs in a hardening run directory.

Usage:
  report.py before <dir>                 -> <dir>/before/report.md, summary.json
  report.py after  <dir> [gate options]  -> <dir>/after/report.md, summary.json,
                                            <dir>/diff.md, <dir>/gate.json
Exit code 0 always; the workflow reads gate.json.
"""
import argparse, json, os, sys
import xml.etree.ElementTree as ET
from collections import Counter

SEV = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]
XCCDF = {"x": "http://checklists.nist.gov/xccdf/1.2"}


def load(path, default=None):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def trivy_summary(path):
    d = load(path, {}) or {}
    vulns, secrets, misconf = [], [], []
    for r in d.get("Results") or []:
        vulns += r.get("Vulnerabilities") or []
        secrets += r.get("Secrets") or []
        misconf += [m for m in (r.get("Misconfigurations") or []) if m.get("Status") == "FAIL"]
    by = Counter(v.get("Severity", "UNKNOWN") for v in vulns)
    fixable = Counter(v.get("Severity", "UNKNOWN") for v in vulns if v.get("FixedVersion"))
    os_ = (d.get("Metadata") or {}).get("OS") or {}
    top = sorted(
        vulns,
        key=lambda v: (SEV.index(v.get("Severity", "UNKNOWN")), -(v.get("CVSS", {}).get("nvd", {}).get("V3Score") or 0)),
    )
    seen, top_list = set(), []
    for v in top:
        k = (v.get("VulnerabilityID"), v.get("PkgName"))
        if k in seen or v.get("Severity") not in ("CRITICAL", "HIGH"):
            continue
        seen.add(k)
        top_list.append({k2: v.get(k2) for k2 in ("VulnerabilityID", "PkgName", "InstalledVersion", "FixedVersion", "Severity", "Title")})
        if len(top_list) >= 15:
            break
    return {
        "os": f'{os_.get("Family", "?")} {os_.get("Name", "?")}',
        "total": len(vulns),
        "by_severity": {s: by.get(s, 0) for s in SEV},
        "fixable": {s: fixable.get(s, 0) for s in SEV},
        "secrets": len(secrets),
        "misconfigurations": len(misconf),
        "top": top_list,
    }


def dockle_summary(path):
    d = load(path, {}) or {}
    s = d.get("summary", {})
    return {
        "fatal": s.get("fatal", 0), "warn": s.get("warn", 0), "info": s.get("info", 0), "pass": s.get("pass", 0),
        "findings": [{"code": x.get("code"), "level": x.get("level"), "title": x.get("title")} for x in d.get("details", [])],
    }


def stig_summary(path):
    try:
        root = ET.parse(path).getroot()
    except (OSError, ET.ParseError):
        return None
    tr = root if root.tag.endswith("TestResult") else root.find(".//x:TestResult", XCCDF)
    if tr is None:
        return None
    titles = {}
    for rule in root.iter("{%s}Rule" % XCCDF["x"]):
        t = rule.find("x:title", XCCDF)
        titles[rule.get("id")] = (t.text if t is not None else rule.get("id"), rule.get("severity"))
    results = Counter()
    failed = []
    for rr in tr.findall("x:rule-result", XCCDF):
        res = rr.find("x:result", XCCDF).text
        if res == "notselected":
            continue
        results[res] += 1
        if res in ("fail", "error", "unknown"):
            rid = rr.get("idref")
            title, sev = titles.get(rid, (rid, rr.get("severity")))
            failed.append({"rule": rid.replace("xccdf_org.ssgproject.content_rule_", ""), "title": title, "severity": rr.get("severity") or sev, "result": res})
    score = None
    for s in tr.findall("x:score", XCCDF):
        score = float(s.text)
    evaluated = results.get("pass", 0) + results.get("fail", 0)
    return {
        "profile": (tr.find("x:profile", XCCDF).get("idref") if tr.find("x:profile", XCCDF) is not None else None),
        "results": dict(results),
        "evaluated": evaluated,
        "pass_rate": round(100.0 * results.get("pass", 0) / evaluated, 1) if evaluated else 0.0,
        "score": score,
        "failed": failed,
    }


def summarize(stage_dir):
    meta = load(os.path.join(stage_dir, "meta.json"), {}) or {}
    return {
        "meta": meta,
        "trivy": trivy_summary(os.path.join(stage_dir, "trivy.json")),
        "dockle": dockle_summary(os.path.join(stage_dir, "dockle.json")),
        "stig": stig_summary(os.path.join(stage_dir, "stig-results.xml")),
        "fips": load(os.path.join(stage_dir, "fips.json"), {"result": "not run", "checks": []}),
    }


def md_report(title, s):
    m = s["meta"]
    t, d, st, f = s["trivy"], s["dockle"], s["stig"], s["fips"]
    out = [f"# {title}", ""]
    out += ["| | |", "|---|---|"]
    for k in ("image", "digest", "base", "user", "ports", "size_mb", "packages", "scanned_at"):
        if k in m:
            out.append(f"| {k} | `{m[k]}` |")
    out += ["", "## Vulnerabilities (Trivy)", "", f"OS: {t['os']}. Total: **{t['total']}**. Secrets: {t['secrets']}. Misconfigurations: {t['misconfigurations']}.", ""]
    out += ["| Severity | Count | Fixable |", "|---|---:|---:|"]
    out += [f"| {sv} | {t['by_severity'][sv]} | {t['fixable'][sv]} |" for sv in SEV]
    if t["top"]:
        out += ["", "Top CRITICAL/HIGH:", "", "| CVE | Package | Installed | Fixed | Severity |", "|---|---|---|---|---|"]
        out += [f"| {v['VulnerabilityID']} | {v['PkgName']} | {v['InstalledVersion']} | {v['FixedVersion'] or '-'} | {v['Severity']} |" for v in t["top"]]
    out += ["", "## CIS Docker Benchmark (Dockle)", "", f"FATAL {d['fatal']} / WARN {d['warn']} / INFO {d['info']} / PASS {d['pass']}", ""]
    if d["findings"]:
        out += ["| Code | Level | Title |", "|---|---|---|"] + [f"| {x['code']} | {x['level']} | {x['title']} |" for x in d["findings"]]
    out += ["", "## DISA STIG (OpenSCAP, SSG RHEL 9, tailored)", ""]
    if st:
        r = st["results"]
        out.append(f"Profile `{st['profile']}`. Pass **{r.get('pass', 0)}**, fail **{r.get('fail', 0)}**, "
                   f"not applicable {r.get('notapplicable', 0)}, not checked {r.get('notchecked', 0)}. "
                   f"Pass rate of evaluated rules: **{st['pass_rate']}%**.")
        if st["evaluated"] == 0:
            out += ["", "_No STIG rules are applicable: the image is not RHEL-based, so the RHEL 9 STIG cannot be evaluated or met._"]
        if st["failed"]:
            out += ["", "| Rule | Severity | Result |", "|---|---|---|"] + [f"| {x['title']} (`{x['rule']}`) | {x['severity']} | {x['result']} |" for x in st["failed"]]
    else:
        out.append("_Not run._")
    out += ["", "## FIPS 140-3", "", f"Result: **{f.get('result')}**", ""]
    if f.get("checks"):
        out += ["| Check | Result | Detail |", "|---|---|---|"] + [f"| {c['desc']} | {c['result']} | {c['detail']} |" for c in f["checks"]]
    if f.get("note"):
        out += ["", f"_{f['note']}_"]
    return "\n".join(out) + "\n"


def delta(a, b):
    d = b - a
    return f"{a} → {b} ({'+' if d > 0 else ''}{d})"


def md_diff(b, a, gate):
    tb, ta = b["trivy"], a["trivy"]
    sb, sa = b["stig"] or {"results": {}, "pass_rate": 0}, a["stig"] or {"results": {}, "pass_rate": 0}
    out = ["# Before / after", "", "| Metric | Before | After |", "|---|---|---|"]
    out.append(f"| Base | {tb['os']} | {ta['os']} |")
    for k in ("user", "ports", "size_mb", "packages"):
        out.append(f"| {k} | {b['meta'].get(k, '-')} | {a['meta'].get(k, '-')} |")
    for sv in SEV[:4]:
        out.append(f"| CVEs {sv} | {tb['by_severity'][sv]} | {ta['by_severity'][sv]} |")
    out.append(f"| CVEs fixable (all) | {sum(tb['fixable'].values())} | {sum(ta['fixable'].values())} |")
    out.append(f"| Secrets | {tb['secrets']} | {ta['secrets']} |")
    out.append(f"| Dockle FATAL/WARN | {b['dockle']['fatal']}/{b['dockle']['warn']} | {a['dockle']['fatal']}/{a['dockle']['warn']} |")
    out.append(f"| STIG pass/fail | {sb['results'].get('pass', 0)}/{sb['results'].get('fail', 0)} | {sa['results'].get('pass', 0)}/{sa['results'].get('fail', 0)} |")
    out.append(f"| STIG pass rate | {sb['pass_rate']}% | {sa['pass_rate']}% |")
    out.append(f"| FIPS | {b['fips'].get('result')} | {a['fips'].get('result')} |")
    out += ["", f"## Gate: **{gate['result'].upper()}**", ""] + [f"- {'✅' if c['ok'] else '❌'} {c['name']}: {c['detail']}" for c in gate["checks"]]
    fixed_ids = {v["VulnerabilityID"] for v in tb["top"]} - {v["VulnerabilityID"] for v in ta["top"]}
    if fixed_ids:
        out += ["", f"Eliminated top CRITICAL/HIGH CVEs: {', '.join(sorted(fixed_ids))}"]
    return "\n".join(out) + "\n"


def gate(a, args):
    t, st, f, d = a["trivy"], a["stig"], a["fips"], a["dockle"]
    checks = []
    fc = t["fixable"]["CRITICAL"]
    checks.append({"name": "No fixable CRITICAL CVEs", "ok": fc == 0, "detail": f"{fc} fixable CRITICAL"})
    if args.no_fixable_high:
        fh = t["fixable"]["HIGH"]
        checks.append({"name": "No fixable HIGH CVEs", "ok": fh == 0, "detail": f"{fh} fixable HIGH"})
    checks.append({"name": "No secrets in image", "ok": t["secrets"] == 0, "detail": f"{t['secrets']} secrets"})
    if st:
        fails = st["results"].get("fail", 0) + st["results"].get("error", 0)
        high = sum(1 for x in st["failed"] if x["severity"] == "high")
        ok = st["pass_rate"] >= args.stig_min_pass_rate and fails <= args.stig_max_fail and high == 0 and st["evaluated"] > 0
        checks.append({"name": f"STIG pass rate ≥ {args.stig_min_pass_rate}%, ≤ {args.stig_max_fail} fails, 0 CAT I",
                       "ok": ok, "detail": f"{st['pass_rate']}% of {st['evaluated']} evaluated, {fails} fail/error, {high} high-severity fail"})
    else:
        checks.append({"name": "STIG scan ran", "ok": False, "detail": "no results"})
    checks.append({"name": "FIPS verification passed", "ok": f.get("result") == "pass", "detail": f"{f.get('passed', 0)} passed, {f.get('failed', '?')} failed"})
    checks.append({"name": "Dockle: no FATAL", "ok": d["fatal"] == 0, "detail": f"{d['fatal']} FATAL, {d['warn']} WARN"})
    checks.append({"name": "Runs as non-root", "ok": str(a["meta"].get("user", "")) not in ("", "0", "root") and not str(a["meta"].get("user", "")).startswith("0:"), "detail": f"user={a['meta'].get('user')}"})
    checks.append({"name": "Smoke test passed", "ok": a["meta"].get("smoke_test") == "pass", "detail": str(a["meta"].get("smoke_test"))})
    return {"result": "pass" if all(c["ok"] for c in checks) else "fail", "checks": checks}


def main():
    p = argparse.ArgumentParser()
    p.add_argument("stage", choices=["before", "after"])
    p.add_argument("dir")
    p.add_argument("--stig-min-pass-rate", type=float, default=95.0)
    p.add_argument("--stig-max-fail", type=int, default=0)
    p.add_argument("--no-fixable-high", action="store_true")
    args = p.parse_args()

    stage_dir = os.path.join(args.dir, args.stage)
    s = summarize(stage_dir)
    with open(os.path.join(stage_dir, "summary.json"), "w") as f:
        json.dump(s, f, indent=2)
    title = "BEFORE hardening: source image" if args.stage == "before" else "AFTER hardening: hardened image"
    with open(os.path.join(stage_dir, "report.md"), "w") as f:
        f.write(md_report(title, s))
    if args.stage == "after":
        b = load(os.path.join(args.dir, "before", "summary.json"))
        g = gate(s, args)
        with open(os.path.join(args.dir, "gate.json"), "w") as f:
            json.dump(g, f, indent=2)
        with open(os.path.join(args.dir, "diff.md"), "w") as f:
            f.write(md_diff(b, s, g))
        print(f"gate: {g['result']}")
        for c in g["checks"]:
            print(f"  {'PASS' if c['ok'] else 'FAIL'}  {c['name']}: {c['detail']}")


if __name__ == "__main__":
    sys.exit(main())

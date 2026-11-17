"""Tests for scripts/cli-review.sh and scripts/check-ci-status.sh (its CR_CLI_LOG branch, review layers and CI verdict).

Run from anywhere: python3 tests/run_tests.py
The fakes in tests/bin stand in for gh and the CodeRabbit CLI, and a throwaway git repo
stands in for the PR checkout, so no CodeRabbit review is spent and nothing reaches GitHub.
Scripts run under /bin/bash (bash 3.2 on macOS), the oldest bash the skill can meet.
"""
import glob
import json
import os
import shutil
import subprocess
import tempfile

T = os.path.dirname(os.path.abspath(__file__))
S = os.path.join(os.path.dirname(T), "scripts")
BASH = "/bin/bash" if os.path.exists("/bin/bash") else "bash"
FAKE_CLI = os.path.join(T, "bin", "coderabbit-fake")
WORK = tempfile.mkdtemp(prefix="coderabbit-resolver-tests-")
REPO = os.path.join(WORK, "repo")
FIX = os.path.join(WORK, "fixtures")
LOGS = os.path.join(WORK, "logs")
results = []


def git(*args):
    # Hooks and signing from the user's global config must not run in the throwaway repo.
    cmd = ["git", "-C", REPO, "-c", "core.hooksPath=/dev/null", "-c", "commit.gpgsign=false"] + list(args)
    return subprocess.run(cmd, check=True, capture_output=True, text=True).stdout.strip()


def commit(name):
    with open(os.path.join(REPO, name), "w") as f:
        f.write(name + "\n")
    git("add", name)
    git("-c", "user.name=test", "-c", "user.email=test@example.invalid", "commit", "-q", "-m", name)
    return git("rev-parse", "HEAD")


# A PR checkout: PARENT then HEAD on main, with origin pointing at itself so `git fetch origin main` works.
os.makedirs(REPO)
os.makedirs(FIX)
git("init", "-q")
git("checkout", "-q", "-b", "main")
PARENT = commit("a.txt")
HEAD = commit("b.txt")
git("remote", "add", "origin", REPO)
git("fetch", "-q", "origin")
OTHER = "a" * 40  # a commit that is neither HEAD nor in its history


def fixture(name, lines):
    path = os.path.join(FIX, name)
    with open(path, "w") as f:
        for line in lines:
            f.write((line if isinstance(line, str) else json.dumps(line)) + "\n")
    return path


def meta(head):
    return {"type": "resolver_meta", "owner": "o", "repo": "r", "pr": 1, "head": head, "base": "main", "baseCommit": PARENT}


def finding(i, sev="minor"):
    return {"type": "finding", "severity": sev, "fileName": f"src/f{i}.ts",
            "comment": f"Finding {i} first line\nsecond line", "codegenInstructions": "do x", "suggestions": ""}


def done(n, status="review_completed"):
    return {"type": "complete", "status": status, "findings": n}


OK0 = fixture("ok0.jsonl", [meta(HEAD), {"type": "heartbeat"}, "Update available: 0.7.7", done(0)])
F2 = fixture("f2.jsonl", [meta(HEAD), finding(1, "major"), finding(2), done(2)])
ERR = fixture("err.jsonl", [meta(HEAD), {"type": "error", "message": "Rate limit exceeded. Try again in 12 minutes."}])
NOMETA = fixture("nometa.jsonl", [done(0)])
MISMATCH = fixture("mismatch.jsonl", [meta(OTHER), done(0)])
ANCESTOR = fixture("ancestor.jsonl", [meta(PARENT), finding(1), done(1)])
NOT_ANCESTOR = fixture("notancestor-f1.jsonl", [meta(OTHER), finding(1), done(1)])
FAILED = fixture("status-other.jsonl", [meta(HEAD), {"type": "complete", "status": "review_failed", "findings": 0}])
REPORTED_MORE = fixture("reported-more.jsonl", [meta(HEAD), finding(1), done(3)])
NOSTATUS = fixture("nostatus.jsonl", [meta(HEAD), {"type": "complete"}])
ARRAY = fixture("array-findings.jsonl", [meta(HEAD), {"type": "complete", "status": "completed", "findings": [{"a": 1}, {"b": 2}]}])
INCOMPLETE = fixture("incomplete.jsonl", [meta(HEAD), finding(1)])
EMPTY = fixture("empty.jsonl", [])


def run(name, args, expect, env=None, contains=(), absent=(), cwd=REPO):
    e = dict(os.environ)
    e["PATH"] = os.path.join(T, "bin") + os.pathsep + e["PATH"]
    e["CR_CLI_LOG_DIR"] = LOGS
    e["FAKE_HEAD"] = HEAD
    for k in ("CR_CLI_LOG", "CR_CLI_ACCEPT", "CR_CLI_MODE", "CR_CLI_BIN", "FAKE_BUILD", "FAKE_CHECKS", "FAKE_CR_DESC",
              "FAKE_COMMENT", "FAKE_REVIEW_IDS", "FAKE_HEAD_FIRST", "FAKE_BODY"):
        e.pop(k, None)
    # The gate polls every second, and each run gets its own state for the fake gh.
    e["CR_CHECK_INTERVAL"] = "1"
    e["FAKE_STATE"] = tempfile.mkdtemp(dir=WORK, prefix="state-")
    if env:
        e.update(env)
    p = subprocess.run([BASH] + args, env=e, cwd=cwd, capture_output=True, text=True, timeout=180)
    out = p.stdout + p.stderr
    missing = [c for c in contains if c not in out]
    present = [a for a in absent if a in out]
    ok = p.returncode == expect and not missing and not present
    results.append(ok)
    print(("PASS" if ok else "FAIL"), "|", name, "| exit", p.returncode, "expected", expect)
    if not ok:
        if missing:
            print("  missing:", missing)
        if present:
            print("  unexpected:", present)
        print("  " + out.replace("\n", "\n  "))
    return out


def check(name, ok, detail=""):
    results.append(ok)
    print(("PASS" if ok else "FAIL"), "|", name, "" if ok else detail)


def newest_log():
    logs = sorted(glob.glob(os.path.join(LOGS, "o", "r", "pr1-*.jsonl")), key=os.path.getmtime)
    return logs[-1]


CR = os.path.join(S, "cli-review.sh")
V = [CR, "--verify"]
FAKE = {"CR_CLI_BIN": FAKE_CLI}

# --verify: the merge gate's view of a log
run("verify: 0 findings on HEAD", V + [OK0, HEAD], 0)
run("verify: 0 findings but 1 accepted", V + [OK0, HEAD, "1"], 1, contains=["has 0 finding(s) and 1 were accepted"])
run("verify: 2 findings, none accepted", V + [F2, HEAD], 1)
run("verify: 2 findings, 2 accepted", V + [F2, HEAD, "2"], 0)
run("verify: error event", V + [ERR, HEAD], 1, contains=["not a completed review"])
run("verify: no resolver_meta", V + [NOMETA, HEAD], 1, contains=["no resolver_meta"])
run("verify: reviewed another commit", V + [MISMATCH, HEAD], 1, contains=["Review HEAD again"])
run("verify: accepted finding fixed in a newer commit", V + [ANCESTOR, HEAD, "1"], 0, contains=["ancestor of HEAD"])
run("verify: ancestor review with its finding unaccepted", V + [ANCESTOR, HEAD, "0"], 1)
run("verify: accepted finding on a non-ancestor", V + [NOT_ANCESTOR, HEAD, "1"], 1, contains=["Review HEAD again"])
run("verify: failed status", V + [FAILED, HEAD], 1, contains=["status=review_failed"])
run("verify: complete count above streamed findings", V + [REPORTED_MORE, HEAD, "1"], 1, contains=["findings=3"])
run("verify: complete count honoured", V + [REPORTED_MORE, HEAD, "3"], 0)
run("verify: complete event without status", V + [NOSTATUS, HEAD], 0)
run("verify: findings given as an array", V + [ARRAY, HEAD, "2"], 0)
run("verify: findings array unaccepted", V + [ARRAY, HEAD], 1)
run("verify: no complete event", V + [INCOMPLETE, HEAD, "1"], 1)
run("verify: empty log", V + [EMPTY, HEAD], 1, contains=["not found or empty"])
run("verify: missing log", V + [os.path.join(FIX, "nope.jsonl"), HEAD], 1)
run("verify: accept is not a number", V + [OK0, HEAD, "x"], 1, contains=["whole number"])
run("verify: too few arguments", V + [OK0], 1, contains=["Usage"])

# review mode: preconditions
run("review: CLI not installed", [CR, "o", "r", "1"], 5, env={"CR_CLI_BIN": "/nonexistent/coderabbit"}, contains=["not installed"])
run("review: CLI signed out", [CR, "o", "r", "1"], 5, env={**FAKE, "FAKE_AUTH": "fail"}, contains=["auth login"])
run("review: PR not open", [CR, "o", "r", "1"], 1, env={**FAKE, "FAKE_PR_STATE": "MERGED"}, contains=["is MERGED"])
run("review: PR number not numeric", [CR, "o", "r", "abc"], 1, env=FAKE, contains=["Usage"])
run("review: checkout is not the PR head", [CR, "o", "r", "1"], 1, env={**FAKE, "FAKE_HEAD": OTHER}, contains=["is not the PR head"])
run("review: no arguments", [CR], 1)

# review mode: outcomes
run("review: 0 findings", [CR, "o", "r", "1"], 0, env={**FAKE, "FAKE_MODE": "zero"}, contains=["0 finding(s)", "Gate: CR_CLI_LOG="])
log = newest_log()
with open(log) as f:
    first = json.loads(f.readline())
with open(log + ".stderr") as f:
    stderr = f.read()
check("review: log starts with resolver_meta for HEAD",
      first["type"] == "resolver_meta" and first["head"] == HEAD and first["pr"] == 1 and first["base"] == "main", first)
check("review: CLI ran with --agent --committed --base-commit <merge base>",
      f"review --agent --committed --base-commit {HEAD}" in stderr, stderr)
run("verify: the 0-finding log it wrote", V + [log, HEAD], 0)
run("review: 2 findings", [CR, "o", "r", "1"], 4, env={**FAKE, "FAKE_MODE": "findings"},
    contains=["#1 [major] src/a.ts: Guard against null.", "#2 [minor] src/b.ts: Rename x to count", "CR_CLI_ACCEPT=<n>"])
run("verify: the 2-finding log with both accepted", V + [newest_log(), HEAD, "2"], 0)
run("review: CLI rate limited (error event)", [CR, "o", "r", "1"], 6, env={**FAKE, "FAKE_MODE": "ratelimit"},
    contains=["Rate limit exceeded", "rate limited as well"])
run("review: scope too large", [CR, "o", "r", "1"], 7, env={**FAKE, "FAKE_MODE": "scope"}, contains=["Review scope too large", "candidate:"])
run("review: CLI rate limited (stderr only)", [CR, "o", "r", "1"], 6, env={**FAKE, "FAKE_MODE": "stderr-ratelimit"})
run("review: signed out mid-run (stderr only)", [CR, "o", "r", "1"], 5, env={**FAKE, "FAKE_MODE": "stderr-auth"})
run("review: CLI crash", [CR, "o", "r", "1"], 7, env={**FAKE, "FAKE_MODE": "crash"}, contains=["without a complete event", "boom"])
run("review: failed status", [CR, "o", "r", "1"], 7, env={**FAKE, "FAKE_MODE": "failed"}, contains=["not a completed review"])

# check-ci-status.sh: the CR_CLI_LOG branch
C = [os.path.join(S, "check-ci-status.sh"), "o", "r", "1", "20"]
C_SHORT = [os.path.join(S, "check-ci-status.sh"), "o", "r", "1", "2"]
WALKTHROUGH = "<!-- walkthrough_start -->\n## Walkthrough\nok"
run("gate: rate limited, no CLI log", C, 3, contains=["review HEAD with cli-review.sh", "Fall back to wait-for-ratelimit.sh"])
run("gate: rate limited, clean CLI log on HEAD", C, 0, env={"CR_CLI_LOG": OK0}, contains=["Accepted: the CLI review replaces", "All checks passed."])
run("gate: rate limited, CLI findings not accepted", C, 3, env={"CR_CLI_LOG": F2}, contains=["Not merge-ready"])
run("gate: rate limited, CLI findings accepted", C, 0, env={"CR_CLI_LOG": F2, "CR_CLI_ACCEPT": "2"})
run("gate: rate limited, CLI log for another commit", C, 3, env={"CR_CLI_LOG": MISMATCH})
run("gate: real review on HEAD ignores the CLI log", C, 0,
    env={"FAKE_CR_DESC": "Review completed", "FAKE_COMMENT": WALKTHROUGH, "CR_CLI_LOG": MISMATCH},
    contains=["real review ran", "left 1 review(s)", "All checks passed."])
run("gate: rate-limit notice comment, no CLI log", C, 3, env={"FAKE_CR_DESC": "Review completed"}, contains=["rate-limit notice"])
run("gate: rate-limit notice comment, clean CLI log", C, 0, env={"FAKE_CR_DESC": "Review completed", "CR_CLI_LOG": OK0})
run("gate: CLI log accepted but CI failed", C, 1, env={"CR_CLI_LOG": OK0, "FAKE_BUILD": "fail|FAILURE"},
    contains=["- build: fail (FAILURE)"])
run("gate: review in progress is not replaced", C, 3, env={"FAKE_CR_DESC": "Review in progress", "CR_CLI_LOG": OK0}, contains=["review not finished"])

# check-ci-status.sh: a "Review completed" status is not proof that HEAD was reviewed. A run can end
# in that status without leaving a review (switch-time 7886215 and 77b5483).
REVIEWED = {"FAKE_CR_DESC": "Review completed", "FAKE_COMMENT": WALKTHROUGH}
run("gate: completed status without a review on HEAD asks for a CLI review", C, 3, env={**REVIEWED, "FAKE_REVIEW_IDS": ""},
    contains=["No CodeRabbit review object", "review HEAD with cli-review.sh"], absent=["Fall back to wait-for-ratelimit.sh"])
run("gate: completed status without a review on HEAD, clean CLI log", C, 0, env={**REVIEWED, "FAKE_REVIEW_IDS": "", "CR_CLI_LOG": OK0},
    contains=["Accepted: the CLI review replaces", "All checks passed."])
run("gate: completed status without a review on HEAD, CLI log for another commit", C, 3,
    env={**REVIEWED, "FAKE_REVIEW_IDS": "", "CR_CLI_LOG": MISMATCH}, contains=["Not merge-ready"])
PAUSED = {"FAKE_CR_DESC": "Reviews paused — CodeRabbit will not run on this PR", "FAKE_COMMENT": WALKTHROUGH}
run("gate: push made while reviews were paused asks for a CLI review", C, 3, env={**PAUSED, "FAKE_REVIEW_IDS": ""},
    contains=["it did not run on this push", "No CodeRabbit review object"])
run("gate: review made on HEAD before the pause still counts", C, 0, env=PAUSED,
    contains=["it did not run on this push", "left 1 review(s)", "All checks passed."])
run("gate: base branch with reviews disabled asks for a CLI review", C, 3,
    env={"FAKE_CR_DESC": "Review skipped: reviews are disabled for this base branch", "FAKE_COMMENT": WALKTHROUGH, "FAKE_REVIEW_IDS": ""},
    contains=["it did not run on this push", "review HEAD with cli-review.sh"])

# check-ci-status.sh: a CLI review of an ancestor needs the PR head in the checkout. A second
# checkout lacks the newer head until the gate fetches pull/1/head from origin.
CLONE = os.path.join(WORK, "clone")
subprocess.run(["git", "clone", "-q", "--no-local", REPO, CLONE], check=True, capture_output=True)
NEWHEAD = git("commit-tree", "HEAD^{tree}", "-p", "HEAD", "-m", "fix accepted finding")
git("update-ref", "refs/pull/1/head", NEWHEAD)
BELOW_NEWHEAD = fixture("below-newhead-f1.jsonl", [meta(HEAD), finding(1), done(1)])
run("gate: accepted CLI review on an ancestor fetches the PR head first", C, 0,
    env={"FAKE_HEAD": NEWHEAD, "CR_CLI_LOG": BELOW_NEWHEAD, "CR_CLI_ACCEPT": "1"}, cwd=CLONE,
    contains=["ancestor of HEAD", "All checks passed."], absent=["is not in this checkout"])
run("gate: outside the PR checkout the ancestor review is refused", C, 3,
    env={"FAKE_HEAD": NEWHEAD, "CR_CLI_LOG": BELOW_NEWHEAD, "CR_CLI_ACCEPT": "1"}, cwd=FIX,
    contains=["is not in this checkout", "Not merge-ready"])

# check-ci-status.sh: which checks let a PR merge. The repo may enforce no checks at all, so the
# gate itself must stop a PR whose CI did not finish green, not only one that reported a failure.
run("gate: cancelled check blocks the merge", C, 1, env={**REVIEWED, "FAKE_BUILD": "cancel|CANCELLED"},
    contains=["1 check(s) did not pass", "- build: cancel (CANCELLED)"])
run("gate: timed-out check blocks the merge", C, 1, env={**REVIEWED, "FAKE_BUILD": "fail|TIMED_OUT"},
    contains=["- build: fail (TIMED_OUT)"])
run("gate: check waiting for approval blocks the merge", C, 1, env={**REVIEWED, "FAKE_BUILD": "fail|ACTION_REQUIRED"},
    contains=["- build: fail (ACTION_REQUIRED)"])
run("gate: cancelled check blocks after an accepted CLI review", C, 1, env={"CR_CLI_LOG": OK0, "FAKE_BUILD": "cancel|CANCELLED"},
    contains=["- build: cancel (CANCELLED)"])
run("gate: failed CI is reported before the rate-limited review", C, 1, env={"FAKE_BUILD": "fail|FAILURE"},
    contains=["- build: fail (FAILURE)"], absent=["review HEAD with cli-review.sh"])
run("gate: skipped check lets the PR merge", C, 0, env={**REVIEWED, "FAKE_BUILD": "skipping|SKIPPED"}, contains=["All checks passed."])
run("gate: neutral check lets the PR merge", C, 0, env={**REVIEWED, "FAKE_BUILD": "skipping|NEUTRAL"}, contains=["All checks passed."])
run("gate: several green and skipped checks let the PR merge", C, 0,
    env={**REVIEWED, "FAKE_CHECKS": "build|pass|SUCCESS\ne2e|skipping|SKIPPED\nlint|pass|SUCCESS\nCodeRabbit|pass|SUCCESS"},
    contains=["All 4 checks finished:", "All checks passed."])
run("gate: only the checks that did not pass are listed", C, 1,
    env={**REVIEWED, "FAKE_CHECKS": "build|pass|SUCCESS\ne2e|fail|TIMED_OUT\nlint|fail|FAILURE\nCodeRabbit|pass|SUCCESS"},
    contains=["2 check(s) did not pass", "- e2e: fail (TIMED_OUT)", "- lint: fail (FAILURE)"], absent=["- build:"])
run("gate: failed CodeRabbit check blocks the merge", C, 1,
    env={**REVIEWED, "FAKE_CHECKS": "build|pass|SUCCESS\nCodeRabbit|fail|FAILURE"}, contains=["CodeRabbit check failed."])

# check-ci-status.sh: when the gate keeps waiting
run("gate: pending check times out instead of passing", C_SHORT, 2,
    env={**REVIEWED, "FAKE_CHECKS": "build|pending|IN_PROGRESS\nCodeRabbit|pass|SUCCESS"},
    contains=["1/2 finished", "Timeout after 2s"], absent=["All checks passed."])
run("gate: CodeRabbit alone is not a green CI", C_SHORT, 2, env={**REVIEWED, "FAKE_CHECKS": "CodeRabbit|pass|SUCCESS"},
    contains=["No CI checks besides CodeRabbit", "Timeout after 2s"])
run("gate: missing CodeRabbit check keeps the gate waiting", C_SHORT, 2, env={**REVIEWED, "FAKE_CHECKS": "build|pass|SUCCESS"},
    contains=["CodeRabbit not found on HEAD yet", "Timeout after 2s"])
run("gate: checks read while HEAD moved are read again", C, 0, env={**REVIEWED, "FAKE_HEAD_FIRST": OTHER},
    contains=["HEAD moved", "Checks on " + HEAD[:7], "All checks passed."], absent=["Checks on " + OTHER[:7]])

# check-ci-status.sh: `cli` mode (`CR_CLI_MODE=1`) and a CLI log without a bot check
run("gate: CLI mode, no log, asks for a CLI review", C, 3, env={"CR_CLI_MODE": "1"},
    contains=["CLI mode", "cli-review.sh"], absent=["CodeRabbit not found on HEAD yet", "Fall back to wait-for-ratelimit.sh", "All checks passed."])
run("gate: CLI mode, no CodeRabbit check, no log", C, 3,
    env={"CR_CLI_MODE": "1", "FAKE_CHECKS": "build|pass|SUCCESS"},
    contains=["CLI mode", "cli-review.sh"], absent=["CodeRabbit not found on HEAD yet", "Timeout"])
run("gate: CLI mode, no CodeRabbit check, clean CLI log", C, 0,
    env={"CR_CLI_MODE": "1", "CR_CLI_LOG": OK0, "FAKE_CHECKS": "build|pass|SUCCESS"},
    contains=["CLI mode", "Accepted: the CLI review covers", "All checks passed."], absent=["CodeRabbit not found"])
run("gate: CLI mode leftover bot review still requires a CLI log", C, 3, env={**REVIEWED, "CR_CLI_MODE": "1"},
    contains=["CLI mode", "cli-review.sh"], absent=["All checks passed.", "left 1 review(s)"])
run("gate: CLI mode leftover bot review, clean CLI log", C, 0,
    env={**REVIEWED, "CR_CLI_MODE": "1", "CR_CLI_LOG": OK0},
    contains=["Accepted: the CLI review covers", "All checks passed."], absent=["left 1 review(s)"])
run("gate: CLI mode failed CI still blocks", C, 1,
    env={"CR_CLI_MODE": "1", "FAKE_CHECKS": "build|fail|FAILURE"},
    contains=["- build: fail (FAILURE)"], absent=["CLI mode: a CodeRabbit CLI review"])
run("gate: CLI mode pending CI still waits", C_SHORT, 2,
    env={"CR_CLI_MODE": "1", "FAKE_CHECKS": "build|pending|IN_PROGRESS"},
    contains=["Timeout after 2s"], absent=["All checks passed."])
run("gate: CLI log without a CodeRabbit check does not wait", C, 0,
    env={"CR_CLI_LOG": OK0, "FAKE_CHECKS": "build|pass|SUCCESS"},
    contains=["Accepted: the CLI review replaces", "All checks passed."], absent=["CodeRabbit not found"])

# ensure-cli-ignore.sh: write `@coderabbitai ignore` into the PR description
EI = [os.path.join(S, "ensure-cli-ignore.sh"), "o", "r", "1"]
run("ignore: adds marker to an empty body", EI, 0, env={"FAKE_BODY": ""}, contains=["Added @coderabbitai ignore"])
run("ignore: appends marker to an existing body", EI, 0, env={"FAKE_BODY": "## Summary\nDone."}, contains=["Added @coderabbitai ignore"])
run("ignore: leaves a body that already has the marker", EI, 0,
    env={"FAKE_BODY": "## Summary\n\n@coderabbitai ignore\n"},
    contains=["already has @coderabbitai ignore"], absent=["Added @coderabbitai ignore"])
run("ignore: PR number not numeric", EI[:-1] + ["abc"], 1, contains=["Usage"])

print()
print(f"{sum(results)}/{len(results)} passed")
if all(results):
    shutil.rmtree(WORK)
else:
    print("kept for debugging:", WORK)
raise SystemExit(0 if all(results) else 1)

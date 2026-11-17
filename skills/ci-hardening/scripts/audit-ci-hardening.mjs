#!/usr/bin/env node
import fs from "node:fs";
import path from "node:path";

const root = process.cwd();
const shaRef = /@[0-9a-fA-F]{40}(?:\s|$|#)/;
const useLine = /^\s*-?\s*uses:\s*([^\s#]+)/;

function walk(dir) {
  if (!fs.existsSync(dir)) return [];
  const entries = fs.readdirSync(dir, { withFileTypes: true });
  return entries.flatMap((entry) => {
    const full = path.join(dir, entry.name);
    if (entry.isDirectory()) return walk(full);
    return [full];
  });
}

function read(file) {
  return fs.readFileSync(file, "utf8");
}

const workflowDir = path.join(root, ".github", "workflows");
const actionDir = path.join(root, ".github", "actions");
const workflowFiles = walk(workflowDir).filter((file) => /\.ya?ml$/.test(file));
const actionFiles = walk(actionDir).filter((file) => /action\.ya?ml$/.test(file));
const allFiles = [...workflowFiles, ...actionFiles];

const findings = [];
let usesTotal = 0;
let pinned = 0;
let unpinned = 0;
let localUses = 0;
let checkouts = 0;
let checkoutsNoPersist = 0;
let workflowsWithPermissions = 0;

for (const file of workflowFiles) {
  const text = read(file);
  if (/^permissions:\s*$/m.test(text)) workflowsWithPermissions += 1;
  if (/pull_request_target/.test(text)) {
    findings.push(["HIGH", file, "pull_request_target present; review with gha-security-review before trusting."]);
  }
  if (/permissions:\s*write-all/.test(text)) {
    findings.push(["HIGH", file, "permissions: write-all grants broad token access."]);
  }
  if (/issue_comment/.test(text)) {
    findings.push(["MEDIUM", file, "issue_comment trigger present; verify author association and command gating."]);
  }
  if (/workflow_run/.test(text) && /download-artifact/.test(text)) {
    findings.push(["MEDIUM", file, "workflow_run downloads artifacts; verify artifact trust boundary."]);
  }
}

for (const file of allFiles) {
  const lines = read(file).split(/\r?\n/);
  lines.forEach((line, index) => {
    const match = line.match(useLine);
    if (!match) return;
    const ref = match[1].replace(/^["']|["']$/g, "");
    usesTotal += 1;
    if (ref.startsWith("./")) {
      localUses += 1;
    } else if (shaRef.test(ref)) {
      pinned += 1;
    } else {
      unpinned += 1;
      findings.push(["MEDIUM", file, `Unpinned action at line ${index + 1}: ${ref}`]);
    }
    if (ref.startsWith("actions/checkout@")) {
      checkouts += 1;
      const block = lines.slice(index, index + 7).join("\n");
      if (/persist-credentials:\s*false/.test(block)) checkoutsNoPersist += 1;
      else findings.push(["LOW", file, `Checkout at line ${index + 1} does not set persist-credentials: false.`]);
    }
  });
}

const support = {
  dependabot: fs.existsSync(path.join(root, ".github", "dependabot.yml")) || fs.existsSync(path.join(root, ".github", "dependabot.yaml")),
  codeowners: fs.existsSync(path.join(root, ".github", "CODEOWNERS")),
  securityPolicy: fs.existsSync(path.join(root, "SECURITY.md")),
  prTemplate: fs.existsSync(path.join(root, ".github", "pull_request_template.md")) || fs.existsSync(path.join(root, ".github", "PULL_REQUEST_TEMPLATE.md")),
};

console.log("CI hardening audit");
console.log(`repo: ${root}`);
console.log(`workflows with permissions: ${workflowsWithPermissions}/${workflowFiles.length}`);
console.log(`actions pinned/unpinned/local: ${pinned}/${unpinned}/${localUses}`);
console.log(`checkout persist-credentials false: ${checkoutsNoPersist}/${checkouts}`);
console.log(`support files: ${Object.entries(support).filter(([, ok]) => ok).map(([key]) => key).join(", ") || "none"}`);

if (findings.length) {
  console.log("\nFindings:");
  for (const [severity, file, message] of findings) {
    console.log(`- [${severity}] ${path.relative(root, file)}: ${message}`);
  }
  process.exitCode = findings.some(([severity]) => severity === "HIGH" || severity === "MEDIUM") ? 1 : 0;
} else {
  console.log("\nNo high/medium CI hardening gaps found by this static audit.");
}

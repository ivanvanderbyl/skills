#!/usr/bin/env python3
"""Keep a Reflex project's state in the project so every run resumes recorded work.

Run `next` first in every session. It reports the phase, an open or interrupted run,
every required check that failed, went stale or never ran, and one next step.

Exit codes: 0 done; 1 invalid input or unreadable state; 2 refused until the step
named in the message is taken. Results are JSON on stdout; errors go to stderr.
"""

import argparse
from datetime import datetime, timezone
from fnmatch import fnmatchcase
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import sys


VERSION = 2
PATH_KEYS = {"status", "decisions", "runs", "evidence", "ledger", "product"}
KINDS = ("unit", "integration", "binding", "store", "journey", "visual", "motion")
RESULTS = ("passed", "failed", "blocked")
OUTCOMES = ("complete", "partial", "blocked", "no-change")
AUTHORITIES = ("user", "source", "vendor", "experiment", "assumption")
GEN_START = "<!-- reflex:generated:start -->"
GEN_END = "<!-- reflex:generated:end -->"
INCOMPLETE = "<!-- reflex:incomplete"
ATTENTION_LIMIT = 25
PLACEHOLDERS = {
    "Did": "No work recorded yet.",
    "Not done": "Not recorded yet.",
    "Next action": "Not recorded yet.",
}


class Refused(Exception):
    """The request is valid but the recorded state requires another step first."""


def now():
    return datetime.now(timezone.utc)


def git(repo, *args):
    result = subprocess.run(["git", "-C", str(repo)] + list(args), stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    return result.stdout if result.returncode == 0 else None


def local_path(repo, name):
    if not isinstance(name, str) or not name:
        raise ValueError("State paths must be nonempty repository-relative strings")
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("Paths must stay inside the selected repository: " + name)
    path = (repo / relative).resolve()
    try:
        path.relative_to(repo)
    except ValueError:
        raise ValueError("Paths must stay inside the selected repository: " + name)
    return path


def write_atomic(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(content, encoding="utf-8")
    os.replace(temporary, path)


def create_text(path, content):
    path.parent.mkdir(parents=True, exist_ok=True)
    try:
        with path.open("x", encoding="utf-8") as stream:
            stream.write(content)
        return True
    except FileExistsError:
        if not path.is_file():
            raise ValueError("Expected a file at " + str(path))
        return False


# Manifest and ledger


def read_manifest(state_dir):
    manifest = state_dir / "manifest.json"
    if not manifest.is_file():
        return None
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or type(data.get("schema_version")) is not int:
        raise ValueError("State manifest is not a versioned object; preserve it and inspect it by hand")
    return data


def load_state(repo, state_dir):
    data = read_manifest(state_dir)
    if data is None:
        raise Refused("State is not initialized. Inspect existing project records, then run: init --repo " + str(repo))
    if data["schema_version"] == 1:
        raise Refused("State uses schema 1. Run `migrate` first; it adds the ledger and product context and keeps every record.")
    if data["schema_version"] != VERSION:
        raise ValueError("Unsupported state schema %s; this helper writes schema %s" % (data["schema_version"], VERSION))
    paths = data.get("paths")
    if not isinstance(paths, dict) or set(paths) != PATH_KEYS or not isinstance(data.get("targets"), dict):
        raise ValueError("Incomplete or unknown state layout; inspect the manifest before changing it")
    resolved = resolve_paths(repo, paths)
    ledger = json.loads(resolved["ledger"].read_text(encoding="utf-8")) if resolved["ledger"].is_file() else {"schema_version": VERSION, "items": []}
    return data, resolved, ledger


def resolve_paths(repo, names):
    paths = {key: local_path(repo, value) for key, value in names.items()}
    values = list(paths.values())
    for index, path in enumerate(values):
        for other in values[index + 1:]:
            if path == other or (path in other.parents and path.suffix) or (other in path.parents and other.suffix):
                raise ValueError("State document paths must not overlap")
    return paths


def save_ledger(paths, ledger):
    write_atomic(paths["ledger"], json.dumps(ledger, indent=2, ensure_ascii=False) + "\n")


def default_paths(prefix, status_doc=None, decisions_doc=None):
    return {
        "status": status_doc or prefix + "/status.md",
        "decisions": decisions_doc or prefix + "/decisions.md",
        "runs": prefix + "/runs",
        "evidence": prefix + "/evidence",
        "ledger": prefix + "/ledger.json",
        "product": prefix + "/product.md",
    }


STATUS_TEMPLATE = (
    "# Reflex project status\n\n"
    "Read the product context first. The block below is generated from the ledger and run records; "
    "change it through reflex_state.py. Text outside the block is preserved.\n\n"
    + GEN_START + "\n" + GEN_END + "\n\n"
    "## Notes\n\nBlockers, context and limits that the ledger cannot express.\n"
)
DECISIONS_TEMPLATE = (
    "# Reflex decisions\n\n"
    "Append-only. Add entries with `reflex_state.py decide`; correct an entry by superseding it.\n"
)
PRODUCT_TEMPLATE = (
    "# Product context\n\n"
    + INCOMPLETE + ": replace each prompt with the project's facts, then delete this line -->\n\n"
    "## Product\n\nWhat the app is for and who uses it, in two or three sentences.\n\n"
    "## Targets\n\nEach surface, whether it is required or optional, and its minimum OS or browser.\n\n"
    "## Vocabulary and copy\n\nThe product's names for its things and actions. Where user-visible strings are defined and how each target reads them.\n\n"
    "## Shared identifiers and design tokens\n\nWhere accessibility identifiers, colours, type and spacing are defined, and how each target consumes them.\n\n"
    "## Accepted differences\n\nDifferences between targets that the user accepted, each with its decision ID.\n"
)


def create_records(repo, state_dir, data):
    paths = resolve_paths(repo, data["paths"])
    created = []
    state_dir.mkdir(parents=True, exist_ok=True)
    for key, content in [
        ("status", STATUS_TEMPLATE),
        ("decisions", DECISIONS_TEMPLATE),
        ("product", PRODUCT_TEMPLATE),
        ("ledger", json.dumps({"schema_version": VERSION, "items": []}, indent=2) + "\n"),
    ]:
        if create_text(paths[key], content):
            created.append(paths[key].relative_to(repo).as_posix())
    for key in ("runs", "evidence"):
        if paths[key].exists() and not paths[key].is_dir():
            raise ValueError("Expected a directory at " + str(paths[key]))
        paths[key].mkdir(parents=True, exist_ok=True)
    return paths, created


def command_init(repo, state_dir, args):
    existing = read_manifest(state_dir)
    prefix = state_dir.relative_to(repo).as_posix()
    if existing and existing["schema_version"] == 1:
        raise Refused("State uses schema 1. Run `migrate`; it keeps every existing record.")
    if existing:
        data = load_state(repo, state_dir)[0]
        for key, override in [("status", args.status_doc), ("decisions", args.decisions_doc)]:
            if override and override != data["paths"][key]:
                raise ValueError("The manifest already owns " + key + "; reconcile its mapping deliberately")
    else:
        data = {"schema_version": VERSION, "paths": default_paths(prefix, args.status_doc, args.decisions_doc), "targets": {}}
    paths, created = create_records(repo, state_dir, data)
    if create_text(state_dir / "manifest.json", json.dumps(data, indent=2) + "\n"):
        created.append((state_dir / "manifest.json").relative_to(repo).as_posix())
    render_status(repo, state_dir, data, paths, load_state(repo, state_dir)[2])
    return {"created": created, "preserved_existing_files": True, "next": "Declare each target with `target`, then run `next`."}


def command_migrate(repo, state_dir, args):
    existing = read_manifest(state_dir)
    if existing is None:
        raise Refused("Nothing to migrate. Run `init`.")
    if existing["schema_version"] == VERSION:
        return {"migrated": False, "reason": "State already uses schema %s." % VERSION}
    if existing["schema_version"] != 1 or set(existing.get("paths", {})) != {"status", "decisions", "runs", "evidence"}:
        raise ValueError("Only an intact schema 1 manifest can be migrated; inspect this one by hand")
    prefix = state_dir.relative_to(repo).as_posix()
    data = {"schema_version": VERSION, "paths": dict(default_paths(prefix), **existing["paths"]), "targets": {}}
    paths, created = create_records(repo, state_dir, data)
    write_atomic(state_dir / "manifest.json", json.dumps(data, indent=2) + "\n")
    render_status(repo, state_dir, data, paths, {"schema_version": VERSION, "items": []})
    return {
        "migrated": True,
        "created": created,
        "kept": "Status notes, decisions, run records and evidence are unchanged.",
        "next": "Declare targets with `target`, then re-enter each tracked work item from the old status table with `item`. Earlier results stay in their run records; record a receipt only after rerunning the check.",
    }


# Source tree, digests and check states


class Tree:
    """The project's files outside the state directory, hashed on demand."""

    def __init__(self, repo, state_dir):
        self.repo = repo
        prefix = state_dir.relative_to(repo).as_posix() + "/"
        listed = git(repo, "ls-files", "-co", "--exclude-standard", "-z")
        if listed is not None:
            names = [name for name in listed.decode("utf-8", "surrogateescape").split("\0") if name]
        else:
            names = [path.relative_to(repo).as_posix() for path in repo.rglob("*") if path.is_file() and ".git" not in path.parts]
        self.files = sorted(set(name for name in names if not name.startswith(prefix)))
        self.hashes = {}

    def match(self, patterns):
        return [name for name in self.files if any(fnmatchcase(name, pattern) for pattern in patterns)]

    def file_hash(self, name):
        if name not in self.hashes:
            path = self.repo / name
            self.hashes[name] = hashlib.sha256(path.read_bytes()).hexdigest() if path.is_file() else "missing"
        return self.hashes[name]

    def digest(self, patterns, extra):
        names = self.match(patterns)
        summary = hashlib.sha256()
        for name in names:
            summary.update((name + "\0" + self.file_hash(name) + "\n").encode("utf-8", "surrogateescape"))
        summary.update(json.dumps(extra, sort_keys=True).encode("utf-8"))
        return summary.hexdigest(), len(names)

    def mentions(self, patterns, needle):
        encoded = needle.encode("utf-8")
        for name in self.match(patterns):
            path = self.repo / name
            if path.is_file() and path.stat().st_size <= 1_000_000 and encoded in path.read_bytes():
                return True
        return False


def normalize_patterns(values):
    patterns = []
    for value in values:
        if not value or value.startswith("/") or ".." in Path(value).parts:
            raise ValueError("Input patterns are repository-relative globs such as platforms/apple/**: " + repr(value))
        patterns.append(value + "*" if value.endswith("/") else value)
    return patterns


def parse_check(manifest, key):
    target, _, kind = key.partition(":")
    if target not in manifest["targets"]:
        raise Refused("Unknown target %r. Declared targets: %s. Declare it with `target --name %s --inputs <glob>`." % (target, ", ".join(manifest["targets"]) or "none", target))
    if kind not in KINDS:
        raise ValueError("Check is <target>:<kind>, with kind one of: " + ", ".join(KINDS))
    return target, kind


def check_patterns(manifest, item, target):
    targets = manifest["targets"]
    patterns = list(targets[target]["inputs"])
    if target != "core" and "core" in targets:
        patterns += targets["core"]["inputs"]
    return patterns + item.get("inputs", [])


def check_digest(tree, manifest, item, target):
    return tree.digest(check_patterns(manifest, item, target), {"acceptance": item["acceptance"], "ui_ids": item.get("ui_ids", [])})


def required_checks(manifest, item):
    targets = manifest["targets"]
    keys = (["core:unit"] if "core" in targets else []) + [name + ":journey" for name in targets if name != "core"]
    for key in item.get("require", []):
        if key not in keys and key.partition(":")[0] in targets:
            keys.append(key)
    return [key for key in keys if key not in item.get("waived", {})]


def latest_receipt(item, key):
    for receipt in reversed(item.get("receipts", [])):
        if receipt["check"] == key:
            return receipt
    return None


def check_state(repo, tree, manifest, item, key):
    receipt = latest_receipt(item, key)
    if receipt is None:
        return {"state": "not-run"}
    detail = {"run": receipt["run_id"], "at": receipt["at"]}
    if receipt["result"] != "passed":
        return dict(detail, state=receipt["result"], why=receipt.get("note") or receipt.get("command"))
    if check_digest(tree, manifest, item, key.partition(":")[0])[0] != receipt["input_digest"]:
        return dict(detail, state="stale", why="Inputs or acceptance changed since the pass recorded at " + str(receipt.get("head"))[:12])
    evidence = receipt.get("evidence")
    if evidence and not evidence.startswith(("http://", "https://")):
        path = repo / evidence
        if not path.is_file():
            return dict(detail, state="stale", why="Evidence file is missing: " + evidence)
        if hashlib.sha256(path.read_bytes()).hexdigest() != receipt.get("evidence_sha256"):
            return dict(detail, state="stale", why="Evidence file changed after it was recorded: " + evidence)
    return dict(detail, state="passed")


def ever_proven(manifest, item):
    required = required_checks(manifest, item)
    passed = {receipt["check"] for receipt in item.get("receipts", []) if receipt["result"] == "passed"}
    return bool(required) and all(key in passed for key in required)


def live_items(ledger):
    return [item for item in ledger["items"] if item["state"] != "dropped"]


# Decisions and run records


def read_decisions(paths):
    text = paths["decisions"].read_text(encoding="utf-8") if paths["decisions"].is_file() else ""
    decisions = []
    for block in re.split(r"(?m)^(?=## D-\d+ )", text):
        heading = re.match(r"## (D-\d+) · (.*)", block)
        if not heading:
            continue
        fields = dict(re.findall(r"(?m)^- (Authority|Supersedes|Confirms): (.*)$", block))
        decisions.append({"id": heading.group(1), "title": heading.group(2).strip(), "fields": fields})
    by_id = {decision["id"]: decision for decision in decisions}
    for decision in decisions:
        decision["status"] = "assumed" if decision["fields"].get("Authority", "").startswith("assumption") else "accepted"
    for decision in decisions:
        confirmed, superseded = decision["fields"].get("Confirms"), decision["fields"].get("Supersedes")
        if confirmed in by_id and decision["status"] == "accepted":
            by_id[confirmed]["status"] = "accepted"
        if superseded in by_id:
            by_id[superseded]["status"] = "superseded"
    return decisions


def accepted_decision(paths, decision_id, purpose):
    for decision in read_decisions(paths):
        if decision["id"] == decision_id:
            if decision["status"] != "accepted":
                raise Refused("%s is %s. %s needs a decision the user or a cited source settled. Confirm it with `decide --confirms %s --authority user --authority-ref \"<the user's words>\"`." % (decision_id, decision["status"], purpose, decision_id))
            return decision
    raise Refused("%s is not in the decisions record. Record it with `decide` first." % decision_id)


def section(text, heading):
    match = re.search(r"(?ms)^## " + re.escape(heading) + r"\n(.*?)(?=^## |\Z)", text)
    return match.group(1).strip() if match else ""


def read_runs(repo, paths):
    runs = []
    for path in sorted(paths["runs"].glob("*.md")) if paths["runs"].is_dir() else []:
        text = path.read_text(encoding="utf-8")
        status = re.search(r"(?m)^Run status: (\S+)", text)
        runs.append({
            "id": path.stem,
            "record": path.relative_to(repo).as_posix(),
            "status": status.group(1) if status else "unknown",
            "next_action": section(text, "Next action"),
            "not_done": section(text, "Not done"),
        })
    return runs


def open_run(repo, paths, run_id=None):
    runs = [run for run in read_runs(repo, paths) if run["status"] == "in_progress"]
    if run_id:
        runs = [run for run in runs if run["id"] == run_id]
    if len(runs) != 1:
        raise Refused(("No open run." if not runs else "Several runs are open; pass --run.") + " Open one with `start`, or see `next`.")
    return runs[0]


def source_context(repo, state_dir):
    excluded = ":(exclude)" + state_dir.relative_to(repo).as_posix()
    head = git(repo, "rev-parse", "HEAD")
    branch = git(repo, "symbolic-ref", "--short", "HEAD")
    dirty = git(repo, "status", "--porcelain", "--untracked-files=normal", "--", ".", excluded)
    return {
        "head": head.decode().strip() if head else None,
        "branch": branch.decode().strip() if branch else None,
        "dirty_paths": dirty.decode().splitlines()[:40] if dirty else [],
    }


# The computed view


def assess(repo, state_dir, manifest, paths, ledger):
    tree = Tree(repo, state_dir)
    targets = manifest["targets"]
    attention, matrix = [], []
    for item in live_items(ledger):
        row = {"id": item["id"], "title": item["title"], "state": item["state"], "checks": {}}
        for key in required_checks(manifest, item):
            state = check_state(repo, tree, manifest, item, key)
            row["checks"][key] = state["state"]
            if state["state"] != "passed" and item["state"] == "active":
                attention.append(dict(state, item=item["id"], check=key))
        for key, decision in item.get("waived", {}).items():
            row["checks"][key] = "waived (%s)" % decision
        if item["state"] == "active" and row["checks"] and all(value == "passed" or value.startswith("waived") for value in row["checks"].values()):
            row["state"] = "verified"
        if item["state"] == "active":
            for identifier in item.get("ui_ids", []):
                for name in targets:
                    if name != "core" and (name + ":journey") not in item.get("waived", {}) and not tree.mentions(check_patterns(manifest, item, name), identifier):
                        attention.append({"state": "identifier-missing", "item": item["id"], "check": name + ":journey", "why": "Shared identifier %r appears in neither the %s sources nor the core sources" % (identifier, name)})
        matrix.append(row)
    order = {"failed": 0, "blocked": 1, "identifier-missing": 2, "stale": 3, "not-run": 4}
    attention.sort(key=lambda entry: (order[entry["state"]], entry["item"], entry["check"]))
    runs = read_runs(repo, paths)
    closed = [run for run in runs if run["status"] in OUTCOMES]
    opened = [run for run in runs if run["status"] == "in_progress"]
    interrupted = [run["id"] for run in runs if run["status"] == "interrupted" and (not closed or run["id"] > closed[-1]["id"])]
    assumed = [decision for decision in read_decisions(paths) if decision["status"] == "assumed"]
    product = paths["product"].read_text(encoding="utf-8") if paths["product"].is_file() else INCOMPLETE
    script = "python3 " + str(Path(__file__).resolve()) + " %s --repo " + str(repo)
    items = live_items(ledger)
    planned = [item for item in items if item["state"] == "planned"]
    if not [name for name in targets if name != "core"]:
        phase, reason = "setup", "No app target is declared."
        step = "Declare the core and each app target with its source globs: " + script % "target" + " --name ios --inputs 'platforms/apple/**'"
    elif not items:
        phase, reason = "inventory", "The ledger has no work items."
        step = "Record the first observable journey as an item, then activate it: " + script % "item" + " --title <title> --acceptance <observable result> --state active"
    else:
        phase = "slice" if not any(ever_proven(manifest, item) for item in items) else ("expand" if attention or planned else "maintain")
        reason = {
            "slice": "No item has passed every required check on every target yet. Prove one before starting another.",
            "expand": "A vertical slice is proven. Work through the remaining checks and planned items.",
            "maintain": "Every active item passes its required checks against the current inputs.",
        }[phase]
        if attention:
            first = attention[0]
            step = {
                "failed": "Repair the failing check before other work: ",
                "blocked": "Resolve the blocker or record why it still blocks: ",
                "identifier-missing": "Add the shared identifier to that target, or correct the item's --ui-id list: ",
                "stale": "Rerun the check against the current inputs and record a new receipt: ",
                "not-run": "Implement and run the check, then record its receipt: ",
            }[first["state"]] + "%s %s%s" % (first["item"], first["check"], (" (" + first["why"] + ")") if first.get("why") else "")
        elif planned:
            step = "Activate the next planned item: " + script % "item" + " --id " + planned[0]["id"] + " --state active"
        else:
            step = "No open work is recorded. Add the user's next request as an item before changing code."
    return {
        "schema_version": VERSION,
        "phase": phase,
        "reason": reason,
        "do": step,
        "open_runs": [{"id": run["id"], "record": run["record"]} for run in opened],
        "last_handoff": ({"run": closed[-1]["id"], "outcome": closed[-1]["status"], "record": closed[-1]["record"], "not_done": closed[-1]["not_done"], "next_action": closed[-1]["next_action"]} if closed else None),
        "interrupted_since_handoff": interrupted,
        "attention": attention[:ATTENTION_LIMIT],
        "attention_total": len(attention),
        "assumed_decisions": [decision["id"] + " · " + decision["title"] for decision in assumed],
        "product_context_incomplete": INCOMPLETE in product,
        "matrix": matrix,
        "read": [manifest["paths"]["product"], manifest["paths"]["status"]] + ([closed[-1]["record"]] if closed else []) + [manifest["paths"]["decisions"]],
        "targets": {name: target["inputs"] for name, target in targets.items()},
        "source_now": source_context(repo, state_dir),
    }


def render_status(repo, state_dir, manifest, paths, ledger):
    view = assess(repo, state_dir, manifest, paths, ledger)
    columns = []
    for row in view["matrix"]:
        columns += [key for key in row["checks"] if key not in columns]
    lines = ["Phase: %s. %s" % (view["phase"], view["reason"]), ""]
    if view["matrix"]:
        lines += ["| Item | State | " + " | ".join(columns) + " |", "| --- | --- |" + " --- |" * len(columns)]
        for row in view["matrix"]:
            lines.append("| %s %s | %s | %s |" % (row["id"], row["title"].replace("|", "/"), row["state"], " | ".join(row["checks"].get(key, "n/a") for key in columns)))
        lines.append("")
    handoff = view["last_handoff"]
    if handoff:
        lines += ["Last closed run: %s (%s). Its next action: %s" % (handoff["run"], handoff["outcome"], handoff["next_action"].replace("\n", " ")), ""]
    if view["open_runs"]:
        lines += ["Open run: " + ", ".join(run["id"] for run in view["open_runs"]), ""]
    if view["interrupted_since_handoff"]:
        lines += ["Interrupted since then, outcome unrecorded: " + ", ".join(view["interrupted_since_handoff"]), ""]
    if view["assumed_decisions"]:
        lines += ["Assumptions awaiting the user: " + "; ".join(view["assumed_decisions"]), ""]
    block = GEN_START + "\n" + "\n".join(lines).rstrip() + "\n" + GEN_END
    text = paths["status"].read_text(encoding="utf-8") if paths["status"].is_file() else STATUS_TEMPLATE
    if GEN_START in text and GEN_END in text:
        text = text[:text.index(GEN_START)] + block + text[text.index(GEN_END) + len(GEN_END):]
    else:
        text = text.rstrip("\n") + "\n\n" + block + "\n"
    if not paths["status"].is_file() or paths["status"].read_text(encoding="utf-8") != text:
        write_atomic(paths["status"], text)
    return view


# Commands that change state


def command_target(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    if not re.fullmatch(r"[a-z][a-z0-9-]*", args.name):
        raise ValueError("Target names are lowercase, such as core, ios, android or web")
    patterns = normalize_patterns(args.inputs)
    matched = len(Tree(repo, state_dir).match(patterns))
    existed = args.name in manifest["targets"]
    manifest["targets"][args.name] = {"inputs": patterns}
    write_atomic(state_dir / "manifest.json", json.dumps(manifest, indent=2) + "\n")
    render_status(repo, state_dir, manifest, paths, ledger)
    return {
        "target": args.name,
        "inputs": patterns,
        "files_matched_now": matched,
        "effect": ("Changed inputs make this target's earlier passes stale." if existed else "Every live item now requires %s." % (args.name + (":unit" if args.name == "core" else ":journey"))),
    }


def command_item(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    if args.id:
        matches = [item for item in ledger["items"] if item["id"] == args.id]
        if not matches:
            raise ValueError("No item " + args.id)
        item = matches[0]
    else:
        if not args.title or not args.acceptance:
            raise ValueError("A new item needs --title and --acceptance (the observable result that proves it)")
        item = {"id": "F-%03d" % (len(ledger["items"]) + 1), "title": "", "acceptance": "", "state": "planned", "ui_ids": [], "require": [], "inputs": [], "waived": {}, "receipts": []}
        ledger["items"].append(item)
    for field, value in [("title", args.title), ("acceptance", args.acceptance)]:
        if value:
            item[field] = value.strip()
    for field, values in [("ui_ids", args.ui_id), ("inputs", normalize_patterns(args.inputs or []))]:
        item[field] += [value for value in values or [] if value not in item[field]]
    for key in args.require or []:
        parse_check(manifest, key)
        if key not in item["require"]:
            item["require"].append(key)
    if args.state and args.state != item["state"]:
        if args.state == "dropped":
            if not args.decision:
                raise Refused("Dropping an item changes product scope. Pass --decision with an accepted decision ID.")
            accepted_decision(paths, args.decision, "Dropping an item")
            item["dropped_by"] = args.decision
        if args.state == "active":
            others = [other for other in live_items(ledger) if other["state"] == "active" and other is not item]
            if others and not any(ever_proven(manifest, other) for other in ledger["items"]):
                if not args.bypass_reason:
                    raise Refused("%s is active and no item has passed every required check on every target. Prove that slice first, or pass --bypass-reason to record why a second item must start now." % others[0]["id"])
                item.setdefault("bypasses", []).append({"rule": "one active item until a slice is proven", "reason": args.bypass_reason, "at": now().isoformat()})
        item["state"] = args.state
    save_ledger(paths, ledger)
    render_status(repo, state_dir, manifest, paths, ledger)
    return {"item": {key: item[key] for key in ("id", "title", "acceptance", "state", "ui_ids", "require", "inputs")}, "required_checks": required_checks(manifest, item)}


def command_receipt(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    target, _ = parse_check(manifest, args.check)
    run = open_run(repo, paths, args.run)
    items = [item for item in ledger["items"] if item["id"] in args.item]
    if len(items) != len(set(args.item)):
        raise ValueError("Unknown item among: " + ", ".join(args.item))
    evidence_hash = None
    if args.evidence and not args.evidence.startswith(("http://", "https://")):
        evidence_path = local_path(repo, args.evidence)
        if not evidence_path.is_file():
            raise Refused("Evidence file does not exist: %s. Save the raw output under %s/%s/ first." % (args.evidence, manifest["paths"]["evidence"], run["id"]))
        evidence_hash = hashlib.sha256(evidence_path.read_bytes()).hexdigest()
    if args.result == "passed":
        if not args.command_line or not args.evidence:
            raise Refused("A pass needs --command (what ran) and --evidence (its saved raw output or a durable URL).")
        if not args.executed or args.executed < 1 or args.failed:
            raise Refused("A pass needs --executed of at least 1 and no failures. Zero discovered tests, a skipped target or a successful compile is not a pass; record `blocked` with a --note instead.")
    elif not args.note:
        raise Refused("A %s result needs --note: the symptom and the smallest reproduction, or what blocks the check." % args.result)
    tree = Tree(repo, state_dir)
    context = source_context(repo, state_dir)
    recorded = []
    for item in items:
        digest, count = check_digest(tree, manifest, item, target)
        if count == 0:
            raise Refused("No file matches the inputs of target %r, so a later change could not make this result stale. Fix the globs with `target`." % target)
        item["receipts"].append({
            "check": args.check, "result": args.result, "run_id": run["id"], "at": now().isoformat(),
            "head": context["head"], "dirty": bool(context["dirty_paths"]), "input_digest": digest, "input_files": count,
            "command": args.command_line, "evidence": args.evidence, "evidence_sha256": evidence_hash,
            "executed": args.executed, "failed": args.failed, "skipped": args.skipped, "environment": args.environment, "note": args.note,
        })
        if args.check not in required_checks(manifest, item) and args.check not in item.get("waived", {}):
            item["require"].append(args.check)
        recorded.append(item["id"])
    save_ledger(paths, ledger)
    view = render_status(repo, state_dir, manifest, paths, ledger)
    return {"recorded": recorded, "check": args.check, "result": args.result, "run": run["id"], "phase": view["phase"], "do": view["do"]}


def command_waive(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    parse_check(manifest, args.check)
    accepted_decision(paths, args.decision, "Waiving a check")
    matches = [item for item in ledger["items"] if item["id"] == args.item]
    if not matches:
        raise ValueError("No item " + args.item)
    matches[0].setdefault("waived", {})[args.check] = args.decision
    save_ledger(paths, ledger)
    render_status(repo, state_dir, manifest, paths, ledger)
    return {"item": args.item, "waived": args.check, "decision": args.decision}


def command_decide(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    decisions = read_decisions(paths)
    known = {decision["id"] for decision in decisions}
    for reference in (args.supersedes, args.confirms):
        if reference and reference not in known:
            raise ValueError("No decision " + reference)
    if args.confirms and args.authority == "assumption":
        raise Refused("Confirming needs an authority other than assumption: the user's words, a source location, a vendor document or an experiment.")
    decision_id = "D-%03d" % (len(decisions) + 1)
    lines = ["", "## %s · %s" % (decision_id, args.title.strip()), "", "- Date: " + now().strftime("%Y-%m-%d")]
    for label, value in [
        ("Scope", args.scope), ("Decision", args.decision), ("Reason", args.reason), ("Alternatives rejected", args.alternatives),
        ("Authority", args.authority + ": " + args.authority_ref), ("Revisit when", args.revisit),
        ("Supersedes", args.supersedes), ("Confirms", args.confirms),
    ]:
        if value:
            lines.append("- %s: %s" % (label, " ".join(value.split())))
    create_text(paths["decisions"], DECISIONS_TEMPLATE)
    with paths["decisions"].open("a", encoding="utf-8") as stream:
        stream.write("\n".join(lines) + "\n")
    render_status(repo, state_dir, manifest, paths, ledger)
    status = "assumed" if args.authority == "assumption" else "accepted"
    return {"id": decision_id, "status": status, "note": ("Name this assumption in the final reply so the user can veto it." if status == "assumed" else None)}


def command_start(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    opened = [run for run in read_runs(repo, paths) if run["status"] == "in_progress"]
    stamp = now()
    if opened:
        if not args.interrupted or {run["id"] for run in opened} != set(args.interrupted):
            raise Refused("Run %s is still open. If this session opened it, keep using it. Otherwise read %s, reconcile it with the tree, then run `start --interrupted %s`." % (opened[0]["id"], opened[0]["record"], " ".join(run["id"] for run in opened)))
        for run in opened:
            path = repo / run["record"]
            text = path.read_text(encoding="utf-8").replace("Run status: in_progress", "Run status: interrupted", 1)
            write_atomic(path, text.rstrip("\n") + "\n\n## Addendum " + stamp.strftime("%Y-%m-%d") + "\n\nClosed as interrupted by the next run. Its outcome was never recorded; treat its claims as unverified.\n")
    view = assess(repo, state_dir, manifest, paths, ledger)
    run_id = stamp.strftime("%Y%m%dT%H%M%S.%fZ")
    path = paths["runs"] / (run_id + ".md")
    handoff = view["last_handoff"]
    inherited = ["Phase at start: %s. %s" % (view["phase"], view["reason"])]
    if handoff:
        inherited += ["Previous run: %s (%s)." % (handoff["run"], handoff["outcome"]), "Its next action: " + handoff["next_action"], "Its not done: " + handoff["not_done"]]
    if view["interrupted_since_handoff"]:
        inherited.append("Interrupted since then, outcome unrecorded: " + ", ".join(view["interrupted_since_handoff"]))
    inherited += ["- %s %s: %s%s" % (entry["item"], entry["check"], entry["state"], (" — " + entry["why"]) if entry.get("why") else "") for entry in view["attention"][:10]]
    content = (
        "# Reflex run " + run_id + "\n\n"
        "Run status: in_progress\n\nStarted: " + stamp.isoformat() + "\n\n"
        "## Source at start\n\n```json\n" + json.dumps(view["source_now"], indent=2) + "\n```\n\n"
        "## Inherited\n\n" + "\n".join(inherited) + "\n\n"
        "## Chose and why\n\nNot selected yet.\n\n"
        "## Did\n\n" + PLACEHOLDERS["Did"] + "\n\n"
        "## Findings\n\nReasoning, hypotheses and failed attempts that a receipt cannot hold. Check results go in the ledger through `receipt`.\n\n"
        "## Not done\n\n" + PLACEHOLDERS["Not done"] + "\n\n"
        "## Next action\n\n" + PLACEHOLDERS["Next action"] + "\n"
    )
    if not create_text(path, content):
        raise ValueError("Run ID collision; retry")
    (paths["evidence"] / run_id).mkdir(parents=True, exist_ok=True)
    render_status(repo, state_dir, manifest, paths, ledger)
    return {"run_id": run_id, "record": path.relative_to(repo).as_posix(), "evidence_dir": (paths["evidence"] / run_id).relative_to(repo).as_posix(), "do": view["do"]}


def command_finish(repo, state_dir, args):
    manifest, paths, ledger = load_state(repo, state_dir)
    run = open_run(repo, paths, args.run)
    path = repo / run["record"]
    text = path.read_text(encoding="utf-8")
    for heading, placeholder in PLACEHOLDERS.items():
        body = section(text, heading)
        if not body or body == placeholder:
            raise Refused("Write the `## %s` section of %s before finishing. For Next action give a command or procedure, its target and the result that would accept it; write `None` only when nothing remains." % (heading, run["record"]))
    unresolved = []
    for item in ledger["items"]:
        for key in {receipt["check"] for receipt in item.get("receipts", []) if receipt["run_id"] == run["id"]}:
            if latest_receipt(item, key)["result"] != "passed":
                unresolved.append(item["id"] + " " + key)
    if args.outcome == "complete" and unresolved:
        raise Refused("This run recorded checks that still fail or are blocked (%s). Finish as `partial` or `blocked`." % ", ".join(sorted(unresolved)))
    text = text.replace("Run status: in_progress", "Run status: " + args.outcome, 1).replace("\n\n## Source at start", "\n\nFinished: " + now().isoformat() + "\n\n## Source at start", 1)
    write_atomic(path, text)
    view = render_status(repo, state_dir, manifest, paths, ledger)
    return {"run": run["id"], "outcome": args.outcome, "phase": view["phase"], "assumed_decisions": view["assumed_decisions"], "attention_total": view["attention_total"], "handoff": "Commit the state directory with the change it describes. In the final reply state the outcome, what was verified on which target, what is not done and the next action."}


def command_next(repo, state_dir, args):
    data = read_manifest(state_dir)
    if data is None:
        return {"schema_version": None, "phase": "uninitialized", "do": "Inspect existing plans and records, then run `init`."}
    if data["schema_version"] == 1:
        return {"schema_version": 1, "phase": "legacy", "do": "Run `migrate`. It adds the ledger and product context and keeps every existing record.", "read": sorted(data.get("paths", {}).values())}
    manifest, paths, ledger = load_state(repo, state_dir)
    view = assess(repo, state_dir, manifest, paths, ledger)
    if view["open_runs"]:
        ids = " ".join(run["id"] for run in view["open_runs"])
        view["do"] = "Run %s is still open. If this session opened it, continue it. Otherwise read its record, reconcile it with the tree and run `start --interrupted %s`. Then: %s" % (ids, ids, view["do"])
    elif view["interrupted_since_handoff"]:
        view["do"] = "Read the interrupted run records (%s) and reconcile their unrecorded work with the tree. Then: %s" % (", ".join(view["interrupted_since_handoff"]), view["do"])
    return view


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--repo", default=".", help="Project repository root (default: current directory)")
    common.add_argument("--state-dir", default=".reflex", help="State directory relative to the repository (default: .reflex)")
    commands = parser.add_subparsers(dest="command", required=True, metavar="command")

    def add(name, handler, summary):
        sub = commands.add_parser(name, parents=[common], help=summary, description=summary)
        sub.set_defaults(handler=handler)
        return sub

    sub = add("init", command_init, "Create missing state files. Never overwrites a record.")
    sub.add_argument("--status-doc", help="Existing status document to adopt, relative to the repository")
    sub.add_argument("--decisions-doc", help="Existing decisions document to adopt, relative to the repository")
    add("migrate", command_migrate, "Upgrade schema 1 state in place, keeping every record.")
    add("next", command_next, "Read-only. Report the phase, open runs, checks needing attention and one next step.")
    add("resume", command_next, "Alias of next.")
    sub = add("target", command_target, "Declare a target (core, ios, android, web) and the source globs whose changes make its results stale.")
    sub.add_argument("--name", required=True)
    sub.add_argument("--inputs", required=True, nargs="+", metavar="GLOB", help="Repository-relative globs; * also matches /")
    sub = add("item", command_item, "Add a work item, or update one with --id. Items are features or journeys with one acceptance result shared by every target.")
    sub.add_argument("--id", help="Existing item to update, such as F-001")
    sub.add_argument("--title")
    sub.add_argument("--acceptance", help="The observable result that proves the item on every target")
    sub.add_argument("--state", choices=("planned", "active", "dropped"))
    sub.add_argument("--ui-id", action="append", help="Identifier every UI target must use for this item; repeatable")
    sub.add_argument("--require", action="append", metavar="TARGET:KIND", help="Extra required check, such as android:binding; repeatable. Kinds: " + ", ".join(KINDS))
    sub.add_argument("--inputs", nargs="+", metavar="GLOB", help="Extra files whose changes make this item's results stale")
    sub.add_argument("--decision", help="Accepted decision ID; required to drop an item")
    sub.add_argument("--bypass-reason", help="Why a second item must be active before any slice is proven")
    sub = add("receipt", command_receipt, "Record one executed check for one or more items in the open run.")
    sub.add_argument("--item", required=True, action="append", help="Item ID; repeatable when one command covered several items")
    sub.add_argument("--check", required=True, metavar="TARGET:KIND")
    sub.add_argument("--result", required=True, choices=RESULTS)
    sub.add_argument("--command", dest="command_line", help="The exact command or procedure that ran")
    sub.add_argument("--evidence", help="Saved raw output inside the repository, or a durable http(s) URL")
    sub.add_argument("--executed", type=int)
    sub.add_argument("--failed", type=int, default=0)
    sub.add_argument("--skipped", type=int, default=0)
    sub.add_argument("--environment", help="Host, OS, simulator, emulator or device, ABI and toolchain")
    sub.add_argument("--note", help="Limits of a pass; required for failed and blocked")
    sub.add_argument("--run", help="Run ID when several runs are open")
    sub = add("waive", command_waive, "Stop requiring a check for an item, citing the accepted decision that allows the difference.")
    sub.add_argument("--item", required=True)
    sub.add_argument("--check", required=True, metavar="TARGET:KIND")
    sub.add_argument("--decision", required=True)
    sub = add("decide", command_decide, "Append a decision and get its ID. Authority `assumption` records a default the user has not confirmed.")
    sub.add_argument("--title", required=True)
    sub.add_argument("--decision", required=True, help="What was chosen")
    sub.add_argument("--reason", required=True)
    sub.add_argument("--authority", required=True, choices=AUTHORITIES)
    sub.add_argument("--authority-ref", required=True, help="The user's words, a file or URL with access date, or the evidence path of an experiment")
    sub.add_argument("--alternatives", help="Options considered and why each was rejected")
    sub.add_argument("--scope")
    sub.add_argument("--revisit", help="The condition that should reopen this decision")
    sub.add_argument("--supersedes", metavar="D-NNN")
    sub.add_argument("--confirms", metavar="D-NNN", help="Turn an assumed decision into an accepted one")
    sub = add("start", command_start, "Open a run record and its evidence directory. Refuses while another run is open.")
    sub.add_argument("--interrupted", nargs="+", metavar="RUN_ID", help="Close these open runs as interrupted after reconciling them")
    sub = add("finish", command_finish, "Close the open run after its Did, Not done and Next action sections are written.")
    sub.add_argument("--outcome", required=True, choices=OUTCOMES)
    sub.add_argument("--run", help="Run ID when several runs are open")

    args = parser.parse_args()
    try:
        repo = Path(args.repo).resolve()
        if not repo.is_dir():
            raise ValueError("Repository directory does not exist: " + args.repo)
        state_dir = local_path(repo, args.state_dir)
        if state_dir == repo:
            raise ValueError("Select a state subdirectory, not the repository root")
        print(json.dumps(args.handler(repo, state_dir, args), indent=2, ensure_ascii=False))
        return 0
    except Refused as refusal:
        print("reflex_state: refused: " + str(refusal), file=sys.stderr)
        return 2
    except (OSError, ValueError, TypeError, KeyError) as error:
        print("reflex_state: " + str(error) + ". Run with --help for usage.", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

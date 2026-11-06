#!/usr/bin/env python3
"""Initialize and locate project-local Reflex records without replacing them."""

import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import subprocess
import sys


VERSION = 1


def git(repo, *args):
    result = subprocess.run(
        ["git", "-C", str(repo)] + list(args),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    return result.stdout if result.returncode == 0 else None


def local_path(repo, name):
    if not isinstance(name, str) or not name:
        raise ValueError("State paths must be nonempty repository-relative strings")
    relative = Path(name)
    if relative.is_absolute() or ".." in relative.parts:
        raise ValueError("State paths must stay inside the selected repository")
    path = (repo / relative).resolve()
    try:
        path.relative_to(repo)
    except ValueError:
        raise ValueError("State paths must stay inside the selected repository")
    return path


def load_manifest(repo, state_dir):
    manifest = state_dir / "manifest.json"
    if not manifest.is_file():
        return None
    data = json.loads(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict):
        raise ValueError("State manifest must be an object; preserve it for inspection")
    if type(data.get("schema_version")) is not int or data["schema_version"] != VERSION:
        raise ValueError("Unsupported state schema; inspect and migrate it without overwriting records")
    paths = data.get("paths", {})
    if not isinstance(paths, dict) or set(paths) != {"status", "decisions", "runs", "evidence"}:
        raise ValueError("Incomplete or unknown state layout; inspect the manifest before changing it")
    resolve_paths(repo, paths)
    return data


def resolve_paths(repo, names):
    paths = {key: local_path(repo, value) for key, value in names.items()}
    values = list(paths.values())
    for index, path in enumerate(values):
        for other in values[index + 1:]:
            if path == other or path in other.parents or other in path.parents:
                raise ValueError("State document and directory paths must not overlap")
    return paths


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


def initialize(repo, state_dir, args):
    existing = load_manifest(repo, state_dir)
    prefix = state_dir.relative_to(repo).as_posix()
    data = existing or {
        "schema_version": VERSION,
        "paths": {
            "status": args.status_doc or prefix + "/status.md",
            "decisions": args.decisions_doc or prefix + "/decisions.md",
            "runs": prefix + "/runs",
            "evidence": prefix + "/evidence",
        },
    }
    for key, override in [("status", args.status_doc), ("decisions", args.decisions_doc)]:
        if existing and override and override != data["paths"][key]:
            raise ValueError("The manifest already owns " + key + "; reconcile its mapping deliberately")
    paths = resolve_paths(repo, data["paths"])
    for key in ("status", "decisions"):
        if paths[key].exists() and not paths[key].is_file():
            raise ValueError("Expected a document at " + str(paths[key]))
    for key in ("runs", "evidence"):
        if paths[key].exists() and not paths[key].is_dir():
            raise ValueError("Expected a directory at " + str(paths[key]))
    created = []
    documents = {
        "status": (
            "# Reflex project status\n\n"
            "Updated: not yet recorded\n\n"
            "## Current scope and source\n\n"
            "Not yet inventoried. Record repository/branch, public consumers and relevant source identity.\n\n"
            "## Work and verification\n\n"
            "| Work item | Implementation | Verification by target | Evidence / limits | Next action |\n"
            "| --- | --- | --- | --- | --- |\n\n"
            "## Blockers and decisions needed\n\nNone recorded yet.\n\n"
            "## Next action\n\nRead existing plans and evidence, then select the next authorized increment.\n\n"
            "## Latest run\n\nNo run recorded yet.\n"
        ),
        "decisions": (
            "# Reflex decisions\n\n"
            "No decisions recorded yet. Preserve existing approved choices when importing them.\n\n"
            "For each material choice, record its ID/date, scope, status, decision, alternatives,\n"
            "reason, authority or evidence, consequences and conditions for revisiting it.\n"
            "Supersede by reference; keep the original record and its rationale.\n"
        ),
    }
    state_dir.mkdir(parents=True, exist_ok=True)
    if create_text(state_dir / "manifest.json", json.dumps(data, indent=2) + "\n"):
        created.append(str((state_dir / "manifest.json").relative_to(repo)))
    for key in ("status", "decisions"):
        if create_text(paths[key], documents[key]):
            created.append(str(paths[key].relative_to(repo)))
    paths["runs"].mkdir(parents=True, exist_ok=True)
    paths["evidence"].mkdir(parents=True, exist_ok=True)
    return {"created": created, "preserved_existing_files": True}


def source_context(repo, state_dir):
    excluded = ":(exclude)" + state_dir.relative_to(repo).as_posix()
    head = git(repo, "rev-parse", "HEAD")
    branch = git(repo, "symbolic-ref", "--short", "HEAD")
    dirty = git(repo, "status", "--porcelain", "--untracked-files=normal", "--", ".", excluded)
    diff = git(repo, "diff", "--binary", "HEAD", "--", ".", excluded) if head else None
    return {
        "repository": str(repo),
        "head": head.decode().strip() if head else None,
        "branch": branch.decode().strip() if branch else None,
        "dirty_paths_at_start": dirty.decode().splitlines() if dirty else [],
        "tracked_diff_sha256_at_start": hashlib.sha256(diff).hexdigest() if diff is not None else None,
        "limits": "Start context is not verification. The diff hash excludes the state directory and untracked file contents.",
    }


def locate(repo, state_dir, data):
    paths = {key: local_path(repo, value) for key, value in data["paths"].items()}
    runs = sorted(paths["runs"].glob("*.md")) if paths["runs"].is_dir() else []
    missing = [str(path.relative_to(repo)) for path in paths.values() if not path.exists()]
    return {
        "state_directory": str(state_dir.relative_to(repo)),
        "documents": data["paths"],
        "missing": missing,
        "latest_run": str(runs[-1].relative_to(repo)) if runs else None,
        "source_now": source_context(repo, state_dir),
        "read_next": "Read status and the latest run's Not done and Next action, then the decisions and evidence relevant to the requested work. Reconcile these against the current tree.",
    }


def start_run(repo, state_dir, data):
    located = locate(repo, state_dir, data)
    if located["missing"]:
        raise ValueError("Partial state; inspect it and rerun init to fill only missing files")
    now = datetime.now(timezone.utc)
    run_id = now.strftime("%Y%m%dT%H%M%S.%fZ")
    path = local_path(repo, data["paths"]["runs"]) / (run_id + ".md")
    content = (
        "# Reflex run " + run_id + "\n\n"
        "Run status: in_progress\n\nStarted: " + now.isoformat() + "\n\n"
        "## Source at start\n\n```json\n"
        + json.dumps(located["source_now"], indent=2) + "\n```\n\n"
        "## Inherited work and evidence\n\n"
        "Previous run: " + (located["latest_run"] or "none") + "\n\n"
        "Pending reconciliation with status, decisions and the current tree.\n\n"
        "## Chose and why\n\nNot selected yet.\n\n"
        "## Did\n\nNo work recorded yet.\n\n"
        "## Verification\n\n"
        "| Check / claim | Result | Source and target | Command / artifact / limits |\n"
        "| --- | --- | --- | --- |\n\n"
        "## Not done\n\nWork and verification have not started in this record.\n\n"
        "## Blockers and decisions needed\n\nNone recorded yet.\n\n"
        "## Next action\n\nReconcile inherited work before implementation.\n\n"
        "## Handoff\n\nNot handed off. Record changed paths and commit/PR/CI state when applicable.\n"
    )
    if not create_text(path, content):
        raise ValueError("Run ID collision; preserve the existing record and retry")
    return {"run_id": run_id, "record": str(path.relative_to(repo)), "status": "in_progress"}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("command", choices=["init", "resume", "start"])
    parser.add_argument("--repo", default=".", help="Selected repository root")
    parser.add_argument("--state-dir", default=".reflex", help="State directory relative to the repository")
    parser.add_argument("--status-doc", help="Existing canonical status document, relative to the repository (init)")
    parser.add_argument("--decisions-doc", help="Existing canonical decisions document, relative to the repository (init)")
    args = parser.parse_args()
    try:
        repo = Path(args.repo).resolve()
        if not repo.is_dir():
            raise ValueError("Repository directory does not exist")
        state_dir = local_path(repo, args.state_dir)
        if state_dir == repo:
            raise ValueError("Select a state subdirectory, not the repository root")
        if args.command == "init":
            result = initialize(repo, state_dir, args)
        else:
            data = load_manifest(repo, state_dir)
            if data is None:
                raise ValueError("State is not initialized; inspect existing project records before running init")
            result = locate(repo, state_dir, data) if args.command == "resume" else start_run(repo, state_dir, data)
        print(json.dumps(result, indent=2))
        return 0
    except (OSError, ValueError, TypeError) as error:
        print("reflex_state: " + str(error), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())

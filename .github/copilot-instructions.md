# Copilot instructions — ai-databases-demos

## Repository status

This repository is a **scaffold**: it currently contains only `README.md` ("Azure AI Databases Demo")
and a Python `.gitignore`. There is no application code, dependency manifest, test suite, or CI yet.

Treat everything below as the intended shape of the repo. **When you add real structure
(dependency manifest, test runner, demo layout), update this file in the same change** so it stops
describing intent and starts describing reality.

## Project intent

Self-contained demos of **Azure AI database capabilities** (vector/semantic search, RAG,
embeddings-in-the-database patterns) across Azure data services. The `.gitignore` targets Python and
mentions Jupyter and Streamlit, so demos are expected to be Python scripts, notebooks, or small
Streamlit apps.

## Conventions to follow

- **Each demo is self-contained.** A demo lives in its own top-level directory with its own README
  covering prerequisites, required Azure resources, and how to run it. Do not create shared
  cross-demo abstractions until at least three demos need them.
- **No secrets in the repo.** Connection strings, keys, and endpoints come from environment
  variables (`.env` is gitignored). Commit a `.env.example` with placeholder keys instead. Prefer
  `DefaultAzureCredential` / Entra ID auth over key-based auth where the service supports it.
- **Provisioning is part of the demo.** Include the `az` CLI commands or Bicep needed to create the
  Azure resources a demo depends on — a reader should be able to go from zero to running.
- **Notebook hygiene.** Clear outputs before committing notebooks so diffs stay reviewable.

## Build, test, lint

None configured yet. When adding the first demo, prefer these defaults and record the exact commands
here:

- Dependencies: `uv` or a per-demo `requirements.txt`, installed into a local `.venv`.
- Tests: `pytest`; single test — `pytest path/to/test_file.py::test_name`.
- Lint/format: `ruff check .` and `ruff format .` (`.ruff_cache/` is already gitignored).

## Environment notes

Development happens on Windows — use backslash paths and PowerShell-compatible commands in docs and
scripts, or make scripts explicitly cross-platform.

# Worktro FP Service Analysis

> Target: `http://192.168.8.19:3000/`
> Date: 2026-06-02
> By: Claude Code (browse session)
> Version: v0.1.0

---

## 1. Overview

**Worktro FP (Fine-tuning Pipeline)** — a no-code, domain-specialized LLM fine-tuning platform.
Slogan: "Domain-specialized LLM by just picking an industry." It automates the full chain: **data collection → cleaning → training → evaluation → packaging → deployment**.

- Frontend: Next.js web UI (left sidebar + content layout, light theme)
- Backend worker: FastAPI (Eden-FP-worker repo)
- License: Apache-2.0 / MIT components, © 2026 Wise

## 2. Auth / Authorization

| Item | Detail |
|------|--------|
| Login | Email + password |
| Social login | Google / GitHub / Kakao — **all unimplemented (disabled)** |
| Role model | RBAC: `ADMIN` / `USER` |
| Current users | 3 (admin@edentns.com=Supervisor/ADMIN, Wiseman.Lim@gmail.com=ADMIN, user@edentns.com=USER) |
| Signup | `Sign up` link available |

Successful login redirects to `/dashboard`.

## 3. Route Map

| Path | Description | Access |
|------|-------------|--------|
| `/` | Landing (hero + 3 features) | Public |
| `/login` | Login | Public |
| `/dashboard` | System resources + recent jobs | User |
| `/jobs` | Job history | User |
| `/jobs/new/step-1-category` … 5 | 5-step job creation wizard | User |
| `/jobs/{uuid}` | Job detail (live progress/logs) | User |
| `/settings` | Profile + HF token | User |
| `/admin/users` | User management | Admin |
| `/admin/jobs` | All-user job monitoring + force cancel/delete | Admin |
| `/admin/resources` | GPU·disk·queue monitoring | Admin |
| `/admin/catalog` | Model/preset/whitelist catalog | Admin |
| `/admin/audit` | Audit log | Admin |

## 4. Core Feature: 5-Step Job Wizard

1. **Category** — 21 KSIC (Korean Standard Industrial Classification) major divisions (A Agriculture … U International orgs) + task type (Chat, etc.) + use-case description (min 10 chars)
2. **Model** — `Auto` (top-1 by HW + category) or `Manual` (pick candidate / enter HF repo). Shows fit %, VRAM requirement, supported languages
3. **Data** — sources: upload / directory / internet / synthetic. Formats: JSONL·JSON·CSV·Parquet·TXT·MD·HTML·PDF·DOCX (max 1GB). Auto-clean pipeline (6 stages):
   1) Dedup (MinHash) 2) Language filter 3) Quality filter (length·whitespace) 4) PII masking (email·phone·SSN·card) 5) Instruction formatting 6) Train/Val/Test split (8:1:1)
4. **Training config** — hyperparameters etc.
5. **Review & run** — final confirmation, then execute

## 5. Job Execution / Monitoring

- **9-stage pipeline** (Stage 1–9). On completion: `DONE` + `Stage 9/9`
- Job detail: live progress (SSE/WS streaming logs), tabs `Collected data` / `Inference demo` / `Download`
- Log sample: `{"msg":"Step 139/279","extra":{"loss":1.71,"epoch":1.49,"stage":7}}` — tracks step·loss·epoch·stage
- Avg training time 44.5 min (current environment)

## 6. Catalog (Model Registry)

- Models registered per HF repo: params(B), license, min VRAM, languages, priority, active flag, download
- Sample models: Qwen2-7B-Instruct (active), gemma-2-9b-it (active), Mistral-7B-Instruct-v0.3 (active), Llama-3.1-8B (active), BioMistral-7B, CodeLlama-13b, deepseek-coder, meditron-7b, Phi-3 — ~16 entries
- Tabs: Models / Category presets / Domain whitelist
- Supports `Auto-refresh` (HF search), `Seed defaults`, and file-upload model add

## 7. System Environment (Deployment Hardware)

| Item | Value |
|------|-------|
| GPU | NVIDIA **GB10** (Grace Blackwell), single GPU |
| Arch | aarch64, 20 threads |
| Memory | Unified memory, System RAM 121.6 GB |
| Disk free | 2835 GB |
| OS | linux |
| GPU temp | 46°C (idle) |

→ Likely a DGX Spark-class ARM unified-memory single-GPU workstation.

## 8. Findings / Recommendations

- ⚠️ **All 3 social logins unimplemented** — buttons shown but disabled
- ⚠️ **Live progress shows "disconnected"** — SSE/WebSocket disconnect state. Review reconnect logic
- ⚠️ **Catalog auto-refresh `hf_search_errors: 15`** — all 15 HF searches failed. Check HF token/network
- ⚠️ **Data step "server-side path input (dev only)"** — path-injection/traversal risk in prod; disable it
- ⚠️ **admin/jobs force delete** — permanently removes other users' data. Warning text exists but add a confirm step
- ℹ️ **HTTP (unencrypted) + private IP** — internal/dev deployment. HTTPS required if exposed
- ℹ️ **Plaintext credential sharing** — admin password was shared over chat. Rotate after analysis

## 9. Verdict

A clear 5-step wizard + KSIC domain presets + HW auto-adaptation (GB10/ARM) make **domain LLM fine-tuning accessible to non-experts**. The data-cleaning pipeline (MinHash·PII masking·8:1:1 split), model catalog, audit log, and RBAC are solid for a v0.1.0. Remaining work: finish unimplemented items (social login, SSE reconnect, HF search errors) and isolate the dev-only path input from production.

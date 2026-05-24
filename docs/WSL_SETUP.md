# Running club-3090 on Windows (WSL2) — from scratch

A start-to-finish path for getting club-3090 running on a Windows machine via **WSL2** (Windows Subsystem for Linux). If you're already on native Linux, ignore this — use the [Quick start](../README.md#quick-start).

**What works on Windows:**

| Engine | Native Windows | WSL2 |
|---|---|---|
| vLLM | ❌ (Linux + CUDA only) | ✅ |
| llama.cpp / ik_llama | ✅ (native build, no Docker) | ✅ (Docker, matches the recipes) |

This guide uses **WSL2 + Docker** so the commands match the rest of the repo. The bulk of the work is one-time host setup (steps 1–6); after that it's the normal [Quick start](../README.md#quick-start).

> **Runtime tuning lives elsewhere — this guide links to it, doesn't repeat it.** Once you're booting, the WSL2-specific VRAM budget, TDR timeout, and boot-crash fixes are in [FAQ.md → Windows/WSL2](FAQ.md#does-this-work-on-windows--wsl2) and [HARDWARE.md → WSL2/Windows](HARDWARE.md#note-for-wsl2--windows-users). Steps 8–9 point you at them.

---

## 1. Install WSL2 + Ubuntu

From an **Administrator PowerShell**:

```powershell
wsl --install -d Ubuntu-22.04
wsl --set-default-version 2
```

Reboot when prompted. Then confirm the distro is on **version 2** (not 1):

```powershell
wsl -l -v        # VERSION column must read 2
```

Everything from here runs **inside the Ubuntu (WSL) shell** unless a step explicitly says "Windows / PowerShell".

## 2. NVIDIA driver + GPU passthrough

Install the **Windows** NVIDIA driver (580.x+ for vLLM's CUDA 13 runtime) from nvidia.com. **Do not install a driver *inside* WSL** — WSL inherits the Windows driver via GPU passthrough; a second driver inside the distro breaks it.

Verify passthrough from the WSL shell:

```bash
nvidia-smi      # must list your 3090(s). If it errors, update the Windows driver and reboot.
```

## 3. Give WSL2 enough RAM — `.wslconfig` ⚠️

**The most common silent failure.** WSL2 defaults to **50% of host RAM**, and the model loader needs to hold the whole checkpoint in RAM. If it can't, vLLM disables auto-prefetch, falls back to a slow streaming path, and you get a *misleading* `Tried to allocate ~44 MiB` "GPU OOM" that's actually **host-RAM starvation** ([#32](https://github.com/noonghunna/club-3090/issues/32)).

Create `C:\Users\<You>\.wslconfig` (Windows side) — size `memory` above your checkpoint (the 27B INT4 is ~18 GB, so give ≥24 GB):

```ini
[wsl2]
memory=24GB
swap=8GB
```

Apply it from **PowerShell**, then verify in WSL:

```powershell
wsl --shutdown          # PowerShell — fully restarts the VM
```
```bash
free -h                 # WSL — "total" should now show ~24Gi
```

## 4. Docker + NVIDIA Container Toolkit (for vLLM)

Use **either** Docker Desktop (WSL2 backend, GPU enabled in Settings → Resources) **or** `docker-ce` + `nvidia-container-toolkit` installed inside the distro. Verify the GPU reaches a container:

```bash
docker run --rm --gpus all nvidia/cuda:12.4.0-base-ubuntu22.04 nvidia-smi
```

If you only want the llama.cpp / ik_llama path you can skip Docker and use a native build — but Docker keeps you on the same commands as the rest of the docs.

## 5. Clone onto the ext4 filesystem — NOT `/mnt/c` ⚠️

Clone into your **WSL home** (`~`), which is the distro's native ext4 filesystem:

```bash
cd ~
git clone https://github.com/noonghunna/club-3090.git
cd club-3090
```

**Do not clone under `/mnt/c` or `/mnt/d`.** Those are the Windows drive mounted via DrvFs, which is **10–50× slower** for the many-small-file I/O that git and the scripts do, and it **doesn't preserve Unix file modes** — so the helper scripts lose their exec bit and you hit mysterious `permission denied` failures. Model *weights* are large-but-few files and can live on a Windows drive if you're short on space (see step 7); the repo itself must be on ext4.

## 6. Keep `.env` and scripts as LF — not CRLF ⚠️

If you create or edit `.env` (or any script) with a Windows editor, it may save with **CRLF** line endings. That breaks two things:

- **`docker compose`** reads `GPU_MEMORY_UTILIZATION=0.94\r` — the trailing `\r` becomes part of the *value*, producing baffling "no such file"/invalid-number errors.
- **Shell scripts** fail with `bad interpreter: /usr/bin/env bash^M`.

Prevent it before cloning, and fix any file that slipped through:

```bash
git config --global core.autocrlf input    # set BEFORE cloning
dos2unix .env                               # or: sed -i 's/\r$//' .env
```

In VS Code, set the file's EOL to **LF** (bottom-right status bar) and enable `"files.eol": "\n"`.

## 7. Download weights — `WEIGHTS` + `MODEL_DIR`

For the **robust single-card path on a 24 GB card** (recommended on WSL2 — see step 10), fetch the **GGUF** weights for llama.cpp / ik_llama:

```bash
WEIGHTS=gguf bash scripts/setup.sh qwen3.6-27b      # Q4_K_M MTP GGUF + vision mmproj, SHA-verified
```

For the vLLM path, omit `WEIGHTS` (defaults to the AutoRound INT4):

```bash
bash scripts/setup.sh qwen3.6-27b
```

**Where weights live:** keep them on ext4 if you have room. If not, point `MODEL_DIR` at a Windows drive both OSes can see — weights are OS-agnostic and the DrvFs slowness barely matters for a few multi-GB files (unlike the repo in step 5):

```bash
export MODEL_DIR=/mnt/d/models      # from WSL; or D:\models from PowerShell
```

Set `MODEL_DIR` **consistently** — either `export` it in your shell *or* put it in the repo-root `.env`, then use it for both `setup.sh` and `launch.sh`. (Mixing the two sources can disagree; see [#187](https://github.com/noonghunna/club-3090/issues/187).)

## 8. Budget for the ~1.3 GiB WSL2 GPU overhead

WSL2's container CUDA context reserves **~1.3 GiB of VRAM that `nvidia-smi` doesn't show at idle** but is locked once a container starts — so the headless-Linux defaults can crash on boot. The fixes (don't repeat them here):

- **Single-card vLLM:** drop `GPU_MEMORY_UTILIZATION=0.94` into `models/qwen3.6-27b/vllm/compose/.env`.
- **Single-card llama.cpp / ik_llama:** lower the context (e.g. `CTX_SIZE=131072`), since these allocate by fixed size, not a ratio.

Full per-compose VRAM table + the combined `.env` template: [FAQ.md → Windows/WSL2](FAQ.md#does-this-work-on-windows--wsl2) and [HARDWARE.md → GPU memory budget on WSL2](HARDWARE.md#note-for-wsl2--windows-users).

## 9. Long-prompt + boot-crash gotchas (TDR, expandable_segments)

Two WSL2-specific failure modes, both fixed on the **Windows** side, both documented in [HARDWARE.md → WSL2/Windows](HARDWARE.md#note-for-wsl2--windows-users):

- **TDR timeout** — Windows force-resets the GPU after 2 s of kernel time; long-context prompts trip it (`CUDA driver error: device not ready`). Fix: raise `TdrDelay` to 60 via the registry + reboot.
- **`expandable_segments` boot crash** — `device not ready` at `gptq_marlin_repack` on some drivers. Fix: `PYTORCH_CUDA_ALLOC_CONF=expandable_segments:False` (already exposed as a `.env` knob).

## 10. Boot it

Then it's the normal [Quick start](../README.md#quick-start). On a single 24 GB card under WSL2, the **llama.cpp / ik_llama** paths are the most forgiving (no prefill cliffs, smaller VRAM footprint):

```bash
bash scripts/launch.sh --variant ik-llama/iq4ks-mtp   # single-card, leanest VRAM — fits WSL2 at defaults
bash scripts/launch.sh --variant llamacpp/default     # single-card, cliff-immune (drop CTX_SIZE if tight)
bash scripts/launch.sh --variant vllm/dual            # 2 cards — WSL2 overhead is noise at TP=2
```

Sanity-check the endpoint (the launcher prints this curl too):

```bash
curl -sf http://localhost:8020/v1/chat/completions \
  -H "Content-Type: application/json" \
  -d '{"model":"qwen3.6-27b-autoround","messages":[{"role":"user","content":"Capital of France?"}],"max_tokens":200}'
```

---

## Recommended config on WSL2

| Hardware | Recommended | Why |
|---|---|---|
| 1× 24 GB (3090/4090) | `ik-llama/iq4ks-mtp` (GGUF) | Leanest VRAM — fits at defaults despite the ~1.3 GiB overhead; no prefill cliffs |
| 1× 24 GB, want vLLM | `vllm/single` + `GPU_MEMORY_UTILIZATION=0.94` `.env` | Full feature stack; needs the WSL2 VRAM + TDR tuning (steps 8–9) |
| 2× 24 GB | `vllm/dual` | TP=2; the ~1.3 GiB overhead is noise at ~17 GB/card |

## See also

- [FAQ.md → Does this work on Windows / WSL2?](FAQ.md#does-this-work-on-windows--wsl2) — runtime VRAM/ctx tuning
- [HARDWARE.md → Note for WSL2 / Windows users](HARDWARE.md#note-for-wsl2--windows-users) — TDR, expandable_segments, the VRAM-overhead formula
- [README → Quick start](../README.md#quick-start) · [SINGLE_CARD.md](SINGLE_CARD.md) — the single-card config detail

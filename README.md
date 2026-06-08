# OpenQP SCF-Converger ML

SCF-converger **database** + **ML method-selector training** for
**[OpenQP](https://github.com/Open-Quantum-Platform/openqp)** (Open Quantum Platform).

> Companion data/ML repository for OpenQP — upstream code:
> https://github.com/Open-Quantum-Platform/openqp

Goal: learn which SCF converger (C-/E-/A-DIIS, SOSCF, TRAH) converges a given system in the
fewest **Fock-equivalent builds** (regular + response), and ship a tiny distilled model that
OpenQP's `converger_type=ml` loads at runtime (no heavy deps in OpenQP).

## 🤝 Contribute your convergence data — this is a community database

**The selector is only as good as the data behind it. Please contribute!** The more diverse the
systems (sizes, elements, charges, spin states, functionals, basis sets, hard/biradical/TM
cases), the better the learned selector becomes **for everyone**.

How to contribute (a few minutes):
1. Run the harness (`harness/build_database.py`) on your molecules — it sweeps each system through
   all convergers and records `system,ref,func,converger,natom,charge,converged,niter,time,E`.
2. Drop your CSV in `data/contrib/<your-name-or-group>.csv` (same columns) **and open a Pull
   Request**, *or* simply open an Issue and attach the CSV — we'll merge it.
3. Include the basis set + how the geometry was obtained (add the `.xyz` to `geometries/` if new).

Every accepted contribution is folded into the next model release. Hard cases where DIIS/SOSCF
**fail** are especially valuable. By contributing you agree the data may be redistributed with
this repository and used to train the shipped selector.

## Layout
```
data/        databases (the training data; large CSVs live here, NOT in the openqp repo)
  db_openqp_postfix.csv  CANONICAL training DB: OpenQP per-converger costs
                         (cdiis/ediis/adiis/soscf/trah) with true Fock-equivalent
                         cost (niter + TRAH micro/response builds). This is what the
                         selector trains on.
  contrib/               community-contributed OpenQP DBs (same schema), also trained on.
  studies/               reference-only, NOT used for selector training:
    db_pyscf_methods.csv   10,890 cells: PySCF method + noise-robustness study
    db_openqp_prefix.csv   obsolete pre-fix OpenQP DB (niter-only; superseded)
harness/     data generation (build_database.py, reparse_fock.py, ensemble_scf_proto.py, systems.py)
geometries/  the 24-system tier-0..3 benchmark geometries
train/       train_selector.py -> trains + distills to model/scf_selector_model.py
model/       scf_selector_model.py  (distilled plain-Python predict(); copied into pyoqp)
```

## Pipeline
1. **Generate** the DB on the cluster (SLURM) / zeus — see harness/.
2. **Train**: `python train/train_selector.py --db data/db_openqp_postfix.csv` →
   labels best converger per (system, functional), trains a small decision tree, prints
   leave-one-system-out accuracy + Fock-build regret vs always-C-DIIS, and **distills** the
   tree to `model/scf_selector_model.py`.
3. **Deploy**: copy `model/scf_selector_model.py` into `openqp/pyoqp/oqp/library/` so
   `converger_type=ml` uses it (falls back to the rule-based `auto` selector if absent).

## Key findings (so far)
- **C-DIIS is the best default** (wins 52/58 OpenQP cells; mean ~21 Fock builds vs A-DIIS 39,
  E-DIIS 53). E-/A-DIIS only help on hard open-shell transition-metal DFT systems.
- **TRAH is most expensive** on true cost (response builds) — reserve for failures.
- An incremental-Fock-refresh fix (in OpenQP) removed C-DIIS's noise-floor stall (caffeine
  117 -> 19, matching PySCF). DB to be **regenerated post-fix** before final training.

Repo: private (training data + WIP). The distilled model + the `auto`/`ml` selector code live
in OpenQP (fork karmachoi -> PR upstream).

## Automated collect → train → ship

**Collect (automatic):** run your OpenQP jobs as usual, then
`python contribute/collect.py --logs <your_run_dir> --out data/contrib/<you>.csv` (or `--watch 60`
to accumulate continuously). PR the CSV.

**Train (automatic):** a GitHub Action (`.github/workflows/train.yml`) retrains on every push to
`data/**` (i.e. when a contribution merges), weekly, or on demand — it runs `train/run.sh`
(union all data → decision tree → leave-one-system-out accuracy + Fock-build regret) and commits
the refreshed `model/scf_selector_model.py` + `model/metrics.txt`.

**Ship:** copy `model/scf_selector_model.py` into `openqp/pyoqp/oqp/library/`; then
`converger_type=ml` uses it (and `converger_type=auto` is the always-available rule-based fallback).

## Priority: ROHF/UHF stability
ROKS is the **MRSF-TDDFT** reference, so **open-shell (ROHF/UHF) SCF robustness is the top goal** —
an unstable/wrong-state open-shell SCF corrupts the excited-state result. Contributions of
**open-shell, transition-metal, and biradical** systems (HF *and* DFT) are the most valuable, and
the selector enables the stability safeguard for these by default.

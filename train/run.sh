#!/bin/bash
# One-command pipeline: union all data (DB + contributions) -> train -> distill model.
set -e
python train/train_selector.py --db "data/*.csv" "data/contrib/*.csv" \
  --geom geometries --out model/scf_selector_model.py | tee model/metrics.txt
echo "model -> model/scf_selector_model.py ; copy into openqp/pyoqp/oqp/library/ for converger_type=ml"

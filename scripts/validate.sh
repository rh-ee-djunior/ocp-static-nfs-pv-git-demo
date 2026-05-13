#!/usr/bin/env bash
set -euo pipefail

NS="${NS:-nfs-static-pv-demo}"
PV="${PV:-static-nfs-pv-demo}"
PVC="${PVC:-static-nfs-pvc-demo}"

echo "[1/5] PV"
oc get pv "$PV" -o wide

echo "[2/5] PVC"
oc get pvc "$PVC" -n "$NS" -o wide

echo "[3/5] Pods"
oc get pods -n "$NS" -o wide

echo "[4/5] Route"
ROUTE=$(oc get route nfs-pv-writer -n "$NS" -o jsonpath='{.spec.host}')
echo "http://${ROUTE}"

echo "[5/5] App data"
curl -s "http://${ROUTE}/list"
echo

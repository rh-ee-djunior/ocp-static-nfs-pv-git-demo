# Runbook de Migração de PV NFS Estático

## Premissas

- O PV é estático e gerenciado via Git.
- A aplicação consome o PVC `static-nfs-pvc-demo`.
- O PVC está fixado ao PV `static-nfs-pv-demo` via `spec.volumeName`.
- O PV está configurado com `persistentVolumeReclaimPolicy: Retain`.

## Validação inicial

```bash
oc get pv static-nfs-pv-demo -o wide
oc get pvc static-nfs-pvc-demo -n nfs-static-pv-demo -o wide
oc get pod -n nfs-static-pv-demo
```

Gerar dados:

```bash
ROUTE=$(oc get route nfs-pv-writer -n nfs-static-pv-demo -o jsonpath='{.spec.host}')
curl -s "http://$ROUTE/write?msg=antes-da-migracao"
curl -s "http://$ROUTE/generate?files=10&size_kb=128"
curl -s "http://$ROUTE/list"
```

## Migração

### 1. Congelar escrita

```bash
oc scale deployment/nfs-pv-writer -n nfs-static-pv-demo --replicas=0
```

### 2. Copiar dados para o novo NFS

```bash
rsync -aHAXv --numeric-ids /exports/ocp-static-nfs-pv-demo/ \
  root@NOVO_NFS:/exports/ocp-static-nfs-pv-demo/
```

### 3. Alterar Git

Alterar no arquivo `manifests/01-pv-nfs.yaml`:

```yaml
nfs:
  server: NOVO_NFS
  path: /exports/ocp-static-nfs-pv-demo
```

Commit:

```bash
git add manifests/01-pv-nfs.yaml
git commit -m "Migrate static NFS PV to new server"
git push
```

### 4. Recriar objetos

```bash
oc delete deployment nfs-pv-writer -n nfs-static-pv-demo --ignore-not-found
oc delete pvc static-nfs-pvc-demo -n nfs-static-pv-demo --ignore-not-found
oc delete pv static-nfs-pv-demo --ignore-not-found
oc apply -k manifests/
```

### 5. Validar

```bash
oc get pv static-nfs-pv-demo
oc get pvc -n nfs-static-pv-demo
oc get pods -n nfs-static-pv-demo

ROUTE=$(oc get route nfs-pv-writer -n nfs-static-pv-demo -o jsonpath='{.spec.host}')
curl -s http://$ROUTE/list
curl -s "http://$ROUTE/write?msg=depois-da-migracao"
```

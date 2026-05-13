# OpenShift Static NFS PV Git Demo

Aplicação de laboratório para testar migração de PersistentVolumes NFS criados por Git.

## Objetivo

Este repositório simula um cenário onde:

- o `PersistentVolume` é estático e fica versionado no Git;
- o PV aponta diretamente para um servidor NFS;
- a aplicação consome um `PersistentVolumeClaim` que se liga ao PV pelo campo `volumeName`;
- para simular a migração, você altera apenas o `server` e/ou `path` dentro do arquivo `manifests/01-pv-nfs.yaml`.

## Arquitetura

```text
NFS Server antigo/novo
  └── export: /exports/ocp-static-nfs-pv-demo
        ↑
        │ PersistentVolume: static-nfs-pv-demo
        ↑
        │ PersistentVolumeClaim: static-nfs-pvc-demo
        ↑
        │ Deployment: nfs-pv-writer
        ↑
        │ Service + Route
        ↑
      Usuário / Browser / curl
```

## Arquivos principais

```text
manifests/
├── 00-namespace.yaml
├── 01-pv-nfs.yaml              # ALTERE AQUI o servidor/path NFS
├── 02-pvc.yaml                 # PVC fixado no PV pelo volumeName
├── 03-configmap-app.yaml       # Código Python da aplicação
├── 04-deployment.yaml          # Aplicação consumindo o PVC
├── 05-service.yaml
├── 06-route.yaml
├── 07-data-generator-job.yaml  # Job opcional para gerar massa de dados
└── kustomization.yaml
```

## 1. Ajustar o servidor NFS

Edite somente o arquivo abaixo:

```bash
vi manifests/01-pv-nfs.yaml
```

Altere:

```yaml
nfs:
  server: 10.0.0.10
  path: /exports/ocp-static-nfs-pv-demo
```

Para o IP/hostname e path reais do seu NFS.

## 2. Preparar o export NFS

No servidor NFS, crie o diretório exportado:

```bash
mkdir -p /exports/ocp-static-nfs-pv-demo
chmod -R 0777 /exports/ocp-static-nfs-pv-demo
```

Exemplo de `/etc/exports` para laboratório:

```text
/exports/ocp-static-nfs-pv-demo *(rw,sync,no_subtree_check,no_root_squash)
```

Depois:

```bash
exportfs -rav
```

> Para produção, ajuste permissões e política NFS de acordo com seu padrão de segurança.

## 3. Aplicar no OpenShift

```bash
oc apply -k manifests/
```

Validar:

```bash
oc get pv static-nfs-pv-demo
oc get pvc -n nfs-static-pv-demo
oc get pods -n nfs-static-pv-demo
oc get route -n nfs-static-pv-demo
```

O PVC deve ficar `Bound` com o PV `static-nfs-pv-demo`.

## 4. Gerar dados persistentes

Pela rota:

```bash
ROUTE=$(oc get route nfs-pv-writer -n nfs-static-pv-demo -o jsonpath='{.spec.host}')
curl -s http://$ROUTE/
curl -s "http://$ROUTE/write?msg=teste-antes-migracao"
curl -s "http://$ROUTE/generate?files=5&size_kb=64"
curl -s http://$ROUTE/list
```

Ou usando o Job:

```bash
oc delete job nfs-pv-data-generator -n nfs-static-pv-demo --ignore-not-found
oc apply -f manifests/07-data-generator-job.yaml
oc logs -n nfs-static-pv-demo job/nfs-pv-data-generator
```

## 5. Simular migração de NFS

### 5.1 Parar a aplicação

```bash
oc scale deployment/nfs-pv-writer -n nfs-static-pv-demo --replicas=0
```

### 5.2 Copiar os dados do NFS antigo para o novo

Exemplo no servidor NFS antigo:

```bash
rsync -aHAXv --numeric-ids /exports/ocp-static-nfs-pv-demo/ \
  root@NOVO_NFS:/exports/ocp-static-nfs-pv-demo/
```

### 5.3 Alterar o PV no Git

Edite:

```bash
vi manifests/01-pv-nfs.yaml
```

Troque apenas:

```yaml
nfs:
  server: NOVO_NFS
  path: /exports/ocp-static-nfs-pv-demo
```

Faça commit e push:

```bash
git add manifests/01-pv-nfs.yaml
git commit -m "Change NFS server for static PV migration test"
git push
```

### 5.4 Recriar o PV/PVC para refletir o novo NFS

Atenção: em Kubernetes/OpenShift, a fonte do volume do PV não deve ser tratada como atualização comum. Para simular a troca, recrie os objetos.

```bash
oc delete deployment nfs-pv-writer -n nfs-static-pv-demo --ignore-not-found
oc delete pvc static-nfs-pvc-demo -n nfs-static-pv-demo --ignore-not-found
oc delete pv static-nfs-pv-demo --ignore-not-found

oc apply -k manifests/
```

### 5.5 Validar dados após migração

```bash
oc get pv static-nfs-pv-demo
oc get pvc -n nfs-static-pv-demo
oc get pods -n nfs-static-pv-demo

ROUTE=$(oc get route nfs-pv-writer -n nfs-static-pv-demo -o jsonpath='{.spec.host}')
curl -s http://$ROUTE/list
curl -s "http://$ROUTE/write?msg=teste-depois-migracao"
```

Se os arquivos antigos aparecerem no `/list`, a migração de dados do NFS foi validada.

## Observações importantes

- O PV usa `persistentVolumeReclaimPolicy: Retain` para evitar remoção lógica dos dados quando o PVC/PV for removido.
- O PVC usa `volumeName: static-nfs-pv-demo` para forçar o bind no PV específico.
- O PV usa `claimRef` para reservar o PV para o PVC do namespace `nfs-static-pv-demo`.
- Se você mudar o namespace, atualize também o `claimRef.namespace` no PV.
- O acesso NFS deve estar liberado para todos os nodes schedulable do OpenShift.


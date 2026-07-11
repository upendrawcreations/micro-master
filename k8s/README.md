# Metaarch on local Kubernetes

These manifests deploy the five Java services, MySQL, the Elastic stack,
Prometheus, and Grafana into the `metaarch` namespace.

## Prerequisites

Enable Kubernetes in Docker Desktop and verify it:

```powershell
kubectl cluster-info
kubectl get nodes
```

Allocate at least 10 GB of memory to Docker Desktop. Do not run the Compose
stack at the same time because both stacks expose admin ports on the host.

## Build and deploy

Build the local application images:

```powershell
docker compose build
```

Docker Desktop Kubernetes can use locally built images. For Kind, load each
image using `kind load docker-image <image>:local`. For a remote cluster,
push versioned images to a registry and replace the five `:local` image names.

Validate and deploy:

```powershell
kubectl apply --dry-run=client -k k8s
kubectl apply -k k8s
kubectl get pods -n metaarch -w
```

The initial startup can take several minutes. Check failures with:

```powershell
kubectl get events -n metaarch --sort-by=.metadata.creationTimestamp
kubectl describe pod -n metaarch <pod-name>
kubectl logs -n metaarch <pod-name>
```

## Local URLs

With Docker Desktop Kubernetes:

- API gateway: http://localhost:30082
- Grafana: http://localhost:30001 (`admin` / `admin`)
- Prometheus: http://localhost:30090
- Kibana: http://localhost:30561

If NodePorts are not reachable through localhost, use port forwarding:

```powershell
kubectl port-forward -n metaarch service/metaarch-api-gateway 8082:8082
kubectl port-forward -n metaarch service/grafana 3001:3000
kubectl port-forward -n metaarch service/prometheus 9090:9090
kubectl port-forward -n metaarch service/kibana 5601:5601
```

## Remove the deployment

```powershell
kubectl delete -k k8s
```

Deleting the namespace or PVCs deletes the local Kubernetes database and
monitoring data. Change all development passwords before a shared or production
deployment.

## Jenkins deployments

For CI/CD that can deploy all applications or only one selected service, see
[JENKINS-PIPELINE.md](JENKINS-PIPELINE.md). The selective pipeline updates only
the chosen Kubernetes Deployment and does not restart unrelated applications.

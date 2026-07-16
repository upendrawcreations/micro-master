# Metaarch on local Kubernetes

To onboard a new REST service across application code, Config Server, Gateway,
Docker Compose, Kubernetes, monitoring, and Jenkins, see
[Adding a REST application](ADDING-REST-APPLICATION.md).

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

## Ingress URLs

The host-based Ingress in `ingress.yaml` exposes these applications without
changing their internal URL paths:

- API Gateway: http://gateway.metaarch.local
- Grafana: http://grafana.metaarch.local
- Kibana: http://kibana.metaarch.local

An NGINX Ingress Controller with an IngressClass named `nginx` must be running:

```powershell
kubectl get ingressclass
kubectl get pods -A | Select-String ingress
```

When using Windows Command Prompt (`cmd.exe`) instead of PowerShell, use
`findstr`:

```bat
kubectl get pods -A | findstr ingress
```

For local Docker Desktop development, install the controller and wait for it:

```bat
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.15.1/deploy/static/provider/cloud/deploy.yaml
kubectl wait --namespace ingress-nginx --for=condition=ready pod --selector=app.kubernetes.io/component=controller --timeout=180s
kubectl get ingressclass
```

Ingress-nginx has reached retirement and should be treated as a local
development option here. Select a maintained ingress or Gateway API controller
before using this setup in a new production environment.

If the cluster does not provide one, install the ingress-nginx controller using
the installation instructions for that Kubernetes distribution before applying
these manifests.

For a local cluster whose Ingress controller is reachable at `127.0.0.1`, open
`C:\Windows\System32\drivers\etc\hosts` as Administrator and add:

```text
127.0.0.1 gateway.metaarch.local
127.0.0.1 grafana.metaarch.local
127.0.0.1 kibana.metaarch.local
```

If the controller has a different external address, obtain it with
`kubectl get ingress -n metaarch` and use that address instead. Verify routing:

```powershell
kubectl describe ingress -n metaarch metaarch-ingress
curl.exe http://gateway.metaarch.local/actuator/health
curl.exe http://grafana.metaarch.local/api/health
curl.exe http://kibana.metaarch.local/api/status
```

The existing NodePort URLs remain available as a fallback.

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

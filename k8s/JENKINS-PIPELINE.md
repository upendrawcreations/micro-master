# Jenkins selective deployment pipeline

The root `Jenkinsfile` builds and deploys either every Kubernetes application
or one selected application. A single-service run only changes that service's
Deployment image and waits for its rollout; the other Deployments are not
applied or restarted.

## Jenkins agent requirements

Use a Windows agent with the label `docker-kubectl` and install:

- Git
- Docker CLI with access to a Docker daemon
- `kubectl`
- Jenkins Pipeline, Git, Credentials Binding, and Workspace Cleanup plugins

The Jenkins agent must be able to reach the Kubernetes API server and the
container registry. For a production-like setup, use a registry reachable by
both Jenkins and every Kubernetes node.

## Credentials

Create these Jenkins credentials:

| ID | Type | Purpose |
|---|---|---|
| `metaarch-git` | Username/password or Git-compatible credential | Clone the private service repositories |
| `metaarch-registry` | Username/password | Push application images |
| `metaarch-kubeconfig` | Secret file | Kubeconfig used for deployment |

Do not store kubeconfig files, registry passwords, or Git tokens in this
repository.

## Repository URLs

Configure these global or folder-level Jenkins environment variables:

| Variable | Application repository |
|---|---|
| `EUREKA_REPO_URL` | Eureka Server |
| `CONFIG_SERVER_REPO_URL` | Config Server |
| `API_GATEWAY_REPO_URL` | API Gateway |
| `ORG_ACCESS_REPO_URL` | Org Access |
| `BOOKING_SYSTEM_REPO_URL` | Booking System |

Each repository must have its `Dockerfile` at its root. If a repository uses a
different Docker build context, update that service's build command in the
`Jenkinsfile`.

## Create and run the Jenkins job

1. Create a Pipeline job pointing to the repository containing this
   `Jenkinsfile`.
2. Run **Build with Parameters**.
3. Choose `all` or one value under `SERVICE`.
4. Set `REGISTRY`, for example `registry.example.com/metaarch`.
5. Keep `PUSH_IMAGES` enabled when Kubernetes does not share the Jenkins
   agent's local Docker daemon.

The generated default image tag contains the Jenkins build number and the
service Git revision. `IMAGE_TAG` can override it for a controlled release.

## Deployment behavior

For a selected service, the pipeline effectively runs:

```powershell
kubectl -n metaarch set image `
  deployment/booking-system `
  booking-system=registry.example.com/metaarch/booking-system:<tag>

kubectl -n metaarch rollout status deployment/booking-system --timeout=5m
```

This leaves Eureka, Config Server, API Gateway, and Org Access unchanged.
Choosing `all` repeats the same targeted operation for all five deployments.

## Docker Desktop note

If Jenkins runs on the same computer and uses Docker Desktop's daemon, an empty
`REGISTRY` with `PUSH_IMAGES` disabled can be used for local-only testing.
Remote clusters require pushed images. Ensure the image registry and tag are
compatible with the cluster's `imagePullPolicy` and registry authentication.

# Adding a REST application to the Metaarch architecture

This guide describes the complete process for adding a Spring Boot REST
application to this repository, local Docker Compose, Config Server, Eureka,
API Gateway, Kubernetes, Prometheus, and the selective Jenkins pipeline.

## Architecture and ownership

Each REST application is maintained in its own Git repository. Its repository
contains application source, tests, Maven files, and a `Dockerfile`.

Kubernetes files do **not** belong in an application repository. All Kubernetes
manifests belong in this orchestration repository's top-level `k8s` directory:

```text
MicroServices/
  Jenkinsfile
  docker-compose.yml
  k8s/
    config.yaml
    kustomization.yaml
    <new-service>.yaml
  <new-service>/             # local checkout; no k8s folder here
    pom.xml
    Dockerfile
    src/
```

The request flow is:

```text
Client -> API Gateway -> Eureka service discovery -> REST application
                                      |
Config Server -> application settings |
Prometheus <- /actuator/prometheus    |
Logstash <- structured application logs
```

## Naming checklist

Choose one lowercase, hyphenated service name and use it consistently. This
guide uses `example-service` on port `8088`.

| Item | Example |
|---|---|
| Spring application name | `example-service` |
| Eureka registration name | `example-service` |
| Docker image | `example-service` |
| Kubernetes Service | `example-service` |
| Kubernetes Deployment | `example-service` |
| Kubernetes container | `example-service` |
| Gateway prefix | `/example-service` |
| Jenkins selection | `example-service` |
| Jenkins repository variable | `EXAMPLE_SERVICE_REPO_URL` |

Do not use `localhost` for calls between containers or pods. In Kubernetes,
`localhost` means the current pod. Use service DNS names such as `kafka:9092`,
`mysql:3306`, and `metaarch-config-server:8888`.

## 1. Create the application repository

Use Java 17 or later and Spring Boot 3. The Jenkins agent currently provides
JDK 21. A typical REST service needs these dependencies:

- `spring-boot-starter-web`
- `spring-boot-starter-validation`
- `spring-cloud-starter-config`
- `spring-cloud-starter-netflix-eureka-client`
- `spring-boot-starter-actuator`
- `micrometer-registry-prometheus`
- `spring-boot-starter-test`

Add database, Kafka, security, OpenAPI, or mail dependencies only when needed.
Import a Spring Cloud release compatible with the chosen Spring Boot version.

Use this minimal application configuration:

```yaml
spring:
  application:
    name: example-service
  config:
    import: "optional:configserver:${CONFIG_SERVER_URL:http://localhost:8888}"

eureka:
  client:
    service-url:
      defaultZone: "${EUREKA_SERVER_URL:http://localhost:8761/eureka}"

management:
  endpoints:
    web:
      exposure:
        include: health,info,prometheus
  endpoint:
    health:
      show-details: always
  metrics:
    tags:
      application: ${spring.application.name}
```

`spring.application.name` must match the Config Server filename and the
Gateway's `lb://` service ID.

### Health endpoint

Provide an internal health endpoint that verifies the web application itself
without requiring optional external systems:

```java
@RestController
@RequestMapping("/api/example")
public class ExampleController {

  @GetMapping("/health")
  public Map<String, String> health() {
    return Map.of("status", "UP");
  }
}
```

Use `/actuator/health` for Kubernetes probes only if its health contributors
are intentionally configured. Mail, Kafka, database, or other external health
contributors can make aggregate health DOWN and cause a healthy web process to
be restarted.

### Build and test locally

```powershell
.\mvnw.cmd clean verify
```

If the repository has no Maven wrapper:

```powershell
mvn clean verify
```

## 2. Add the Dockerfile

Place the `Dockerfile` at the application repository root because Jenkins runs
`docker build` from that directory:

```dockerfile
FROM eclipse-temurin:21-jre

WORKDIR /app
COPY target/*.jar app.jar

EXPOSE 8088
ENTRYPOINT ["java", "-jar", "app.jar"]
```

Add a `.dockerignore` to keep build context small:

```text
.git
.idea
.settings
.project
.classpath
src
*.md
```

Do not exclude `target`, because the Jenkins pipeline builds the JAR before it
builds the image.

Test the image:

```powershell
.\mvnw.cmd clean package
docker build -t example-service:local .
docker run --rm -p 8088:8088 `
  -e SERVER_PORT=8088 `
  -e CONFIG_SERVER_URL=http://host.docker.internal:8888 `
  -e EUREKA_SERVER_URL=http://host.docker.internal:8761/eureka `
  example-service:local
```

## 3. Add centralized application configuration

Add this file to the Config Server repository:

```text
metaarch-config-server/src/main/resources/config/example-service.yml
```

Example:

```yaml
server:
  port: ${SERVER_PORT:8088}

example:
  message: "${EXAMPLE_MESSAGE:Hello from Example Service}"

eureka:
  client:
    service-url:
      defaultZone: "${EUREKA_SERVER_URL:http://localhost:8761/eureka}"
```

Use environment-variable placeholders for values that differ by environment.
Non-secret shared values belong in `k8s/config.yaml`. Secret values must come
from a Kubernetes Secret or an external secret manager. Never commit real
passwords, tokens, private keys, SMTP credentials, or production kubeconfigs.

The Config Server uses the native classpath backend. Therefore, after adding or
changing a file under `src/main/resources/config`, rebuild and redeploy
`metaarch-config-server`.

Verify the configuration after Config Server is running:

```powershell
curl.exe http://localhost:8888/example-service/default
```

## 4. Add the API Gateway route

In
`metaarch-config-server/src/main/resources/config/api-gateway.yml`, add:

```yaml
spring:
  cloud:
    gateway:
      routes:
        - id: example-service
          uri: lb://example-service
          predicates:
            - Path=/example-service/**
          filters:
            - StripPrefix=1
```

Preserve the existing routes under the same `routes` list. With `StripPrefix=1`,
this request:

```text
GET /example-service/api/example/health
```

is forwarded to:

```text
GET /api/example/health
```

Rebuild/redeploy Config Server, then restart or redeploy the API Gateway so it
loads the updated routes. Confirm that `example-service` appears in Eureka
before testing the Gateway.

## 5. Add local Docker Compose support

Add the service under `services` in the root `docker-compose.yml`:

```yaml
  example-service:
    build:
      context: ./example-service
    image: example-service:local
    container_name: example-service
    environment:
      SERVER_PORT: 8088
      CONFIG_SERVER_URL: http://metaarch-config-server:8888
      EUREKA_SERVER_URL: http://metaarch-eureka-server:8761/eureka
      LOGSTASH_HOST: logstash
      LOGSTASH_PORT: 5000
      LOG_ENV: docker
    ports:
      - "8088:8088"
    depends_on:
      metaarch-config-server:
        condition: service_started
      metaarch-eureka-server:
        condition: service_started
      logstash:
        condition: service_started
    networks:
      - metaarch-network
```

Add MySQL or Kafka under `depends_on` only if the service uses it. Test with:

```powershell
docker compose config
docker compose build example-service
docker compose up -d example-service
docker compose logs -f example-service
```

## 6. Add the centralized Kubernetes manifest

Create `k8s/example-service.yaml` in this orchestration repository. Do not
create `example-service/k8s` in the application repository.

```yaml
apiVersion: v1
kind: Service
metadata:
  name: example-service
  namespace: metaarch
spec:
  selector:
    app: example-service
  ports:
    - name: http
      port: 8088
      targetPort: http
---
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-service
  namespace: metaarch
spec:
  replicas: 1
  selector:
    matchLabels:
      app: example-service
  template:
    metadata:
      labels:
        app: example-service
    spec:
      containers:
        - name: example-service
          image: example-service:local
          imagePullPolicy: IfNotPresent
          ports:
            - name: http
              containerPort: 8088
          env:
            - name: SERVER_PORT
              value: "8088"
          envFrom:
            - configMapRef:
                name: metaarch-config
            - secretRef:
                name: metaarch-secrets
          startupProbe:
            httpGet: {path: /api/example/health, port: http}
            periodSeconds: 10
            failureThreshold: 30
          readinessProbe:
            httpGet: {path: /api/example/health, port: http}
            periodSeconds: 10
            failureThreshold: 6
          livenessProbe:
            httpGet: {path: /api/example/health, port: http}
            periodSeconds: 20
            failureThreshold: 3
          resources:
            requests: {cpu: 200m, memory: 384Mi}
            limits: {memory: 768Mi}
```

Add the manifest to `k8s/kustomization.yaml`:

```yaml
resources:
  # existing resources...
  - example-service.yaml
```

Add only required values to `k8s/config.yaml`. Prefer explicit Spring Boot
environment variable names when a generic variable is not mapped by Config
Server. For example:

```yaml
- name: SPRING_KAFKA_BOOTSTRAP_SERVERS
  value: "kafka:9092"
```

### Probe guidance

- Startup probes allow slow initialization without premature restarts.
- Readiness probes control whether the Service sends traffic to the pod.
- Liveness probes restart a process that has become unresponsive.
- A named probe port such as `http` must match the container port name.
- Do not make liveness depend on Kafka, SMTP, Eureka, Config Server, or a remote
  API unless restarting this application can actually repair that dependency.

### Validate before deployment

```powershell
kubectl apply --dry-run=client -k k8s
kubectl kustomize k8s | Out-Null
```

For a local image:

- Docker Desktop Kubernetes may be able to use the Docker daemon's images.
- Kind requires `kind load docker-image example-service:local`.
- A remote or multi-node cluster requires an accessible registry and usually
  `PUSH_IMAGES=true` in Jenkins.

## 7. Add Prometheus monitoring

In the `spring-boot-services` scrape job in `k8s/monitoring.yaml`, add:

```yaml
- example-service:8088
```

For Docker Compose monitoring, add the same target to
`docker/prometheus/prometheus.yml`.

Verify metrics directly:

```powershell
kubectl port-forward -n metaarch service/example-service 8088:8088
curl.exe http://localhost:8088/actuator/prometheus
```

Then check Prometheus targets at `http://localhost:30090/targets`.

## 8. Register the service in Jenkins

Make three changes in the root `Jenkinsfile`.

First, add the service to the `SERVICE` parameter choices:

```groovy
'example-service'
```

Second, add it to `serviceCatalog()`:

```groovy
'example-service': [
    repositoryVariable: 'EXAMPLE_SERVICE_REPO_URL',
    image: 'example-service',
    deployment: 'example-service',
    container: 'example-service',
    manifest: 'deployment-config/k8s/example-service.yaml'
]
```

Third, configure `EXAMPLE_SERVICE_REPO_URL` as a Jenkins folder/global
environment variable containing the application's Git repository URL.

The names in `deployment`, `container`, and the Kubernetes manifest must match
exactly. Jenkins uses the image placeholder `example-service:local` when it
renders the centralized manifest with the newly built image.

Run **Build with Parameters**, select `example-service`, and choose image mode:

- Local Docker Desktop: empty `REGISTRY`, `PUSH_IMAGES=false`.
- Remote/multi-node cluster: set `REGISTRY` and `PUSH_IMAGES=true`.

The Jenkins agent needs Git, Maven or `mvnw`, JDK 21, Docker access, `kubectl`,
the configured kubeconfig credential, and registry credentials when pushing.

## 9. Deployment order

For a new service or configuration change, use this order:

1. Commit and push the application repository.
2. Add and push Config Server application configuration and Gateway route.
3. Rebuild/deploy `metaarch-config-server`.
4. Redeploy `metaarch-api-gateway` when routes changed.
5. Commit and push the centralized Kubernetes manifest and Jenkins changes.
6. Configure the new Jenkins repository URL variable.
7. Run the Jenkins job for the new service.
8. Verify the pod, Eureka registration, direct endpoint, Gateway route, and
   Prometheus target.

## 10. End-to-end verification

```powershell
kubectl get deployment,service,pod -n metaarch -l app=example-service
kubectl rollout status -n metaarch deployment/example-service --timeout=5m
kubectl logs -n metaarch deployment/example-service --tail=200
```

Check Eureka at `http://localhost:8761`, or port-forward it if necessary.

Test directly:

```powershell
kubectl port-forward -n metaarch service/example-service 8088:8088
curl.exe http://localhost:8088/api/example/health
```

Test through the Gateway:

```powershell
curl.exe http://localhost:30082/example-service/api/example/health
```

Expected response:

```json
{"status":"UP"}
```

## Troubleshooting

### `ImagePullBackOff`

The node cannot access the image. Inspect pod events:

```powershell
kubectl describe pod -n metaarch <pod-name>
```

Push the image to a reachable registry, load it into Kind, or ensure Jenkins
and Docker Desktop Kubernetes share the intended image store. Do not leave a
manifest pointing at a nonexistent `:local` image in a remote cluster.

### `CreateContainerConfigError`

Usually a referenced ConfigMap, Secret, or key is missing:

```powershell
kubectl describe pod -n metaarch <pod-name>
kubectl get configmap,secret -n metaarch
```

Declare required keys in the centralized configuration and apply them before
the Deployment. Do not solve this by committing real credentials.

### Application connects to `localhost`

Set the correct container/pod DNS address. Common values are:

```text
CONFIG_SERVER_URL=http://metaarch-config-server:8888
EUREKA_SERVER_URL=http://metaarch-eureka-server:8761/eureka
SPRING_KAFKA_BOOTSTRAP_SERVERS=kafka:9092
MYSQL_HOST=mysql
MYSQL_PORT=3306
```

### Pod runs but is not Ready

```powershell
kubectl describe pod -n metaarch <pod-name>
kubectl logs -n metaarch <pod-name> --previous
```

Confirm the probe path, port name, security rules, and whether aggregate
Actuator health is DOWN because of an unrelated external dependency.

### Gateway returns `404`

Confirm the route is in `api-gateway.yml`, Config Server and Gateway were
rebuilt/redeployed, `StripPrefix` matches the controller path, and the request
uses the configured prefix.

### Gateway returns `503`

The service is normally absent from Eureka or has no Ready instances. Check
the application's Eureka URL, `spring.application.name`, pod readiness, and the
Gateway `lb://` service ID.

### Config changes are ignored

This Config Server packages native configuration inside its image. Rebuild and
redeploy Config Server, then restart the consuming service if it does not
refresh configuration dynamically.

### Rollout times out

```powershell
kubectl get pods -n metaarch -l app=example-service -o wide
kubectl describe deployment -n metaarch example-service
kubectl describe pods -n metaarch -l app=example-service
kubectl logs -n metaarch -l app=example-service --all-containers --tail=200
```

The Jenkins pipeline performs these diagnostics automatically after a failed
rollout.

## Completion checklist

- [ ] Application name, image, Kubernetes names, and Eureka ID match.
- [ ] Maven build and tests pass.
- [ ] Root-level Dockerfile builds successfully.
- [ ] No Kubernetes directory was added to the application repository.
- [ ] Config Server has `<service-name>.yml`.
- [ ] Gateway has the route and correct `StripPrefix` behavior.
- [ ] Docker Compose entry works when local Compose support is required.
- [ ] Central `k8s/<service-name>.yaml` exists.
- [ ] `k8s/kustomization.yaml` includes the manifest.
- [ ] ConfigMap/Secret references exist and contain required keys.
- [ ] Health probes test application health, not optional dependencies.
- [ ] Prometheus scrape target is configured.
- [ ] Jenkins choice, service catalog, manifest path, and repository variable
  are configured.
- [ ] Direct and Gateway endpoints work.
- [ ] Service appears in Eureka and Prometheus.
- [ ] Real credentials are managed outside Git.

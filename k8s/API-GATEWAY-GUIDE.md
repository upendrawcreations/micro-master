# API Gateway calling guide

## Base URL

The local Kubernetes Gateway is available at:

```text
http://localhost:30082
```

Check that it is running:

```powershell
curl.exe http://localhost:30082/actuator/health
```

Expected result: JSON containing `"status":"UP"`.

The Gateway removes the first path segment before forwarding a request. For
example:

```text
/booking-system/api/houses -> booking-system:/api/houses
/org-access/api/auth/login -> org-access:/api/auth/login
```

## Currently deployed application routes

| Application | Gateway prefix | Eureka service | Kubernetes status |
|---|---|---|---|
| Org Access | `/org-access` | `org-access` | Deployed |
| Booking System | `/booking-system` | `booking-system` | Deployed |

Infrastructure such as MySQL, Elasticsearch, Logstash, Prometheus, and Grafana
is not called through the application Gateway.

## Org Access authentication

### Log in

```powershell
curl.exe -X POST "http://localhost:30082/org-access/api/auth/login" `
  -H "Content-Type: application/json" `
  -d '{"username":"admin","password":"admin123"}'
```

The response has this shape:

```json
{
  "token": "JWT_TOKEN",
  "username": "admin",
  "roles": ["ADMIN"],
  "expiresInMillis": 3600000
}
```

Store the token in PowerShell:

```powershell
$login = Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:30082/org-access/api/auth/login" `
  -ContentType "application/json" `
  -Body '{"username":"admin","password":"admin123"}'

$token = $login.token
```

These development credentials are defined in the Org Access configuration.
Change them before using the system outside local development.

### Validate a token

```powershell
curl.exe "http://localhost:30082/org-access/api/auth/validate" `
  -H "Authorization: Bearer $token"
```

### Get the current user

```powershell
curl.exe "http://localhost:30082/org-access/api/auth/me" `
  -H "Authorization: Bearer $token"
```

## Booking System

Use the Org Access JWT when calling Booking business endpoints:

```text
Authorization: Bearer <JWT_TOKEN>
```

### Houses

| Method | Gateway URL | Purpose |
|---|---|---|
| `POST` | `/booking-system/api/houses` | Create a house |
| `PUT` | `/booking-system/api/houses/{id}` | Update a house |
| `GET` | `/booking-system/api/houses/{id}` | Get one house |
| `GET` | `/booking-system/api/houses?page=0&size=10` | List houses |
| `DELETE` | `/booking-system/api/houses/{id}` | Delete a house |

Create a house:

```powershell
curl.exe -X POST "http://localhost:30082/booking-system/api/houses" `
  -H "Content-Type: application/json" `
  -d '{"name":"AMB Cinemas"}'
```

List houses:

```powershell
curl.exe "http://localhost:30082/booking-system/api/houses?page=0&size=10"
```

### Screens

| Method | Gateway URL | Purpose |
|---|---|---|
| `POST` | `/booking-system/api/screens` | Create a screen |
| `PUT` | `/booking-system/api/screens/{id}` | Update a screen |
| `GET` | `/booking-system/api/screens/{id}` | Get one screen |
| `GET` | `/booking-system/api/screens?page=0&size=10` | List screens |
| `GET` | `/booking-system/api/screens?houseId={houseId}&page=0&size=10` | List screens for a house |
| `DELETE` | `/booking-system/api/screens/{id}` | Delete a screen |

Create a screen after creating a house:

```powershell
curl.exe -X POST "http://localhost:30082/booking-system/api/screens" `
  -H "Content-Type: application/json" `
  -H "Authorization: Bearer $token" `
  -d '{"name":"Screen 1","number":1,"houseId":1}'
```

### Layouts

| Method | Gateway URL | Purpose |
|---|---|---|
| `POST` | `/booking-system/api/layouts` | Create a layout |
| `PUT` | `/booking-system/api/layouts/{id}` | Replace a layout |
| `GET` | `/booking-system/api/layouts/{id}` | Get one layout |
| `GET` | `/booking-system/api/layouts?page=0&size=10` | List layouts |
| `DELETE` | `/booking-system/api/layouts/{id}` | Delete a layout |

Example minimal layout:

```powershell
$layout = @{
  layoutName = "Weekend Premium Layout"
  screenId = 1
  sections = @(
    @{
      name = "Gold"
      price = 250.00
      order = 1
      rows = @(
        @{
          label = "A"
          rowOrder = 1
          afterGapCm = 12.5
          seats = @(
            @{
              number = 1
              position = 1
              seatTypeId = 1
              seatStatusId = 1
              bestView = $true
              afterGapCm = 0.0
            }
          )
        }
      )
    }
  )
} | ConvertTo-Json -Depth 10

Invoke-RestMethod `
  -Method Post `
  -Uri "http://localhost:30082/booking-system/api/layouts" `
  -ContentType "application/json" `
  -Body $layout
```

### Publish a booking alert event

```powershell
curl.exe -X POST "http://localhost:30082/booking-system/api/booking-alerts/publish" `
  -H "Content-Type: application/json" `
  -d '{"bookingId":"BK-1001","emailTo":"customer@example.com","customerName":"Test Customer","movieName":"Example Movie","theatreName":"AMB Cinemas","screenName":"Screen 1","showTime":"2026-07-10T18:30:00","seatNumbers":["A1","A2"],"subject":"Booking confirmed","message":"Your booking is confirmed"}'
```

This endpoint publishes an event. Delivery requires the alert-service and its
messaging dependency to be deployed and configured.

## Swagger/OpenAPI

When Gateway routing is active, use:

```text
http://localhost:30082/booking-system/swagger-ui/index.html
http://localhost:30082/booking-system/v3/api-docs
```

## Configured but not deployed routes

The Gateway configuration also contains these routes, but the corresponding
applications are not part of the current Kubernetes application manifest:

| Gateway prefix | Eureka service |
|---|---|
| `/specgeneration` | `specgeneration` |
| `/timesheet` | `timesheet-resource` |
| `/employee1` | `employee1` |
| `/leavemanagement` | `leavemanagement` |
| `/alerts-service` | `alerts-service` |
| `/theatre-management-service` | `theatre-management-service` |

Calling one of these routes will fail until that service is built, deployed,
and registered with Eureka.

## Route-loading troubleshooting

The Kubernetes Gateway is configured to require Config Server during startup.
If Config Server is temporarily unavailable, Kubernetes retries the Gateway
container instead of allowing it to start without any routes.

If a route unexpectedly returns HTTP `404`, confirm that both the Gateway and
Config Server are Ready and inspect their logs:

Useful checks:

```powershell
kubectl --insecure-skip-tls-verify=true logs -n metaarch deployment/metaarch-api-gateway
kubectl --insecure-skip-tls-verify=true logs -n metaarch deployment/metaarch-config-server
kubectl --insecure-skip-tls-verify=true get pods -n metaarch
```

# Banco XYZ - Microservicios, Resiliencia, OAuth2 y Contenedores

## Exp3 - Semana 8 · Desarrollo Backend III (PBY2203)

**Actividad sumativa:** *Desarrollando microservicios y resiliencia en la nube con Spring Cloud*

---

## Objetivo

Preparar los microservicios del Banco XYZ para un entorno cloud **seguro, resiliente y portable**:

1. **OAuth 2.0:** un Authorization Server propio emite los tokens; el Core y los tres BFF son *Resource Servers* que los validan.
2. **Docker:** cada microservicio tiene su propio `Dockerfile` (imagen multi-etapa, usuario no root, healthcheck).
3. **Docker Compose:** un único `docker-compose.yaml` levanta toda la plataforma con `docker compose up -d --build`.

Se mantienen y se integran en el mismo despliegue los requisitos de las semanas anteriores:
tolerancia a fallos con **Resilience4j**, mensajería asíncrona con **Kafka**, **Config Server** y **Eureka**.

Datos base: <https://github.com/KariVillagran/bank_legacy_data> (cuentas de `semana_1/intereses.csv` y movimientos de `semana_1/cuentas_anuales.csv`, cargados por `bank-core-api/src/main/resources/data.sql`).

---

## Estructura del código

```text
Banco-XYZ/
├── docker-compose.yaml          # Orquestación completa (11 contenedores)
├── .env.example                 # Variables / secretos de ejemplo
├── .dockerignore
├── pom.xml                      # POM padre (módulos Maven)
├── bank-common/                 # Librería compartida: errores HTTP, contrato de eventos, cliente OAuth2
├── config-server/    + Dockerfile   :8888  Spring Cloud Config (lee config-repo/)
├── config-repo/                 # Configuración centralizada del Core (Kafka, Resilience4j)
├── discovery-server/ + Dockerfile   :8761  Eureka
├── auth-server/      + Dockerfile   :9000  Spring Authorization Server (OAuth 2.0)   ← NUEVO
├── bank-core-api/    + Dockerfile   :8080  Dominio bancario, MySQL, publica eventos Kafka
├── bff-web/          + Dockerfile   :8081  Backend for Frontend Web
├── bff-mobile/       + Dockerfile   :8082  Backend for Frontend Mobile
├── bff-atm/          + Dockerfile   :8083  Backend for Frontend ATM
├── audit-service/    + Dockerfile          Consumidor Kafka de auditoría
├── scripts/smoke-test.(sh|ps1)           Prueba de humo OAuth2 + flujo completo
├── PROPUESTA_TECNICA.md         # Propuesta técnica
├── DECISIONES_ARQUITECTONICAS.md
├── DIAGRAMA_ARQUITECTURA.md
├── EVIDENCIA_EJECUCION.md       # Evidencias
└── evidencias/                  # Capturas de pantalla por semana (Evidencias S8: E01 a E19)
```

---

## Arquitectura

```text
                       1. client_credentials
   Canal (Web/Mobile/ATM) ───────────────────────►  auth-server :9000
        │   ◄──────────── access_token (JWT RS256) ───────┘   (/oauth2/token, /oauth2/jwks)
        │
        │ 2. Authorization: Bearer <token>   (scope web.access | mobile.access | atm.access)
        ▼
   BFF Web / Mobile / ATM  ── Resource Server: valida firma (JWKS), issuer, expiración y scope
        │
        │ 3. El BFF obtiene SU token (client_credentials, scope core.access) y llama al Core
        │    protegido con Resilience4j (Circuit Breaker "coreApi" + timeouts)
        ▼
   bank-core-api :8080  ── Resource Server (exige core.access) ── MySQL
        │
        │ 4. Después del COMMIT: evento validado con JSON Schema
        ▼
   Kafka (banco.movimientos, 3 particiones) ──► audit-service ×2 (grupo banco-auditoria)

   Config Server (config-repo) · Eureka · todos en la red Docker "banco-net"
```

---

## 1. OAuth 2.0

**Flujo:** `client_credentials` (comunicación servicio a servicio, el estándar para canales y backends sin usuario interactivo).
**Servidor:** `auth-server` (Spring Authorization Server). Emite JWT firmados con RSA y publica la llave pública en `/oauth2/jwks`.

| Cliente (`client_id`) | Quién lo usa | Scope | Secreto (variable) |
|---|---|---|---|
| `web-app` | Canal Web → `bff-web` | `web.access` | `WEB_CLIENT_SECRET` |
| `mobile-app` | Canal Mobile → `bff-mobile` | `mobile.access` | `MOBILE_CLIENT_SECRET` |
| `atm-app` | Cajero → `bff-atm` | `atm.access` | `ATM_CLIENT_SECRET` |
| `bff-web` | `bff-web` → Core | `core.access` | `BFF_WEB_SECRET` |
| `bff-mobile` | `bff-mobile` → Core | `core.access` | `BFF_MOBILE_SECRET` |
| `bff-atm` | `bff-atm` → Core | `core.access` | `BFF_ATM_SECRET` |

**Protección (principio de mínimo privilegio):**

| Recurso | Requiere | Resultado sin cumplirlo |
|---|---|---|
| `/api/web/**` | scope `web.access` | 401 sin token · 403 con otro scope |
| `/api/mobile/**` | scope `mobile.access` | 401 / 403 |
| `/api/atm/**` | scope `atm.access` | 401 / 403 |
| `/api/core/**` | scope `core.access` | 401 / 403 (un token de canal **no** sirve en el Core) |
| `/actuator/health` | público | — |

Todos los 401/403 usan el mismo JSON de error estándar (`ApiErrorResponse`). El claim `iss` es fijo (`AUTH_ISSUER`), por lo que los tokens son válidos tanto si se piden desde el host (`localhost:9000`) como desde la red interna de Docker.

Obtener un token manualmente:

```bash
curl -s -u atm-app:atm-secret-dev \
     -d grant_type=client_credentials -d scope=atm.access \
     http://localhost:9000/oauth2/token
```

Usarlo:

```bash
curl -H "Authorization: Bearer <access_token>" http://localhost:8083/api/atm/saldo/101
```

---

## 2. Docker

Cada microservicio tiene su `Dockerfile` (construcción desde la **raíz** del repo, porque dependen del POM padre y de `bank-common`):

- **Etapa 1 (build):** `maven:3.9-eclipse-temurin-21` compila solo el módulo y sus dependencias (`-pl <modulo> -am`), con caché de `~/.m2`.
- **Etapa 2 (runtime):** `eclipse-temurin:21-jre` solo con el JAR → imagen liviana, ejecución con usuario **no root**.
- `config-server` incluye `config-repo/` dentro de la imagen.

```bash
docker build -f bank-core-api/Dockerfile -t bancoxyz/bank-core-api .
```

---

## 3. Docker Compose

`docker-compose.yaml` orquesta **11 contenedores**:

| Servicio | Imagen | Puerto host | Depende de (healthy) |
|---|---|---|---|
| `mysql` | mysql:8.4 | 3307 | — |
| `kafka` | apache/kafka:4.3.1 | 9092 | — |
| `config-server` | build | 8888 | — |
| `discovery-server` | build | 8761 | — |
| `auth-server` | build | 9000 | — |
| `bank-core-api` | build | 8080 | mysql, kafka, config-server, discovery-server, auth-server |
| `bff-web` / `bff-mobile` / `bff-atm` | build | 8081 / 8082 / 8083 | bank-core-api, auth-server |
| `audit-service-1` / `audit-service-2` | build | — | kafka |

Características: red propia `banco-net`, `healthcheck` en cada servicio, `depends_on` con `service_healthy` (orden de arranque correcto), `restart: unless-stopped` (reinicio automático ante fallos), volúmenes persistentes para MySQL y Kafka, secretos por variables de entorno (`.env`).

---

## Requisitos

- Docker Desktop / Docker Engine **con Docker Compose v2** (`docker compose version`)
- ~6 GB de RAM libres para Docker
- Puertos libres: 3307, 8080-8083, 8761, 8888, 9000, 9092


## Ejecución

```bash

# 1. Construir y levantar todo
docker compose up -d --build

# 2. Esperar a que todos estén "healthy"
docker compose ps

# 3. Prueba de humo (OAuth2 + flujo completo con Kafka)
.\scripts\smoke-test.ps1        # Windows PowerShell
./scripts/smoke-test.sh         # Linux / macOS

# 4. Detener
docker compose down            # conserva datos
docker compose down -v         # borra también MySQL y Kafka
```

URLs útiles: Eureka <http://localhost:8761> · Config <http://localhost:8888/bank-core-api/default> · JWKS <http://localhost:9000/oauth2/jwks> · Metadata <http://localhost:9000/.well-known/oauth-authorization-server>

### Logs

```bash
docker compose logs -f bank-core-api bff-atm
docker compose logs -f audit-service-1 audit-service-2     # ver el reparto de particiones
```

### Probar resiliencia

```bash
docker compose stop bank-core-api          # el BFF responde 503 CORE_NO_DISPONIBLE, reintenta y luego rechaza llamadas (circuito abierto)
curl -s "http://localhost:8083/actuator/metrics/resilience4j.circuitbreaker.state?tag=name:coreApi&tag=state:open"
docker compose start bank-core-api         # al volver el Core, las consultas responden 200 y el circuito queda CLOSED

docker compose stop kafka                  # el retiro sigue respondiendo 200; el Core registra "Kafka no disponible" (la publicación es asíncrona)
docker compose start kafka
```

---

## Ejecución local sin Docker (desarrollo)

Cada servicio mantiene valores por defecto apuntando a `localhost`: levantar MySQL, Kafka (`docker-compose.kafka.yml`), y luego con `./mvnw -pl <modulo> spring-boot:run` en este orden: `config-server`, `discovery-server`, `auth-server`, `bank-core-api`, BFFs, `audit-service`.
Variables necesarias: `DB_PASSWORD` (Core) y, para HTTPS en BFF, `SSL_KEYSTORE_PATH` / `SSL_KEYSTORE_PASSWORD` (o `SSL_ENABLED=false`).


## Compilar y probar

```bash
./mvnw clean verify          # 9 módulos + pruebas unitarias
```

Pruebas: contrato de eventos, consumidor idempotente de auditoría, cliente OAuth2 (`ClientCredentialsTokenProviderTest`) y Retry/Bulkhead (`ResilientCallTest`).

---

## Funcionalidades mantenidas (resumen)

- **Resilience4j** (Circuit Breaker + Retry + Bulkhead + timeouts):

  | Servicio | Protección | Detalle |
  |---|---|---|
  | `bff-web`, `bff-mobile`, `bff-atm` → Core | **Circuit Breaker** `coreApi` | ventana 3 llamadas, umbral 50 %, 10 s en OPEN, medio abierto automático; ignora errores funcionales (404/409/4xx) |
  | | **Retry** | 3 intentos, 300 ms; solo fallos transitorios (timeout, conexión, 5xx, falla de token). **No** reintenta el retiro (POST no idempotente) |
  | | **Bulkhead** | máx. 10 llamadas concurrentes al Core; el exceso se rechaza en 100 ms |
  | | **Timeouts** | 2 s conexión / 3 s lectura |
  | `bank-core-api` → Kafka | **Circuit Breaker** `kafkaPublisher` | la publicación se hace en un hilo propio: el retiro sigue respondiendo 200 y el fallo se registra en el Core (`Kafka no disponible: evento ... no publicado`); `max.block.ms=3000` |

  Composición: `CircuitBreaker( Retry( Bulkhead( llamada ) ) )`. El estado del circuito se consulta como métrica `resilience4j.circuitbreaker.state` en `/actuator/metrics`.
- **Kafka:** tópico `banco.movimientos` (3 particiones, clave = `cuentaId`), publicación **después del COMMIT**, contrato JSON Schema, productor idempotente, `audit-service` con idempotencia por `eventId` y 2 instancias en el mismo grupo.
- **Errores y validaciones:** respuesta de error única, Bean Validation antes de la transacción, DTOs separados de entidades.
- **Config Server + Eureka:** configuración centralizada del Core y registro de servicios.

Detalle en `PROPUESTA_TECNICA.md` y `DECISIONES_ARQUITECTONICAS.md`.

## Tecnologías

Java 21 · Spring Boot 4.0.7 · Spring Cloud 2025.1.2 · Spring Security (OAuth2 Resource Server) · Spring Authorization Server · Resilience4j · Apache Kafka · MySQL 8.4 · Docker / Docker Compose · Maven

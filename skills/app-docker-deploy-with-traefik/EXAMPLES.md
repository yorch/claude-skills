# Deployment Examples

Real-world examples of Docker + Traefik deployments.

## Example 1: Express.js API with PostgreSQL

### docker-compose.yml

```yaml
services:
  app:
    build: .
    restart: unless-stopped
    environment:
      - NODE_ENV=${NODE_ENV}
      - PORT=${PORT}
      - DATABASE_URL=${DATABASE_URL}
    depends_on:
      db:
        condition: service_healthy

  db:
    image: postgres:17-alpine
    restart: unless-stopped
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
    healthcheck:
      test: pg_isready -U "$$POSTGRES_USER" -d "$$POSTGRES_DB"
      interval: 10s
      timeout: 2s
      retries: 10
```

### docker-compose.for-traefik.yml

```yaml
services:
  app:
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.services.my-api.loadbalancer.server.port=3000'
      - 'traefik.http.routers.my-api.rule=Host(`api.example.com`)'
      - 'traefik.http.routers.my-api.entrypoints=websecure'
      - 'traefik.http.routers.my-api.tls=true'
      - 'traefik.http.routers.my-api.tls.certResolver=webcert'
      - 'traefik.http.routers.my-api.service=my-api'

  db:
    networks:
      - default

networks:
  traefik:
    external: true
```

## Example 2: Python FastAPI with Redis

### docker-compose.yml

```yaml
services:
  app:
    build: .
    restart: unless-stopped
    environment:
      - REDIS_URL=redis://redis:6379
      - DATABASE_URL=${DATABASE_URL}
    depends_on:
      - redis
      - db

  redis:
    image: redis:8-alpine
    restart: unless-stopped
    volumes:
      - ./data/redis:/data
    command: ['redis-server', '--save', '60', '1']

  db:
    image: postgres:17-alpine
    restart: unless-stopped
    volumes:
      - ./data/postgres:/var/lib/postgresql/data
    environment:
      - POSTGRES_DB=${POSTGRES_DB}
      - POSTGRES_USER=${POSTGRES_USER}
      - POSTGRES_PASSWORD=${POSTGRES_PASSWORD}
```

### docker-compose.for-traefik.yml

```yaml
services:
  app:
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.services.fastapi-app.loadbalancer.server.port=8000'
      - 'traefik.http.routers.fastapi-app.rule=Host(`${DOMAIN}`)'
      - 'traefik.http.routers.fastapi-app.entrypoints=websecure'
      - 'traefik.http.routers.fastapi-app.tls=true'
      - 'traefik.http.routers.fastapi-app.tls.certResolver=webcert'

  redis:
    networks:
      - default

  db:
    networks:
      - default

networks:
  traefik:
    external: true
```

## Example 3: Full-Stack (Frontend + Backend on Same Domain)

### docker-compose.for-traefik.yml

```yaml
services:
  frontend:
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.services.myapp-frontend.loadbalancer.server.port=80'
      - 'traefik.http.routers.myapp-frontend.rule=Host(`${DOMAIN}`)'
      - 'traefik.http.routers.myapp-frontend.entrypoints=websecure'
      - 'traefik.http.routers.myapp-frontend.tls=true'
      - 'traefik.http.routers.myapp-frontend.tls.certResolver=webcert'

  backend:
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.services.myapp-backend.loadbalancer.server.port=3000'
      # API routes go to backend
      - 'traefik.http.routers.myapp-backend.rule=Host(`${DOMAIN}`) && PathPrefix(`/api`)'
      - 'traefik.http.routers.myapp-backend.entrypoints=websecure'
      - 'traefik.http.routers.myapp-backend.tls=true'
      - 'traefik.http.routers.myapp-backend.tls.certResolver=webcert'

  db:
    networks:
      - default

networks:
  traefik:
    external: true
```

## Example 4: With Basic Auth Protection

```yaml
services:
  app:
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      # Basic Auth Middleware
      - 'traefik.http.middlewares.admin-auth.basicauth.users=${USERNAME}:${HASHED_PASSWORD}'
      # Service
      - 'traefik.http.services.admin-panel.loadbalancer.server.port=8080'
      # HTTPS Host with auth middleware
      - 'traefik.http.routers.admin-panel.rule=Host(`admin.${DOMAIN}`)'
      - 'traefik.http.routers.admin-panel.entrypoints=websecure'
      - 'traefik.http.routers.admin-panel.tls=true'
      - 'traefik.http.routers.admin-panel.tls.certResolver=webcert'
      - 'traefik.http.routers.admin-panel.middlewares=admin-auth@docker'

networks:
  traefik:
    external: true
```

## Example 5: Pre-built Image (No Dockerfile)

```yaml
services:
  app:
    image: ghcr.io/myorg/myapp:v1.2.3
    restart: unless-stopped
    networks:
      - default
      - traefik
    labels:
      - 'traefik.enable=true'
      - 'traefik.docker.network=traefik'
      - 'traefik.http.services.myapp.loadbalancer.server.port=8080'
      - 'traefik.http.routers.myapp.rule=Host(`${DOMAIN}`)'
      - 'traefik.http.routers.myapp.entrypoints=websecure'
      - 'traefik.http.routers.myapp.tls=true'
      - 'traefik.http.routers.myapp.tls.certResolver=webcert'

networks:
  traefik:
    external: true
```

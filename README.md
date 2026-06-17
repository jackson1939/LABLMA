# SGC — Sistema de Gestión de Calidad

**Sistema integral open-source para la gestión de calidad ISO 9001, ISO 17025, ISO 14001 e ISO 45000.**

Documentos, no conformidades, riesgos, planes de acción, dashboard con KPIs y notificaciones multicanal. Diseñado para PYMES, laboratorios y organismos de certificación que necesitan un SGC robusto sin pagar licencias SaaS.

---

## Índice

- [Stack tecnológico](#stack-tecnológico)
- [Módulos funcionales](#módulos-funcionales)
- [Arquitectura](#arquitectura)
- [Quick Start (desarrollo local)](#quick-start-desarrollo-local)
- [Setup producción (servidor local)](#setup-producción-servidor-local)
  - [Requisitos del servidor](#requisitos-del-servidor)
  - [Instalación 1 comando](#instalación-1-comando)
  - [Auto-deploy desde GitHub](#auto-deploy-desde-github)
  - [Acceso externo con Cloudflare Tunnel](#acceso-externo-con-cloudflare-tunnel)
- [Comandos del sistema](#comandos-del-sistema)
- [API REST](#api-rest)
- [Workflow de desarrollo diario](#workflow-de-desarrollo-diario)
- [Docker](#docker)
- [Variables de entorno](#variables-de-entorno)
- [Licencia](#licencia)

---

## Stack tecnológico

| Capa | Tecnología | Versión |
|------|-----------|---------|
| **Frontend** | Next.js (App Router) + TypeScript | 14.2 / 5.4 |
| **Estilos** | Tailwind CSS + class-variance-authority | 3.4 |
| **Gráficos** | Recharts | 2.12 |
| **Iconos** | Lucide React | 0.378 |
| **Backend** | FastAPI + Python | 0.111 / 3.12 |
| **ORM** | SQLAlchemy 2.0 (async) + Pydantic | 2.0 / 2.7 |
| **Base de datos** | PostgreSQL 15 / SQLite (dev) | |
| **Autenticación** | JWT (HS256) + bcrypt | 8h expiración |
| **PDF** | WeasyPrint + Jinja2 | |
| **Notificaciones** | SMTP (fastapi-mail) + WhatsApp Cloud API (Meta) | |
| **Tareas programadas** | APScheduler | 3.10 |
| **Infraestructura** | PowerShell scripts + cloudflared + Windows Service | |

---

## Módulos funcionales

| Módulo | Descripción |
|--------|-------------|
| **Documentos** | Ciclo de vida completo: borrador → revisión → vigente → obsoleto. Control de versiones, lista maestra, editor WYSIWYG con autoguardado, historial de cambios, flujo de aprobación multi-rol |
| **No Conformidades** | Registro de NC con máquina de estados: abierta → análisis → plan aprobado → ejecución → cerrada/vencida. Acciones correctivas vinculadas, alertas de vencimiento |
| **Riesgos** | Matriz probabilidad(1-5) × impacto(1-5) = nivel(1-25). Mapa de calor, tratamiento con plan de acción. Clasificación automática por nivel |
| **Planes y Programas** | Planes con ISO y año fiscal. Diagrama Gantt con tareas, responsables, fechas y progreso (0-100%). Aprobación multi-rol |
| **Dashboard** | KPIs en tiempo real, gráficos de torta (NC por tipo), barras (documentos por estado), alertas de próximos vencimientos. Auto-refresh |
| **Notificaciones** | Multicanal: in-app (campana con contador), email (SMTP), WhatsApp (Meta Cloud API). Notificaciones al asignar NC, aprobar documentos, vencimientos |
| **Usuarios y Roles** | 6 roles con matriz de permisos granular: admin, director, responsable, verificador, elaborador, consultor. CRUD completo solo admin |

### Estados de negocio

```
Documento:    borrador → en_revision → vigente → obsoleto
NC:           abierta → en_analisis → plan_aprobado → en_ejecucion → cerrada / vencida
PlanAcción:   pendiente → en_curso → completada
Riesgo:       activo → mitigado → aceptado
PlanPrograma: borrador → aprobado → en_ejecucion → completado
```

---

## Arquitectura

```
┌────────────────────────────────────────────────────────┐
│                    NAVEGADOR                            │
│           http://localhost:3000 / https://lablma.com     │
└─────────────────────┬──────────────────────────────────┘
                      │  /api/* → proxy (mismo origen)
                      │  / → React Server Components
┌─────────────────────▼──────────────────────────────────┐
│              NEXT.JS (App Router)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │ Páginas      │  │ API Rewrites  │  │ Static Assets │  │
│  │ + RSC        │  │ /api/* → BE   │  │               │  │
│  └─────────────┘  └──────┬───────┘  └──────────────┘  │
└──────────────────────────┼────────────────────────────┘
                           │  proxy (server-side)
┌──────────────────────────▼────────────────────────────┐
│              FASTAPI (Backend)                         │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ Auth     │ │ Doc.     │ │ NC       │ │ Riesgos  │ │
│  │ /auth    │ │ /doc.    │ │ /nc      │ │ /riesgos │ │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│  │ Planes   │ │ Dashboard│ │ Notif.   │ │ Scheduler│ │
│  │ /planes  │ │ /kpis    │ │ /notif   │ │ APSch.   │ │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ │
└──────────────────────┬────────────────────────────────┘
                       │  SQLAlchemy async
┌──────────────────────▼────────────────────────────────┐
│              BASE DE DATOS                              │
│         SQLite (dev) / PostgreSQL 15 (prod)             │
└────────────────────────────────────────────────────────┘
```

### Infraestructura de producción

```
┌──────────────────────────────────────────────────┐
│  SERVIDOR (Windows)                               │
│                                                    │
│  ┌────────┐  ┌────────┐  ┌──────────┐  ┌──────┐  │
│  │Backend  │  │Frontend│  │ Monitor   │  │Tunnel│  │
│  │:8000    │  │:3000   │  │health+git │  │CF    │  │
│  └────────┘  └────────┘  └──────────┘  └──────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐  │
│  │ Windows Service (SGC-Server, arranque auto)   │  │
│  └──────────────────────────────────────────────┘  │
└──────────────────┬───────────────────────────────┘
                   │
    ┌──────────────┴──────────────┐
    │  LAN           │  Internet  │
    │  192.168.x.x   │  lablma.com│
    │  WiFi          │  Tunnel CF │
    └─────────────────────────────┘
```

---

## Quick Start (desarrollo local)

### Requisitos

- Python 3.12+ con `venv`
- Node.js 20+
- Git

### 1. Clonar e instalar

```bash
git clone https://github.com/jackson1939/LABLMA.git sgc
cd sgc

# Backend
cd backend
python -m venv venv
.\venv\Scripts\pip install -r requirements.txt
cd ..

# Frontend
cd frontend
npm install
cd ..

# Raíz
npm install
```

### 2. Configurar variables

```bash
copy .env.example backend\.env
copy frontend\.env.local.example frontend\.env.local
```

Editar `backend\.env` si usas PostgreSQL (por defecto SQLite local).

### 3. ¡Un solo comando!

```bash
npm run dev
```

Esto ejecuta migraciones → seed → backend (hot-reload) → frontend simultáneamente.

### 4. Abrir

| URL | Descripción |
|-----|-------------|
| http://localhost:3000 | Aplicación |
| http://localhost:8000/docs | Documentación API (Swagger) |
| http://localhost:8000/redoc | Documentación API (Redoc) |

### Usuarios demo

| Email | Contraseña | Rol |
|-------|-----------|-----|
| admin@sgc.local | Admin1234! | Administrador |
| director@sgc.local | Director1234! | Director |
| responsable@sgc.local | Resp1234! | Responsable |
| verificador@sgc.local | Verif1234! | Verificador |
| elaborador@sgc.local | Elab1234! | Elaborador |

---

## Setup producción (servidor local)

Sistema completo de auto-despliegue para servidor Windows con acceso LAN y externo.

### Requisitos del servidor

- Windows 10/11 o Windows Server 2019+
- 2 GB RAM (mínimo), 1 TB NVMe recomendado (para 30-50 usuarios)
- Node.js 20+, Python 3.12+, Git
- PowerShell 5.1+ (ejecutar como Administrador)

### Instalación 1 comando

```powershell
# 1. Abrir PowerShell como ADMINISTRADOR
# 2. En la carpeta del proyecto:
cd C:\sgc

npm run infra:setup
```

El wizard guía paso a paso:

| Paso | Descripción |
|------|-------------|
| 1. Requisitos | Verifica Node.js, Python, Git |
| 2. Red | Detecta IP LAN, abre puertos en firewall (3000, 8000) |
| 3. Entorno Python | Crea venv, instala dependencias |
| 4. Frontend | Instala npm, build producción |
| 5. BD | Migraciones automáticas + seed datos demo |
| 6. Servicio Windows | Instala tarea programada "SGC-Server" (inicio automático) |
| 7. Git remote | Configura el remoto para auto-deploy |
| 8. Cloudflare Tunnel | Opcional — login + crear túnel para acceso externo |

Después del setup, iniciar con:

```powershell
npm start
```

### Auto-deploy desde GitHub

Sincronización automática cuando codeas desde cualquier lugar:

```
LAPTOP (tú)                        SERVIDOR (producción)
─────────────────                  ─────────────────────
código → git commit
         git push
                  ─────────►       monitor detecta cambio
                                   git pull
                                   alembic upgrade head
                                   npm run build
                                   restart services
                                   ✅ cambios vivos
```

**Comando rápido desde la laptop:**

```bash
npm run sync          # add + commit + push (pide mensaje)
npm run sync:push     # igual
npm run sync:status   # ver estado del git
npm run sync:log      # ver historial de deploys
```

### Acceso externo con Cloudflare Tunnel

Para acceder desde fuera de tu red local sin abrir puertos en el router:

```powershell
npm run infra:tunnel:install   # Descarga cloudflared
npm run infra:tunnel:login     # Autenticación (abre navegador)
npm run infra:tunnel:create    # Crea tunnel + configura DNS
npm run infra:tunnel:start     # Inicia el túnel
npm run infra:tunnel:status    # Ver estado
```

Después de crear el tunnel, agregar estos registros en el panel DNS de Cloudflare:

| Tipo | Nombre | Valor |
|------|--------|-------|
| CNAME | `lablma.com` | `<tunnel-id>.cfargotunnel.com` |
| CNAME | `api.lablma.com` | `<tunnel-id>.cfargotunnel.com` |

---

## Comandos del sistema

### Desarrollo

| Comando | Descripción |
|---------|-------------|
| `npm run dev` | Inicia backend + frontend con hot-reload |
| `npm run dev:backend` | Solo backend (uvicorn --reload) |
| `npm run dev:frontend` | Solo frontend (next dev) |
| `npm run migrate` | Ejecuta migrations (alembic) |
| `npm run seed` | Pobla la BD con datos demo |

### Producción

| Comando | Descripción |
|---------|-------------|
| `npm start` | Inicia servidor producción (start-server.ps1) |
| `npm stop` | Detiene servicios |
| `npm run status` | Muestra estado de backend/frontend/servicio |
| `npm run backup` | Backup de la base de datos |
| `npm run infra:start` | Inicia server + tunnel + monitor |
| `npm run infra:deploy` | Forzar deploy manual (pull + build + restart) |
| `npm run infra:monitor` | Monitor de salud (health check + auto-restart + git poller) |

### Infraestructura

| Comando | Descripción |
|---------|-------------|
| `npm run infra:setup` | Wizard completo de instalación |
| `npm run infra:setup:quick` | Setup rápido (sin tunnel) |
| `npm run infra:tunnel:start` | Iniciar túnel Cloudflare |
| `npm run infra:tunnel:stop` | Detener túnel |
| `npm run infra:tunnel:status` | Estado del túnel |
| `npm run infra:tunnel:uninstall` | Eliminar túnel y config |
| `npm run infra:webhook:start` | Iniciar receptor webhook GitHub |

---

## API REST

Prefijo: `/api/v1`. Documentación interactiva en `/docs` (Swagger).

| Módulo | Endpoints principales |
|--------|----------------------|
| **Auth** | `POST /auth/login`, `GET /auth/me`, `POST /auth/refresh` |
| **Usuarios** | CRUD `/usuarios` (solo admin) |
| **Documentos** | CRUD, `POST /{id}/enviar-revision`, `/aprobar`, `/rechazar`, `/dar-de-baja`, GET `/{id}/versiones` |
| **No Conformidades** | CRUD, `POST /{id}/analisis`, `/aprobar-plan`, `/cerrar`, `/validar-cierre`, CRUD `/planes-accion` |
| **Riesgos** | CRUD, `GET /matriz` (datos para heat map) |
| **Planes** | CRUD, `POST /{id}/aprobar`, CRUD `/tareas` |
| **Dashboard** | `GET /kpis`, `/documentos`, `/nc`, `/alertas` |
| **Notificaciones** | `GET /`, `POST /{id}/leer`, `POST /leer-todas` |
| **Scheduler** | `GET /scheduler/run-jobs?cron_secret=...` |

### Autenticación

JWT Bearer token. Obtener en `POST /auth/login`, enviar en header `Authorization: Bearer <token>`.

Roles con matriz de permisos: `admin` > `director` > `responsable` > `verificador` > `elaborador` > `consultor`.

---

## Workflow de desarrollo diario

### En la oficina (misma red)

```bash
# Código y pruebas en local
npm run dev
# Abrir: http://localhost:3000

# Cuando algo está listo, desplegar al servidor local:
npm run infra:deploy
```

### Fuera de la oficina (laptop)

```bash
# 1. Hacer cambios en el código
# 2. Sincronizar:
npm run sync
# 3. Esperar ~30s (el monitor detecta y despliega)
# 4. Verificar en: https://lablma.com
```

### Despliegue manual forzado

```bash
npm run infra:deploy
```

---

## Docker

```bash
docker-compose up --build
```

Levanta PostgreSQL + backend + frontend. Editar `docker-compose.yml` para ajustar puertos y variables.

---

## Variables de entorno

### Backend (`backend/.env`)

| Variable | Descripción | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Conexión BD | `sqlite+aiosqlite:///../data/sgc.db` |
| `SECRET_KEY` | Key para JWT (min 32 chars) | |
| `ALGORITHM` | Algoritmo JWT | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Expiración token | `480` |
| `SMTP_*` | Configuración de correo | |
| `WHATSAPP_*` | Meta Cloud API | |
| `FRONTEND_URL` | URL del frontend para CORS | `http://localhost:3000` |
| `ENVIRONMENT` | `development` / `production` | `development` |
| `CRON_SECRET` | Secreto para endpoint scheduler | |

### Frontend (`frontend/.env.local`)

| Variable | Descripción | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | URL base de la API | `/api/v1` (relativa, proxy por Next.js) |
| `NEXT_PUBLIC_APP_NAME` | Nombre de la aplicación | `SGC - Sistema de Gestión de Calidad` |

---

## Estructura del proyecto

```
sgc/
├── frontend/                # Next.js 14 App Router
│   └── src/
│       ├── app/             # Rutas (auth) y (dashboard)
│       ├── components/      # UI, layout, módulos
│       ├── hooks/           # useAuth, useDocumentos, etc.
│       ├── lib/             # api.ts, auth.ts, utils.ts
│       └── types/           # Interfaces TypeScript
├── backend/                 # FastAPI
│   └── app/
│       ├── models/          # 9 modelos SQLAlchemy
│       ├── schemas/         # Pydantic request/response
│       ├── routers/         # 7 módulos (~40 endpoints)
│       ├── services/        # email, whatsapp, pdf, scheduler
│       ├── utils/           # permisos, helpers
│       └── templates/pdf/   # Jinja2 para generación PDF
├── scripts/
│   ├── infra/               # 🚀 Sistema de infraestructura
│   │   ├── setup.ps1        # Wizard instalación (1 comando)
│   │   ├── network.ps1      # Detección LAN + firewall
│   │   ├── deploy.ps1       # Pipeline deploy
│   │   ├── sync.ps1         # Git sync commands
│   │   ├── tunnel.ps1       # Cloudflare Tunnel
│   │   ├── monitor.ps1      # Health check + auto-deploy
│   │   ├── webhook-server.py# Receptor webhook GitHub
│   │   └── config.json      # Configuración central
│   ├── start-server.ps1     # Iniciar producción
│   ├── stop-server.ps1      # Detener servicios
│   ├── install-service.ps1  # Instalar servicio Windows
│   └── backup.ps1           # Backup BD
├── data/                    # SQLite local (dev)
├── logs/                    # Logs de servicios
├── start.ps1                # Entry point unificado
└── docker-compose.yml       # PostgreSQL + backend + frontend
```

---

## Licencia

MIT — Open Source. Uso personal, educativo y comercial permitido.

Contribuciones, issues y pull requests bienvenidos.

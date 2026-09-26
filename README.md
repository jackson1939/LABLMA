# LABLMA — SGC · Sistema de Gestión de Calidad

**Plataforma integral open-source para gestionar Sistemas de Gestión de Calidad bajo ISO 9001, ISO 17025, ISO 14001 e ISO 45001.**

Documentos controlados, no conformidades, riesgos, planes de acción, dashboard con KPIs y notificaciones multicanal — todo en una sola aplicación web, pensada para PYMES, laboratorios y organismos de certificación que necesitan un SGC robusto sin pagar licencias SaaS.

🌐 **Idioma / Language:** [Español](#español) | [English](#english)

---

<a name="español"></a>

## Español

### Índice

- [Descripción general](#descripción-general)
- [Características principales](#características-principales)
- [Stack tecnológico](#stack-tecnológico)
- [Arquitectura](#arquitectura)
- [Estructura del proyecto](#estructura-del-proyecto)
- [Requisitos previos](#requisitos-previos)
- [Instalación y configuración](#instalación-y-configuración)
- [Uso](#uso)
- [API REST](#api-rest)
- [Despliegue en producción](#despliegue-en-producción)
- [Docker](#docker)
- [Variables de entorno](#variables-de-entorno)
- [Estado del proyecto y roadmap](#estado-del-proyecto-y-roadmap)
- [Licencia](#licencia)
- [Autor / Contacto](#autor--contacto)

---

### Descripción general

**LABLMA (SGC)** es un sistema de gestión de calidad web full-stack que digitaliza los procesos que exigen normas como ISO 9001, ISO 17025, ISO 14001 e ISO 45001: control documental, gestión de no conformidades, análisis de riesgos, planes de acción y programas, y reporting ejecutivo mediante un dashboard con KPIs en tiempo real.

Está orientado a organizaciones que hoy gestionan su SGC en hojas de cálculo o carpetas compartidas — PYMES, laboratorios de ensayo/calibración y organismos de certificación — y necesitan trazabilidad, control de versiones y flujos de aprobación auditable, sin el costo recurrente de una suite SaaS de calidad.

El proyecto incluye, además de la aplicación, un **stack de infraestructura propio** (scripts de PowerShell) para desplegar y mantener el sistema corriendo de forma autónoma en un servidor Windows local, con auto-deploy desde GitHub y acceso externo vía Cloudflare Tunnel — pensado para organizaciones sin equipo de DevOps dedicado.

### Características principales

- **Gestión documental** con ciclo de vida completo: `borrador → en_revisión → vigente → obsoleto`. Incluye control de versiones, lista maestra de documentos, editor WYSIWYG (TipTap) con autoguardado, historial de cambios y flujo de aprobación multi-rol.
- **No conformidades (NC)** con máquina de estados: `abierta → en_análisis → plan_aprobado → en_ejecución → cerrada / vencida`. Acciones correctivas vinculadas y alertas automáticas de vencimiento.
- **Gestión de riesgos** mediante matriz probabilidad (1-5) × impacto (1-5) = nivel (1-25), con mapa de calor visual, planes de tratamiento y clasificación automática por nivel de criticidad.
- **Planes y programas** anuales vinculados a norma ISO y año fiscal, con diagrama tipo Gantt (tareas, responsables, fechas, progreso 0-100%) y aprobación multi-rol.
- **Dashboard ejecutivo** con KPIs en tiempo real, gráficos de torta (NC por tipo) y barras (documentos por estado), alertas de próximos vencimientos y auto-refresh.
- **Notificaciones multicanal**: in-app (campana con contador), email (SMTP vía `fastapi-mail`) y WhatsApp (Meta Cloud API) — se disparan al asignar una NC, aprobar documentos o ante vencimientos próximos.
- **Usuarios y roles**: 6 roles con matriz de permisos granular (`admin`, `director`, `responsable`, `verificador`, `elaborador`, `consultor`), con CRUD de usuarios restringido a administradores.
- **Generación de PDF** de documentos y reportes mediante WeasyPrint + Jinja2.
- **Tareas programadas** (recordatorios de vencimiento, limpieza, etc.) con APScheduler, ejecutables también vía endpoint protegido para cron externos (p. ej. Vercel Cron).
- **Infraestructura autogestionada**: wizard de instalación en un solo comando, servicio de Windows con arranque automático, monitor de salud con auto-restart, auto-deploy al hacer `git push`, y túnel Cloudflare para exponer el sistema a internet sin abrir puertos en el router.

#### Estados de negocio

```
Documento:     borrador → en_revision → vigente → obsoleto
No conformidad: abierta → en_analisis → plan_aprobado → en_ejecucion → cerrada / vencida
Plan de acción: pendiente → en_curso → completada
Riesgo:         activo → mitigado → aceptado
Plan/Programa:  borrador → aprobado → en_ejecucion → completado
```

### Stack tecnológico

| Capa | Tecnología | Versión |
|------|-----------|---------|
| **Frontend** | Next.js (App Router) + TypeScript | 14.2 / 5.4 |
| **Estilos** | Tailwind CSS + class-variance-authority | 3.4 |
| **Editor de texto enriquecido** | TipTap (extensiones de tabla, imagen, links, etc.) | 3.27 |
| **Gráficos** | Recharts | 2.12 |
| **Iconos** | Lucide React | 0.378 |
| **Cliente HTTP (frontend)** | Axios | 1.7 |
| **Backend** | FastAPI + Python | 0.111 / 3.12 |
| **ORM** | SQLAlchemy 2.0 (async) + Alembic (migraciones) | 2.0 / 1.13 |
| **Validación** | Pydantic + Pydantic Settings | 2.7 / 2.3 |
| **Base de datos** | PostgreSQL 15 (producción) / SQLite + aiosqlite (desarrollo) | |
| **Autenticación** | JWT (HS256) vía `python-jose` + `bcrypt`/`passlib` | expiración configurable (default 8h) |
| **Generación de PDF** | WeasyPrint + Jinja2 | |
| **Notificaciones** | SMTP (`fastapi-mail`) + WhatsApp Cloud API (Meta) | |
| **Cliente HTTP (backend)** | httpx | |
| **Tareas programadas** | APScheduler | 3.10 |
| **Contenedores** | Docker + Docker Compose | |
| **Infraestructura** | Scripts PowerShell (setup, deploy, sync, monitor, tunnel) + cloudflared + Windows Service | |

### Arquitectura

```
┌────────────────────────────────────────────────────────┐
│                    NAVEGADOR                            │
│           http://localhost:3000 / https://lablma.com    │
└─────────────────────┬──────────────────────────────────┘
                       │  /api/* → proxy (mismo origen)
                       │  / → React Server Components
┌─────────────────────▼──────────────────────────────────┐
│              NEXT.JS (App Router)                       │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐   │
│  │ Páginas      │  │ API Rewrites │  │ Static Assets │   │
│  │ + RSC        │  │ /api/* → BE  │  │               │   │
│  └─────────────┘  └──────┬───────┘  └──────────────┘   │
└──────────────────────────┼──────────────────────────────┘
                            │  proxy (server-side)
┌──────────────────────────▼──────────────────────────────┐
│              FASTAPI (Backend)                           │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Auth     │ │ Doc.     │ │ NC       │ │ Riesgos  │    │
│  │ /auth    │ │ /docs.   │ │ /nc      │ │ /riesgos │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Planes   │ │ Dashboard│ │ Notif.   │ │ Scheduler│    │
│  │ /planes  │ │ /kpis    │ │ /notif   │ │ APSch.   │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
└──────────────────────┬────────────────────────────────┘
                        │  SQLAlchemy async
┌──────────────────────▼────────────────────────────────┐
│              BASE DE DATOS                              │
│         SQLite (dev) / PostgreSQL 15 (prod)             │
└──────────────────────────────────────────────────────────┘
```

**Infraestructura de producción (servidor Windows local):**

```
┌──────────────────────────────────────────────────┐
│  SERVIDOR (Windows)                               │
│                                                    │
│  ┌────────┐  ┌────────┐  ┌──────────┐  ┌──────┐  │
│  │Backend │  │Frontend│  │ Monitor  │  │Tunnel│  │
│  │:8000   │  │:3000   │  │health+git│  │CF    │  │
│  └────────┘  └────────┘  └──────────┘  └──────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ Windows Service (SGC-Server, arranque auto)   │ │
│  └──────────────────────────────────────────────┘ │
└──────────────────┬───────────────────────────────┘
                    │
      ┌─────────────┴──────────────┐
      │  LAN            │ Internet │
      │  192.168.x.x    │  túnel   │
      │  WiFi           │  CF      │
      └─────────────────────────────┘
```

### Estructura del proyecto

```
LABLMA/
├── frontend/                  # Next.js 14 (App Router) + TypeScript
│   └── src/
│       ├── app/                # Rutas: grupos (auth) y (dashboard)
│       ├── components/         # Componentes UI, layout y por módulo
│       ├── hooks/               # useAuth, useDocumentos, etc.
│       ├── lib/                  # api.ts, auth.ts, utils.ts
│       └── types/                 # Interfaces TypeScript compartidas
├── backend/                   # FastAPI
│   ├── alembic/                 # Migraciones de base de datos
│   └── app/
│       ├── auth/                 # Router y lógica de autenticación (JWT)
│       ├── models/               # 10 modelos SQLAlchemy (usuario, documento, NC, riesgo, planes...)
│       ├── schemas/              # Esquemas Pydantic (request/response)
│       ├── routers/              # 8 routers (~40 endpoints) bajo /api/v1
│       ├── services/             # email, whatsapp, pdf, scheduler, libreoffice
│       ├── templates/pdf/        # Plantillas Jinja2 para generación de PDF
│       ├── seed.py               # Datos demo (usuarios, documentos, NC de ejemplo)
│       ├── config.py              # Configuración vía variables de entorno
│       └── main.py                # Entry point de la app FastAPI
├── scripts/
│   ├── infra/                   # Sistema de infraestructura y auto-deploy
│   │   ├── setup.ps1              # Wizard de instalación (1 comando)
│   │   ├── network.ps1            # Detección de IP LAN + reglas de firewall
│   │   ├── deploy.ps1             # Pipeline de despliegue
│   │   ├── sync.ps1               # Comandos de sincronización Git
│   │   ├── tunnel.ps1             # Gestión de Cloudflare Tunnel
│   │   ├── monitor.ps1            # Health check + auto-restart + git poller
│   │   ├── webhook-server.py     # Receptor de webhooks de GitHub
│   │   └── config.json            # Configuración central de infraestructura
│   ├── start-server.ps1          # Arranque de producción
│   ├── stop-server.ps1           # Detención de servicios
│   ├── install-service.ps1       # Instalación como servicio de Windows
│   └── backup.ps1                # Backup de la base de datos
├── boot.ps1 / start.ps1          # Puntos de entrada unificados (dev / infra / status)
├── docker-compose.yml            # PostgreSQL + backend + frontend en contenedores
└── package.json                  # Scripts npm orquestadores (raíz)
```

### Requisitos previos

Para desarrollo local:

- **Python** 3.12+ (con `venv`)
- **Node.js** 20+
- **Git**

Para el setup de producción en servidor propio (opcional):

- Windows 10/11 o Windows Server 2019+
- 2 GB RAM como mínimo (se recomienda almacenamiento NVMe para 30-50 usuarios concurrentes)
- PowerShell 5.1+ ejecutado como Administrador
- (Opcional) Cuenta de Cloudflare para el túnel de acceso externo

### Instalación y configuración

```bash
# 1. Clonar el repositorio
git clone https://github.com/jackson1939/LABLMA.git
cd LABLMA

# 2. Backend: entorno virtual y dependencias
cd backend
python -m venv venv
.\venv\Scripts\pip install -r requirements.txt
cd ..

# 3. Frontend: dependencias
cd frontend
npm install
cd ..

# 4. Raíz: dependencias del orquestador (concurrently)
npm install
```

**Configurar variables de entorno:**

```bash
copy .env.example backend\.env
copy frontend\.env.local.example frontend\.env.local
```

Por defecto el backend usa SQLite (sin configuración adicional). Para usar PostgreSQL, editar `DATABASE_URL` en `backend\.env` (ver sección [Variables de entorno](#variables-de-entorno)).

### Uso

**Arrancar todo con un solo comando** (migraciones → seed → backend con hot-reload → frontend, en paralelo):

```bash
npm run dev
```

| URL | Descripción |
|-----|-------------|
| http://localhost:3000 | Aplicación web |
| http://localhost:8000/docs | Documentación interactiva de la API (Swagger) |
| http://localhost:8000/redoc | Documentación de la API (ReDoc) |

**Usuarios de demostración** (creados por `npm run seed`):

| Email | Contraseña | Rol |
|-------|-----------|-----|
| admin@sgc.local | Admin1234! | Administrador |
| director@sgc.local | Director1234! | Director |
| responsable@sgc.local | Resp1234! | Responsable |
| verificador@sgc.local | Verif1234! | Verificador |
| elaborador@sgc.local | Elab1234! | Elaborador |

> Cambiar estas credenciales antes de exponer cualquier instancia fuera de un entorno local de pruebas.

**Otros comandos útiles:**

| Comando | Descripción |
|---------|-------------|
| `npm run dev:backend` | Solo backend (uvicorn con `--reload`) |
| `npm run dev:frontend` | Solo frontend (`next dev`) |
| `npm run migrate` | Ejecuta migraciones (Alembic) |
| `npm run seed` | Pobla la base de datos con datos demo |
| `npm run status` | Muestra el estado de backend/frontend/servicio |
| `npm run backup` | Backup de la base de datos |

### API REST

Prefijo base: `/api/v1`. Documentación interactiva autogenerada en `/docs` (Swagger) y `/redoc`.

| Módulo | Endpoints principales |
|--------|----------------------|
| **Auth** | `POST /auth/login`, `GET /auth/me`, `POST /auth/refresh` |
| **Usuarios** | CRUD `/usuarios` (solo rol admin) |
| **Documentos** | CRUD, `POST /{id}/enviar-revision`, `/aprobar`, `/rechazar`, `/dar-de-baja`, `GET /{id}/versiones` |
| **No conformidades** | CRUD, `POST /{id}/analisis`, `/aprobar-plan`, `/cerrar`, `/validar-cierre`, CRUD `/planes-accion` |
| **Riesgos** | CRUD, `GET /matriz` (datos para el mapa de calor) |
| **Planes** | CRUD, `POST /{id}/aprobar`, CRUD `/tareas` |
| **Dashboard** | `GET /kpis`, `/documentos`, `/nc`, `/alertas` |
| **Notificaciones** | `GET /`, `POST /{id}/leer`, `POST /leer-todas` |
| **Scheduler** | `GET /scheduler/run-jobs?cron_secret=...` (protegido, pensado para cron externos) |

**Autenticación:** JWT Bearer token, obtenido en `POST /auth/login` y enviado en el header `Authorization: Bearer <token>`.

**Jerarquía de roles:** `admin` > `director` > `responsable` > `verificador` > `elaborador` > `consultor`.

### Despliegue en producción

El repositorio incluye un stack completo de infraestructura para correr LABLMA de forma autónoma en un servidor Windows propio, con acceso en LAN y, opcionalmente, expuesto a internet:

```powershell
# PowerShell como Administrador, en la carpeta del proyecto:
npm run infra:setup
```

El wizard guía paso a paso: verificación de requisitos → configuración de red y firewall → entorno Python → build de frontend → migraciones y seed → instalación como servicio de Windows (`SGC-Server`) → configuración de auto-deploy vía Git → (opcional) Cloudflare Tunnel para acceso externo sin abrir puertos.

Una vez configurado:

```powershell
npm start   # Inicia el servidor en modo producción
```

**Auto-deploy desde GitHub:** al hacer `git push` desde cualquier equipo, un monitor en el servidor detecta el cambio, ejecuta `git pull`, corre migraciones, reconstruye el frontend y reinicia los servicios automáticamente:

```bash
npm run sync          # add + commit + push (interactivo)
npm run sync:status   # ver estado del repositorio
npm run sync:log      # ver historial de despliegues
```

Comandos de infraestructura disponibles: `infra:start`, `infra:deploy`, `infra:monitor`, `infra:tunnel:install|login|create|start|stop|status|uninstall`, `infra:webhook:start`. El detalle completo de cada uno está documentado en los propios scripts bajo `scripts/infra/`.

### Docker

Alternativa a la infraestructura basada en PowerShell, útil para desarrollo o despliegue en Linux:

```bash
docker-compose up --build
```

Esto levanta PostgreSQL, backend (con migraciones y seed automáticos) y frontend en contenedores separados. Ajustar puertos y variables en `docker-compose.yml` según necesidad.

### Variables de entorno

**Backend** (`backend/.env`, ver plantilla en `.env.example`):

| Variable | Descripción | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Cadena de conexión a la base de datos | `sqlite+aiosqlite:///../data/sgc.db` |
| `SECRET_KEY` | Clave secreta para firmar JWT (mínimo 32 caracteres) | — |
| `ALGORITHM` | Algoritmo de firma JWT | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Minutos de expiración del token | `480` |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASSWORD` / `SMTP_FROM` | Configuración del servidor de correo saliente | — |
| `WHATSAPP_TOKEN` / `WHATSAPP_PHONE_NUMBER_ID` / `WHATSAPP_TEMPLATE_NC` / `WHATSAPP_TEMPLATE_DOC` | Credenciales y plantillas de WhatsApp Cloud API (Meta) | — |
| `FRONTEND_URL` | URL del frontend, usada para CORS | `http://localhost:3000` |
| `ENVIRONMENT` | `development` / `production` | `development` |
| `CRON_SECRET` | Token para proteger el endpoint del scheduler | — |

**Frontend** (`frontend/.env.local`, ver plantilla en `.env.local.example`):

| Variable | Descripción | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | URL base de la API | `/api/v1` (relativa, vía proxy de Next.js) |
| `NEXT_PUBLIC_APP_NAME` | Nombre visible de la aplicación | `SGC - Sistema de Gestión de Calidad` |

> Ninguna variable sensible real está incluida en el repositorio; `.env.example` solo documenta las claves esperadas.

### Estado del proyecto y roadmap

El proyecto está en un estado **funcional / uso interno activo**: cuenta con los seis módulos de negocio implementados end-to-end (frontend + backend + base de datos + notificaciones), migraciones versionadas con Alembic, datos de demostración, y un stack de infraestructura propio ya en uso para desplegar en un servidor real con dominio (`lablma.com`) y túnel Cloudflare. No es un prototipo: incluye autenticación, control de permisos por rol, generación de PDF, notificaciones multicanal y auto-deploy productivo.

Áreas naturales de evolución (no confirmadas como roadmap oficial, inferidas del código):

- Suite de tests automatizados (no se detectaron directorios `tests/` en frontend o backend).
- CI/CD basado en GitHub Actions como alternativa/complemento al monitor de despliegue por polling.
- Empaquetado de la infraestructura de producción para plataformas distintas de Windows.

### Licencia

No se encontró un archivo `LICENSE` en el repositorio al momento de escribir este documento. Por lo tanto, y salvo indicación posterior por parte del autor, aplica **"Todos los derechos reservados"** — proyecto de jackson1939, sin una licencia open-source formal publicada.

> Si la intención es distribuir el proyecto como open-source (por ejemplo bajo MIT, como se mencionaba en una versión anterior de este documento), se recomienda agregar un archivo `LICENSE` en la raíz del repositorio para que ese permiso sea legalmente explícito.

### Autor / Contacto

Desarrollado y mantenido por **[jackson1939](https://github.com/jackson1939)**.

¿Preguntas, reportes de bugs o propuestas de mejora? Abrí un [issue](https://github.com/jackson1939/LABLMA/issues) en este repositorio.

---

<a name="english"></a>

## English

### Table of contents

- [Overview](#overview)
- [Key features](#key-features)
- [Tech stack](#tech-stack)
- [Architecture](#architecture)
- [Project structure](#project-structure)
- [Prerequisites](#prerequisites)
- [Installation & setup](#installation--setup)
- [Usage](#usage)
- [REST API](#rest-api)
- [Production deployment](#production-deployment)
- [Docker](#docker-1)
- [Environment variables](#environment-variables)
- [Project status & roadmap](#project-status--roadmap)
- [License](#license)
- [Author / Contact](#author--contact)

---

### Overview

**LABLMA (SGC)** is a full-stack Quality Management System (QMS) web application that digitizes the processes required by standards such as ISO 9001, ISO 17025, ISO 14001 and ISO 45001: document control, non-conformance management, risk analysis, action plans and improvement programs, plus executive reporting through a real-time KPI dashboard.

It targets organizations that currently run their QMS on spreadsheets or shared folders — SMEs, testing/calibration laboratories, and certification bodies — that need traceability, version control and auditable approval workflows, without the recurring cost of a SaaS quality suite.

Beyond the application itself, the repository ships a **self-contained infrastructure stack** (PowerShell scripts) to deploy and keep the system running autonomously on a self-hosted Windows server, with GitHub auto-deploy and external access via Cloudflare Tunnel — built for organizations without a dedicated DevOps team.

### Key features

- **Document management** with a full lifecycle: `draft → under review → effective → obsolete`. Includes version control, a master document list, a WYSIWYG editor (TipTap) with autosave, change history, and a multi-role approval workflow.
- **Non-conformances (NC)** driven by a state machine: `open → analysis → plan approved → in progress → closed / overdue`. Linked corrective actions and automatic due-date alerts.
- **Risk management** via a probability (1-5) × impact (1-5) = level (1-25) matrix, with a visual heat map, treatment plans and automatic severity classification.
- **Plans & programs** tied to an ISO standard and fiscal year, with a Gantt-style chart (tasks, owners, dates, 0-100% progress) and multi-role approval.
- **Executive dashboard** with real-time KPIs, pie charts (NCs by type) and bar charts (documents by status), upcoming-deadline alerts, and auto-refresh.
- **Multi-channel notifications**: in-app (bell icon with counter), email (SMTP via `fastapi-mail`), and WhatsApp (Meta Cloud API) — triggered when an NC is assigned, a document is approved, or a deadline approaches.
- **Users & roles**: 6 roles with a granular permission matrix (`admin`, `director`, `responsable`, `verificador`, `elaborador`, `consultor`), with user CRUD restricted to admins.
- **PDF generation** for documents and reports via WeasyPrint + Jinja2.
- **Scheduled jobs** (due-date reminders, cleanup, etc.) powered by APScheduler, also triggerable through a protected endpoint for external cron providers (e.g. Vercel Cron).
- **Self-managed infrastructure**: one-command install wizard, Windows Service with automatic startup, a health monitor with auto-restart, GitHub push-triggered auto-deploy, and a Cloudflare Tunnel to expose the system to the internet without opening router ports.

#### Business state machines

```
Document:        draft → under_review → effective → obsolete
Non-conformance: open → analysis → plan_approved → in_progress → closed / overdue
Action plan:      pending → in_progress → completed
Risk:              active → mitigated → accepted
Plan/Program:      draft → approved → in_progress → completed
```

### Tech stack

| Layer | Technology | Version |
|-------|-----------|---------|
| **Frontend** | Next.js (App Router) + TypeScript | 14.2 / 5.4 |
| **Styling** | Tailwind CSS + class-variance-authority | 3.4 |
| **Rich text editor** | TipTap (table, image, link extensions, etc.) | 3.27 |
| **Charts** | Recharts | 2.12 |
| **Icons** | Lucide React | 0.378 |
| **HTTP client (frontend)** | Axios | 1.7 |
| **Backend** | FastAPI + Python | 0.111 / 3.12 |
| **ORM** | SQLAlchemy 2.0 (async) + Alembic (migrations) | 2.0 / 1.13 |
| **Validation** | Pydantic + Pydantic Settings | 2.7 / 2.3 |
| **Database** | PostgreSQL 15 (production) / SQLite + aiosqlite (development) | |
| **Authentication** | JWT (HS256) via `python-jose` + `bcrypt`/`passlib` | configurable expiry (default 8h) |
| **PDF generation** | WeasyPrint + Jinja2 | |
| **Notifications** | SMTP (`fastapi-mail`) + WhatsApp Cloud API (Meta) | |
| **HTTP client (backend)** | httpx | |
| **Scheduled jobs** | APScheduler | 3.10 |
| **Containers** | Docker + Docker Compose | |
| **Infrastructure** | PowerShell scripts (setup, deploy, sync, monitor, tunnel) + cloudflared + Windows Service | |

### Architecture

```
┌────────────────────────────────────────────────────────┐
│                       BROWSER                            │
│           http://localhost:3000 / https://lablma.com    │
└─────────────────────┬──────────────────────────────────┘
                       │  /api/* → same-origin proxy
                       │  / → React Server Components
┌─────────────────────▼──────────────────────────────────┐
│                 NEXT.JS (App Router)                     │
│  ┌─────────────┐  ┌──────────────┐  ┌──────────────┐    │
│  │ Pages        │  │ API Rewrites │  │ Static Assets │   │
│  │ + RSC        │  │ /api/* → BE  │  │               │   │
│  └─────────────┘  └──────┬───────┘  └──────────────┘    │
└──────────────────────────┼──────────────────────────────┘
                            │  server-side proxy
┌──────────────────────────▼──────────────────────────────┐
│                  FASTAPI (Backend)                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Auth     │ │ Docs     │ │ NC       │ │ Risks    │    │
│  │ /auth    │ │ /docs.   │ │ /nc      │ │ /riesgos │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐    │
│  │ Plans    │ │ Dashboard│ │ Notif.   │ │ Scheduler│    │
│  │ /planes  │ │ /kpis    │ │ /notif   │ │ APSch.   │    │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘    │
└──────────────────────┬────────────────────────────────┘
                        │  SQLAlchemy async
┌──────────────────────▼────────────────────────────────┐
│                     DATABASE                             │
│         SQLite (dev) / PostgreSQL 15 (prod)             │
└──────────────────────────────────────────────────────────┘
```

**Production infrastructure (self-hosted Windows server):**

```
┌──────────────────────────────────────────────────┐
│  SERVER (Windows)                                 │
│                                                    │
│  ┌────────┐  ┌────────┐  ┌──────────┐  ┌──────┐  │
│  │Backend │  │Frontend│  │ Monitor  │  │Tunnel│  │
│  │:8000   │  │:3000   │  │health+git│  │CF    │  │
│  └────────┘  └────────┘  └──────────┘  └──────┘  │
│                                                    │
│  ┌──────────────────────────────────────────────┐ │
│  │ Windows Service (SGC-Server, auto-start)      │ │
│  └──────────────────────────────────────────────┘ │
└──────────────────┬───────────────────────────────┘
                    │
      ┌─────────────┴──────────────┐
      │  LAN            │ Internet │
      │  192.168.x.x    │  CF      │
      │  WiFi           │  Tunnel  │
      └─────────────────────────────┘
```

### Project structure

```
LABLMA/
├── frontend/                  # Next.js 14 (App Router) + TypeScript
│   └── src/
│       ├── app/                # Routes: (auth) and (dashboard) groups
│       ├── components/         # UI, layout and per-module components
│       ├── hooks/               # useAuth, useDocumentos, etc.
│       ├── lib/                  # api.ts, auth.ts, utils.ts
│       └── types/                 # Shared TypeScript interfaces
├── backend/                   # FastAPI
│   ├── alembic/                 # Database migrations
│   └── app/
│       ├── auth/                 # Auth router and JWT logic
│       ├── models/               # 10 SQLAlchemy models (user, document, NC, risk, plans...)
│       ├── schemas/              # Pydantic request/response schemas
│       ├── routers/              # 8 routers (~40 endpoints) under /api/v1
│       ├── services/             # email, whatsapp, pdf, scheduler, libreoffice
│       ├── templates/pdf/        # Jinja2 templates for PDF generation
│       ├── seed.py               # Demo data (users, sample documents/NCs)
│       ├── config.py              # Environment-based settings
│       └── main.py                # FastAPI application entry point
├── scripts/
│   ├── infra/                   # Infrastructure and auto-deploy system
│   │   ├── setup.ps1              # One-command install wizard
│   │   ├── network.ps1            # LAN IP detection + firewall rules
│   │   ├── deploy.ps1             # Deployment pipeline
│   │   ├── sync.ps1               # Git sync commands
│   │   ├── tunnel.ps1             # Cloudflare Tunnel management
│   │   ├── monitor.ps1            # Health check + auto-restart + git poller
│   │   ├── webhook-server.py     # GitHub webhook receiver
│   │   └── config.json            # Central infrastructure configuration
│   ├── start-server.ps1          # Production startup
│   ├── stop-server.ps1           # Stop services
│   ├── install-service.ps1       # Install as a Windows Service
│   └── backup.ps1                # Database backup
├── boot.ps1 / start.ps1          # Unified entry points (dev / infra / status)
├── docker-compose.yml            # PostgreSQL + backend + frontend containers
└── package.json                  # Root orchestration npm scripts
```

### Prerequisites

For local development:

- **Python** 3.12+ (with `venv`)
- **Node.js** 20+
- **Git**

For self-hosted production setup (optional):

- Windows 10/11 or Windows Server 2019+
- 2 GB RAM minimum (NVMe storage recommended for 30-50 concurrent users)
- PowerShell 5.1+ run as Administrator
- (Optional) a Cloudflare account for the external-access tunnel

### Installation & setup

```bash
# 1. Clone the repository
git clone https://github.com/jackson1939/LABLMA.git
cd LABLMA

# 2. Backend: virtual environment and dependencies
cd backend
python -m venv venv
.\venv\Scripts\pip install -r requirements.txt
cd ..

# 3. Frontend: dependencies
cd frontend
npm install
cd ..

# 4. Root: orchestrator dependencies (concurrently)
npm install
```

**Configure environment variables:**

```bash
copy .env.example backend\.env
copy frontend\.env.local.example frontend\.env.local
```

By default the backend uses SQLite (no extra configuration needed). To use PostgreSQL, edit `DATABASE_URL` in `backend\.env` (see [Environment variables](#environment-variables)).

### Usage

**Start everything with a single command** (migrations → seed → backend with hot-reload → frontend, all in parallel):

```bash
npm run dev
```

| URL | Description |
|-----|-------------|
| http://localhost:3000 | Web application |
| http://localhost:8000/docs | Interactive API documentation (Swagger) |
| http://localhost:8000/redoc | API documentation (ReDoc) |

**Demo users** (created by `npm run seed`):

| Email | Password | Role |
|-------|----------|------|
| admin@sgc.local | Admin1234! | Administrator |
| director@sgc.local | Director1234! | Director |
| responsable@sgc.local | Resp1234! | Owner/Responsible |
| verificador@sgc.local | Verif1234! | Verifier |
| elaborador@sgc.local | Elab1234! | Drafter |

> Change these credentials before exposing any instance outside a local test environment.

**Other useful commands:**

| Command | Description |
|---------|-------------|
| `npm run dev:backend` | Backend only (uvicorn with `--reload`) |
| `npm run dev:frontend` | Frontend only (`next dev`) |
| `npm run migrate` | Run database migrations (Alembic) |
| `npm run seed` | Seed the database with demo data |
| `npm run status` | Show backend/frontend/service status |
| `npm run backup` | Back up the database |

### REST API

Base prefix: `/api/v1`. Auto-generated interactive docs at `/docs` (Swagger) and `/redoc`.

| Module | Main endpoints |
|--------|-----------------|
| **Auth** | `POST /auth/login`, `GET /auth/me`, `POST /auth/refresh` |
| **Users** | CRUD `/usuarios` (admin only) |
| **Documents** | CRUD, `POST /{id}/enviar-revision`, `/aprobar`, `/rechazar`, `/dar-de-baja`, `GET /{id}/versiones` |
| **Non-conformances** | CRUD, `POST /{id}/analisis`, `/aprobar-plan`, `/cerrar`, `/validar-cierre`, CRUD `/planes-accion` |
| **Risks** | CRUD, `GET /matriz` (heat-map data) |
| **Plans** | CRUD, `POST /{id}/aprobar`, CRUD `/tareas` |
| **Dashboard** | `GET /kpis`, `/documentos`, `/nc`, `/alertas` |
| **Notifications** | `GET /`, `POST /{id}/leer`, `POST /leer-todas` |
| **Scheduler** | `GET /scheduler/run-jobs?cron_secret=...` (protected, meant for external cron) |

**Authentication:** JWT Bearer token, obtained from `POST /auth/login` and sent in the `Authorization: Bearer <token>` header.

**Role hierarchy:** `admin` > `director` > `responsable` > `verificador` > `elaborador` > `consultor`.

### Production deployment

The repository includes a complete infrastructure stack to run LABLMA autonomously on a self-hosted Windows server, reachable over LAN and, optionally, exposed to the internet:

```powershell
# PowerShell as Administrator, from the project folder:
npm run infra:setup
```

The wizard walks through: prerequisite checks → network/firewall configuration → Python environment → frontend build → migrations and seed data → installation as a Windows Service (`SGC-Server`) → Git-based auto-deploy configuration → (optional) Cloudflare Tunnel for external access without opening ports.

Once configured:

```powershell
npm start   # Starts the server in production mode
```

**GitHub auto-deploy:** whenever `git push` is run from any machine, a monitor on the server detects the change, runs `git pull`, applies migrations, rebuilds the frontend, and restarts services automatically:

```bash
npm run sync          # add + commit + push (interactive)
npm run sync:status   # check repository status
npm run sync:log      # view deployment history
```

Additional infrastructure commands: `infra:start`, `infra:deploy`, `infra:monitor`, `infra:tunnel:install|login|create|start|stop|status|uninstall`, `infra:webhook:start`. Full details for each are documented in the scripts themselves under `scripts/infra/`.

### Docker

An alternative to the PowerShell-based infrastructure, useful for local development or Linux deployments:

```bash
docker-compose up --build
```

This brings up PostgreSQL, the backend (with automatic migrations and seeding) and the frontend as separate containers. Adjust ports and variables in `docker-compose.yml` as needed.

### Environment variables

**Backend** (`backend/.env`, see the template in `.env.example`):

| Variable | Description | Default |
|----------|-------------|---------|
| `DATABASE_URL` | Database connection string | `sqlite+aiosqlite:///../data/sgc.db` |
| `SECRET_KEY` | Secret key used to sign JWTs (32+ chars) | — |
| `ALGORITHM` | JWT signing algorithm | `HS256` |
| `ACCESS_TOKEN_EXPIRE_MINUTES` | Token expiry, in minutes | `480` |
| `SMTP_HOST` / `SMTP_PORT` / `SMTP_USER` / `SMTP_PASSWORD` / `SMTP_FROM` | Outgoing mail server configuration | — |
| `WHATSAPP_TOKEN` / `WHATSAPP_PHONE_NUMBER_ID` / `WHATSAPP_TEMPLATE_NC` / `WHATSAPP_TEMPLATE_DOC` | WhatsApp Cloud API (Meta) credentials and templates | — |
| `FRONTEND_URL` | Frontend URL, used for CORS | `http://localhost:3000` |
| `ENVIRONMENT` | `development` / `production` | `development` |
| `CRON_SECRET` | Token protecting the scheduler endpoint | — |

**Frontend** (`frontend/.env.local`, see the template in `.env.local.example`):

| Variable | Description | Default |
|----------|-------------|---------|
| `NEXT_PUBLIC_API_URL` | Base API URL | `/api/v1` (relative, via Next.js proxy) |
| `NEXT_PUBLIC_APP_NAME` | Application display name | `SGC - Sistema de Gestión de Calidad` |

> No real secrets are included in the repository; `.env.example` only documents the expected keys.

### Project status & roadmap

The project is in an **active, functionally complete** state: all six business modules are implemented end-to-end (frontend + backend + database + notifications), migrations are versioned with Alembic, demo data is seeded, and a purpose-built infrastructure stack is already deployed to a real server with a live domain (`lablma.com`) via a Cloudflare Tunnel. This is not a prototype: it includes authentication, role-based permissions, PDF generation, multi-channel notifications, and production auto-deploy.

Natural areas for future work (inferred from the code, not an official roadmap):

- An automated test suite (no `tests/` directories were found in frontend or backend).
- GitHub Actions-based CI/CD as an alternative or complement to the polling-based deploy monitor.
- Packaging the production infrastructure for platforms other than Windows.

### License

No `LICENSE` file was found in the repository at the time of writing. Absent one, and unless the author states otherwise, **"All rights reserved"** applies — this is jackson1939's project, without a formally published open-source license.

> If the intent is to distribute the project as open source (e.g. under MIT, as an earlier version of this document stated), adding a `LICENSE` file at the repository root is recommended to make that permission legally explicit.

### Author / Contact

Built and maintained by **[jackson1939](https://github.com/jackson1939)**.

Questions, bug reports or feature suggestions? Open an [issue](https://github.com/jackson1939/LABLMA/issues) on this repository.

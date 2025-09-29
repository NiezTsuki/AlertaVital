# Backend (Node.js + Express + PostgreSQL)

Endpoints listos para probar con Postman:

- POST /auth/register
- POST /auth/login
- GET  /auth/me (con `Authorization: Bearer <token>`)

## Pasos
1) Crear base de datos y aplicar `db/001_init.sql`
2) `cp .env.example .env`
3) `npm i`
4) `npm run dev`

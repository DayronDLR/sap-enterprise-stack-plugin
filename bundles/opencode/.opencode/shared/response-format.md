# Formato de Respuesta Estandar — Agentes SAP

> Cada agente adapta las secciones a su dominio. Este es el esqueleto base.

## Estructura

Toda respuesta de un agente especializado debe incluir estas secciones (adaptar nombres al dominio):

1. **ANALISIS** — Comprension del requerimiento, stack detectado, decisiones de diseno
2. **ARQUITECTURA / DISENO** — Diagrama o descripcion de componentes y capas
3. **IMPLEMENTACION** — Codigo, configuracion, artefactos (la seccion mas extensa)
4. **SEGURIDAD** — Autorizaciones, roles, XSUAA, access control segun aplique
5. **TESTING** — Tests unitarios, integracion, o validacion segun el dominio
6. **CONSIDERACIONES** — Riesgos, dependencias, limitaciones, proximos pasos

## Reglas

- Siempre empezar con un resumen de 2-3 lineas antes de las secciones
- Si una seccion no aplica, indicar explicitamente por que se omite
- Codigo siempre en bloques con lenguaje especificado
- Mencionar transacciones SAP relevantes donde aplique
- Terminar con proximos pasos o dependencias pendientes

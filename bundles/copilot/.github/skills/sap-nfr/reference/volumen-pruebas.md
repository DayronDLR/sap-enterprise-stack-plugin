# Volúmenes mínimos de prueba antes de dar por listo

> Detalle del catálogo NFR del stack. Se lee bajo demanda.

## 7. Volumen de Pruebas Obligatorio

| Sistema | Volumen minimo en QAS antes de "listo" |
|---|---|
| Reports / queries | 80% del volumen pico productivo estimado |
| Jobs batch | 100% del volumen pico + simulacion de cancelacion en medio |
| Interfaces | rafaga de 10× la frecuencia normal durante 5 min |
| Apps Fiori | dataset >5.000 registros para validar paginacion |
| Procesos paralelos | minimo 3 ejecuciones simultaneas del mismo flujo |

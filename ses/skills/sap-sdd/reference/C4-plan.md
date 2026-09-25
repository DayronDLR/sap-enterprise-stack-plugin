# C4 — Plan y estimación

Perspectiva: **Tech Lead SAP**. Convertís el inventario de C3 en un plan de
trabajo y en una estimación **justa**: la que un equipo competente cumple sin
héroes y sin holgura escondida. Una estimación inflada es tan mala como una
corta: encarece la propuesta, se pierde el proyecto o se gasta la holgura.

## Qué leer

1. `C3-diseno/diseno.md` (el inventario) y `C3-diseno/handoff.md`.
2. `C2-escenarios/casos-prueba.md`: el esfuerzo de pruebas sale de ahí.
3. `C1-captura/preguntas.md`: cada pregunta abierta es un supuesto o un riesgo.
4. Si el arquitecto te pasó **referencias de su equipo** (horas reales de
   proyectos parecidos), usalas antes que cualquier intuición. Nunca inventes un
   "histórico".

## Qué producir

| Archivo | Obligatorio | Qué verifica el gate |
|---|---|---|
| `C4-plan/plan.md` | sí | al menos una cita; los riesgos `R-NN` que usa la contingencia |
| `C4-plan/estimacion.md` | sí | todo lo de la sección «Qué verifica el gate» |
| `C4-plan/handoff.md` | sí | — |

## Estimar lo justo

El sobredimensionamiento casi nunca viene de un número malo. Viene de cómo se
arman los números. Cada regla de abajo cierra una de esas puertas, y el gate
verifica las que se pueden verificar con aritmética.

1. **Sólo lo que está en el inventario, y todo lo que está.** Cada línea de
   la estimación apunta a uno o más `OBJ-NN` de C3. Si falta un objeto, se
   vuelve a C3; no se agrega acá. Lo olvidado se termina pagando con colchón.
2. **Tres puntos, cada uno con su significado.**
   - `M` es la **mediana** para el equipo que lo va a hacer: la mitad de las
     veces sale en menos. No es el número seguro. Tampoco es "lo más común":
     en tareas con cola hacia el lado malo, lo más común queda por debajo de la
     mediana, y la estimación sale corta.
   - `O` es el **P10**: 1 de cada 10 veces sale así de rápido o más. No es un
     heroísmo.
   - `P` es el **P90**: 1 de cada 10 veces tarda esto o más. No es una
     catástrofe.
   - `E = 0,3·O + 0,4·M + 0,3·P`. Es la media de Swanson para P10/P50/P90. La
     fórmula PERT `(O + 4M + P) / 6` supone que O y P son los extremos
     absolutos, y con estimaciones reales (que son P10/P90) sale corta.
3. **El colchón va una sola vez.** No se infla `M` "por las dudas" y después se
   suma contingencia: eso cobra dos veces el mismo riesgo.
4. **La contingencia es por riesgo identificado**, nunca un porcentaje general.
   Cada fila es un riesgo `R-NN` de la tabla de riesgos del plan, con su
   probabilidad y las horas que costaría si ocurre: `Horas = Prob × Impacto`.
   - Cada riesgo va **una sola vez**.
   - La probabilidad va **entre 0 y 1, sin incluir el 1**. Algo que va a pasar
     seguro no es un riesgo: es trabajo, y va a la estimación como tarea.
   - **Un riesgo va en la contingencia o en `P`, nunca en los dos.** Si el `P`
     de una tarea ya contempla que ocurra R-01, R-01 no va a la contingencia.
5. **Partí lo grande.** Una tarea con `M` de más de 40 h esconde holgura y
   errores: se parte en tareas de una semana o menos. Partir no achica el
   rango: las tareas que comparten algún objeto se suman como correlacionadas,
   porque si una se complica, se complican juntas. Las transversales, entre sí,
   también.
6. **Si `P` pasa de 3 veces `M`, no es un rango: es una pregunta sin
   responder.** Llevala a `preguntas.md`, o partí la tarea hasta que se entienda.
7. **Las transversales se estiman por entregable concreto**, nunca como
   porcentaje: el gate rechaza un `%` en la columna Base. Revisá cada una y
   estimá sólo las que aplican:
   - pruebas funcionales: casos de C2 × tiempo por caso;
   - pruebas de integración con terceros: interfaces × ciclos;
   - soporte de UAT: sesiones o días;
   - despliegue: ciclos de transporte;
   - cutover e hypercare: días acordados;
   - documentación: documentos.

   Las pruebas unitarias van dentro de la tarea de cada objeto, no aparte.
   La conectividad (Cloud Connector, destinations, credenciales) es un objeto
   del inventario de C3, no una transversal. Gestión de proyecto, sólo si el
   arquitecto la pide.
8. **Lo estándar cuesta su uso, no su construcción.** Un objeto `Estándar` o
   `Configuración` se estima como configuración y prueba, no como desarrollo.
9. **El total es ΣE más la contingencia.** La suma de los pesimistas no es una
   estimación: que todo salga mal a la vez es improbable. El rango honesto es el
   P80, que el gate calcula con la varianza de las tareas y la de los riesgos.

Unidades: **horas-persona**. No conviertas a dinero salvo que el arquitecto te dé
la tarifa.

## `estimacion.md`

Tres tablas, con estos títulos y columnas:

```markdown
## Estimación

| ID | Tarea | OBJ | Base | O | M | P | E |
|---|---|---|---|---|---|---|---|
| EST-01 | Vista CDS de aging con buckets | OBJ-01 | descomposición: 3 asociaciones y 1 cálculo | 6 | 8 | 14 | 9,2 |
| EST-02 | Customizing de intervalos | OBJ-02 | comparable: 4 intervalos en SPRO | 1 | 2 | 3 | 2,0 |
| EST-03 | Pruebas funcionales | transversal | 8 casos de C2 × 0,5 h | 3 | 4 | 6 | 4,3 |

## Contingencia

| Riesgo | Prob | Impacto | Horas |
|---|---|---|---|
| R-01 Volumen de partidas mayor al informado | 0,3 | 10 | 3,0 |

## Totales

| Concepto | Horas |
|---|---|
| Base | 15,5 |
| Contingencia | 3,0 |
| Total | 18,5 |
| P80 | 23,3 |
```

- `OBJ`: uno o más `OBJ-NN` separados por coma, o `transversal`.
- `Base`: cómo salió `M`. Puede ser la descomposición en pasos, un comparable
  con nombre, o una referencia del equipo. Si no sabés decir en qué se basa, el
  número es una adivinanza: una palabra suelta como «experiencia» genera un
  aviso, y un porcentaje no pasa.
- `E` con un decimal. El gate verifica la fórmula.
- `Totales` lleva exactamente estas cuatro filas. Otra fila, como un «total con
  seguridad», no pasa:
  - `Base` = ΣE;
  - `Contingencia` = Σ Horas de la tabla de contingencia;
  - `Total` = Base + Contingencia;
  - `P80` = Total + 0,8416 × σ, donde σ² suma la de las tareas y la de los riesgos:
    - cada tarea aporta σ = (P − O) / 2,563, y las que comparten algún objeto
      (o las transversales, entre sí) se suman antes de elevar al cuadrado;
    - cada riesgo aporta Prob × (1 − Prob) × Impacto².

  El gate los recalcula e imprime el P80, así que no hace falta calcularlo a
  mano: copiá el que da. Si no hay riesgos que cuantificar, la contingencia
  lleva una fila `—` con 0 h.

Al correr `sdd gate <proyecto> C4`, el gate imprime el resumen: base,
contingencia, total, P80, el rango de las tareas, las horas por objeto y avisos
para tu juicio. Los avisos no bloquean:

- una contingencia de más del 25 % de la base;
- un riesgo con probabilidad de 0,8 o más: se parece a trabajo seguro;
- transversales de más del 35 % del desarrollo cuando alguna no está contada
  por entregable;
- una tarea con P > 3M: es una pregunta abierta;
- una tarea con O, M y P casi iguales: ¿de verdad no hay incertidumbre, o M
  está inflado para cubrirla?;
- una fila que cubre tres objetos o más, o filas que encadenan tres objetos en
  un mismo grupo de riesgo;
- una base que no cuenta nada ni nombra un comparable;
- objetos del inventario del mismo tipo que citan exactamente las mismas
  reglas: ¿son uno solo partido?

Mirá las horas por objeto: una inflación pareja en todas las filas no dispara
ningún aviso relativo, pero se ve cuando un objeto chico suma muchas horas.

## `plan.md`

- **WBS por capa y por agente del stack**, con dependencias: requerimientos,
  integración, CAP, Fiori, HANA, ABAP, Basis, migración, QA, DevOps. Sólo los que
  el inventario necesita.
- **Transportes**: la ruta DEV → QAS → PRD y qué objetos viajan juntos.
- **Riesgos**, en una tabla bajo el título `## Riesgos`, con la mitigación de
  cada uno. La contingencia sólo puede usar los `R-NN` de esta tabla:

  ```markdown
  ## Riesgos

  | ID | Riesgo | Prob | Impacto | Mitigación |
  |---|---|---|---|---|
  | R-01 | Volumen de partidas mayor al informado | 0,3 | 10 h | Prueba de volumen en QAS con datos reales |
  ```

- **Supuestos** que, si fallan, cambian la estimación. Cada uno con su impacto.
- **Fuera de alcance**: lo que no se estimó, a propósito.

Cita el requerimiento donde el plan se apoya en una regla.

## Cómo se presenta

En el resumen al arquitecto:

1. **El total** (ΣE + contingencia) es la estimación.
2. **El P80**, para quien necesite un número con más confianza.
3. **Los supuestos** que, si fallan, la cambian.

Nunca presentes la suma de los pesimistas como la estimación. Tampoco le sumes
un porcentaje "de seguridad" que no esté en la tabla de contingencia.

## `handoff.md` — para la implementación

El orden de trabajo por agente con sus dependencias, que es lo que
`/sap-techlead` va a ejecutar, y los objetos de cada transporte.

## No hacer

- Estimar objetos que no están en el inventario, o dejar alguno afuera.
- Inflar `M`, o sumar colchón en las tareas y además contingencia.
- Contingencia como porcentaje sin riesgo que la respalde.
- Tareas de más de 40 h sin partir.
- Presentar ΣP, o redondear hacia arriba cada línea.
- Dejar `<!-- sdd:pendiente -->` en un archivo que se presenta.

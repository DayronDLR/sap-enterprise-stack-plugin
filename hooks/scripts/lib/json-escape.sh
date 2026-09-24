#!/bin/bash
# json-escape.sh — escapar texto arbitrario como string JSON, en bash puro.
#
# POR QUE VIVE SOLO
#
# La necesitan dos consumidores que NO se sourcean entre si:
#
#   dod-common.sh        arma la `permissionDecisionReason` que el host parsea
#   emit-stack-event.sh  arma cada linea de logs/stack-events.jsonl
#
# Y los dos los sourcea el mismo gate, asi que copiarla en el segundo habria sido
# una redefinicion, no una copia inofensiva. Es la misma tesis que el resto del
# aparato: una regla, un lugar.
#
# SIN INTERPRETE. Los hooks corren en cada tool call y un spawn de python3 o node
# por hook es latencia pura sobre el camino caliente.
#
# Doble source: este archivo es idempotente —solo define funciones— y NO usa
# `readonly`, que bajo `set -e` mata el script en el segundo source.

# Escapa un texto como string JSON, comillas incluidas.
#
# Cubre TODOS los control chars que exige RFC 8259 (`\x00-\x1F`), no solo los
# cinco de siempre. Una version anterior decia cubrir "los escapes que exige RFC
# 8259" y hacia `\\`, `"`, `\t`, `\r`, `\n`: la promesa era mas ancha que el
# codigo. Un `\x0c` o un `\x08` —que se cuelan por un filename importado o un
# stderr de git en un locale viejo— producian JSON invalido, y un hook que
# devuelve JSON no parseable no tiene comportamiento garantizado: el host puede
# caer a "allow".
# Hasta aca el escapado es bash puro, sin fork. Mas grande, se delega.
#
# Estaba en 2048 y el Gate 3 midio el peor caso justo debajo: 2048 caracteres de
# control mezclados en 6,7 s, 2048 `\x1b` en 0,55 s. Con 512 el peor caso medido
# es de ~120 ms. Los payloads del emisor son de ~200 B, asi que el camino caliente
# sigue sin fork; lo que se delega es el texto de un deny largo, que es raro.
SES_JSON_BASH_MAX=512
# Sin interprete, lo que se recorta. Se escapa en bash, asi que tambien acota el
# costo de ese camino degradado.
SES_JSON_RECORTE=2048

ses_json_escape() {
    local s="$1" out
    # LO GRANDE NO SE ESCAPA EN BASH, porque en bash no hay forma lineal.
    #
    # `${s//x/y}` en bash 3.2 reconstruye el string entero por CADA coincidencia:
    # O(n·m). Medido con una razon de deny tipo salida de ESLint con color —el
    # `\x1b` de ANSI aparece dos veces por linea—: 2 KB en 48 ms, 7 KB en 1,5 s,
    # 14 KB en 12 s, y `LC_ALL=C` no cambia nada. Una version anterior indexaba
    # caracter a caracter y daba lo mismo; reemplazar el bucle por sustituciones
    # no lo arreglo, porque el cuadratico estaba en la sustitucion misma. Esto
    # corre en `deny()`, dentro del timeout del host.
    #
    # Asi que: lo chico —el camino caliente, payloads de eventos de ~200 B— en
    # bash sin fork; lo grande, a un interprete que escapa en una pasada. El
    # resultado se CAPTURA antes de imprimir: si el interprete muere a mitad, no
    # queda media salida seguida de la del respaldo.
    #
    # Sin node ni python3 se recorta con aviso, y el deny se imprime igual. Un
    # mensaje recortado sigue denegando; un hook que no termina a tiempo es una
    # incognita que depende del host.
    if (( ${#s} > SES_JSON_BASH_MAX )); then
        if command -v node >/dev/null 2>&1; then
            out=$(printf '%s' "$s" | node -e 'let d="";process.stdin.setEncoding("utf8");process.stdin.on("data",(c)=>{d+=c;}).on("end",()=>{process.stdout.write(JSON.stringify(d));});' 2>/dev/null) \
                && [[ -n "$out" ]] && { printf '%s' "$out"; return 0; }
        fi
        if command -v python3 >/dev/null 2>&1; then
            out=$(printf '%s' "$s" | python3 -c 'import json,sys; sys.stdout.write(json.dumps(sys.stdin.buffer.read().decode("utf-8","replace"), ensure_ascii=False))' 2>/dev/null) \
                && [[ -n "$out" ]] && { printf '%s' "$out"; return 0; }
        fi
        if (( ${#s} > SES_JSON_RECORTE )); then
            s="${s:0:SES_JSON_RECORTE}"$'\n''[... recortado: sin node ni python3 para escapar el resto]'
        fi
    fi
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    # El resto de `\x01-\x1F`, UNA SUSTITUCION POR CARACTER, sin bucle.
    #
    # Aca habia un bucle que indexaba caracter a caracter con `${s:i:1}`, y en
    # bash 3.2 con locale UTF-8 cada indexado recorre desde el principio: costo
    # CUADRATICO. Medido por el Gate 3 con una razon de deny tipo salida de ESLint
    # con color (el `\x1b` de ANSI dispara el bucle): 2,4 KB en 266 ms, 7 KB en
    # 2,4 s, 14 KB en 10,8 s. Y esto corre en `deny()`, dentro del timeout del
    # host.
    #
    # La forma literal `s="${s//X/\\uNNNN}"` y no una tabla con variables: bash
    # 3.2 conserva LITERALMENTE las comillas de un reemplazo citado
    # (`"${s//"$ch"/"$rep"}"` da `a"\u001b"b`), y sin citar el comportamiento del
    # backslash cambia en bash 5.2. Esta es la misma forma que las cinco lineas de
    # arriba, que ya corren en CI con bash 5.
    if [[ "$s" == *[$'\x01'-$'\x08'$'\x0b'$'\x0c'$'\x0e'-$'\x1f']* ]]; then
        s="${s//$'\x01'/\\u0001}"
        s="${s//$'\x02'/\\u0002}"
        s="${s//$'\x03'/\\u0003}"
        s="${s//$'\x04'/\\u0004}"
        s="${s//$'\x05'/\\u0005}"
        s="${s//$'\x06'/\\u0006}"
        s="${s//$'\x07'/\\u0007}"
        s="${s//$'\x08'/\\u0008}"
        s="${s//$'\x0b'/\\u000b}"
        s="${s//$'\x0c'/\\u000c}"
        s="${s//$'\x0e'/\\u000e}"
        s="${s//$'\x0f'/\\u000f}"
        s="${s//$'\x10'/\\u0010}"
        s="${s//$'\x11'/\\u0011}"
        s="${s//$'\x12'/\\u0012}"
        s="${s//$'\x13'/\\u0013}"
        s="${s//$'\x14'/\\u0014}"
        s="${s//$'\x15'/\\u0015}"
        s="${s//$'\x16'/\\u0016}"
        s="${s//$'\x17'/\\u0017}"
        s="${s//$'\x18'/\\u0018}"
        s="${s//$'\x19'/\\u0019}"
        s="${s//$'\x1a'/\\u001a}"
        s="${s//$'\x1b'/\\u001b}"
        s="${s//$'\x1c'/\\u001c}"
        s="${s//$'\x1d'/\\u001d}"
        s="${s//$'\x1e'/\\u001e}"
        s="${s//$'\x1f'/\\u001f}"
    fi
    printf '"%s"' "$s"
}

# ¿Es `$1` un objeto JSON que se puede escribir tal cual en una linea JSONL?
#
# NO alcanza con mirar si empieza con `{`. El emisor de eventos hacia exactamente
# eso y dejaba pasar crudo `{no es json` y hasta un `{` suelto. La primera
# version de este validador contaba llaves fuera de strings, y el Gate 3 midio que
# tambien era demasiado permisivo: aceptaba `{no es json}`, `{"a":1,}`,
# `{"a":"x"} {"b":1}` y strings con un salto de linea o un TAB crudo adentro —que
# parten la linea en dos o la vuelven invalida—. 7 de 15 lineas salian rotas.
#
# Ahora exige, ademas del balance:
#   - fuera de strings, solo lo que JSON admite: estructura, numeros, espacio,
#     TAB y las letras de true/false/null. `no es json` cae por la `o`.
#   - adentro de un string, ningun caracter de control crudo, y escapes validos.
#   - nada despues de que la llave de afuera cierra.
#   - nada de coma antes de un cierre.
#
# Tambien rechaza dos valores sin separador y separadores vacios (`{"a":}`,
# `{"a" "b"}`, `[1,,2]`). Sigue sin ser un parser, y lo dice: pasan los errores
# lexicos (`{"a":tru}`, `{"a":01}`, `{"a":--1}`) y cuatro estructurales medidos
# por el Gate 3 —`{"a":{]}`, `{"a"}`, `{"a":"b":"c"}`, `{"a":"\u12"}`—. Los
# llamadores reales pasan payloads internos que no tienen esas formas. Lo unico que el llamador
# decide con esto es "va como objeto" o "va envuelto como texto", y ante la duda
# responde que NO: el payload dudoso termina como string y la linea sale valida
# igual.
#
# Acotado a 1 KB. Recorre caracter a caracter, y eso en bash es cuadratico; los
# payloads reales son de ~200 B. Uno mas grande se envuelve como texto, que es
# correcto y lineal.
ses_json_es_objeto() {
    local LC_ALL=C
    local s="$1" i c n en_str=0 esc=0 prof=0 cerrado=0 ult='' sep=0 ini fin_v
    n=${#s}
    (( n > 0 && n <= 1024 )) || return 1
    [[ "${s:0:1}" = "{" ]] || return 1
    for (( i=0; i<n; i++ )); do
        c="${s:i:1}"
        if (( en_str )); then
            if (( esc )); then
                case "$c" in '"'|'\'|/|b|f|n|r|t|u) esc=0 ;; *) return 1 ;; esac
            elif [[ "$c" = '\' ]]; then esc=1
            elif [[ "$c" = '"' ]]; then en_str=0; ult='"'; sep=0
            elif [[ "$c" < ' ' ]]; then return 1
            fi
            continue
        fi
        case "$c" in ' '|$'\t') sep=1; continue ;; esac
        (( cerrado )) && return 1
        # DOS VALORES SIN SEPARADOR: `{"a" "b"}`, `{"a":1 2}`, `{"a":{}"b":1}`. Un
        # valor termino si lo ultimo fue un string, un cierre, o una palabra seguida
        # de espacio; y `c` empieza otro valor.
        ini=0; fin_v=0
        case "$c" in '"'|'{'|'['|[0-9]|-|t|f|n) ini=1 ;; esac
        case "$ult" in
            '"'|'}'|']') fin_v=1 ;;
            # Una palabra termina en un espacio, o cuando lo que sigue no puede ser
            # parte de ella: `1"b"` son dos valores aunque no haya espacio.
            [0-9a-z]) (( sep )) && fin_v=1
                      case "$c" in '"'|'{'|'[') fin_v=1 ;; esac ;;
        esac
        (( ini && fin_v )) && return 1
        # SEPARADORES QUE NO SEPARAN NADA: `{"a":}`, `{:}`, `{,"a":1}`, `[1,,2]`,
        # `{"a":1,}`. Lo que el Gate 3 midio que la version anterior dejaba pasar;
        # `{"duration_ms":,…}` —un numero vacio— es la forma realista.
        case "$c" in
            ',')     case "$ult" in ','|':'|'{'|'['|'') return 1 ;; esac ;;
            ':')     case "$ult" in '"') ;; *) return 1 ;; esac ;;
            '}'|']') case "$ult" in ','|':') return 1 ;; esac ;;
        esac
        case "$c" in
            '"') en_str=1 ;;
            '{'|'[') prof=$(( prof + 1 )) ;;
            '}'|']')
                prof=$(( prof - 1 ))
                (( prof < 0 )) && return 1
                (( prof == 0 )) && cerrado=1 ;;
            ':'|','|[0-9]|-|+|.|e|E|t|r|u|f|a|l|s|n) ;;
            *) return 1 ;;
        esac
        ult="$c"; sep=0
    done
    (( en_str == 0 && prof == 0 && cerrado ))
}

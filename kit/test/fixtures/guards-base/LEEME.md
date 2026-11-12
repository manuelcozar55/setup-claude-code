# Copia congelada de los guards de la version base (bc68243)

Solo referencia de test: la usa `kit/test/test_guards_monotonia.sh` (y `test_guards_r1.sh` para medir la columna `base`) como oraculo
de «que habria dicho la version anterior». NO se instala (`install.sh` solo copia `kit/claude/` y `kit/sentinel/`), y los ficheros
llevan el sufijo `.base` para que ni shellcheck ni el escaner los traten como codigo vivo; el test los materializa en un directorio
temporal. No se edita: si hay que cambiarla, es que la base de comparacion cambia, y eso se decide en una revision.

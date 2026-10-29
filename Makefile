.DEFAULT_GOAL := help

.PHONY: help install bootstrap test test-cockpit bateria doctor mutantes phoenix phoenix-push evals-dryrun evals-paid evals-ablacion-paid

help: ## Lista los targets disponibles
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*##"}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Instala el kit en CLAUDE_HOME (default $HOME/.claude)
	bash kit/install.sh

bootstrap: ## Para quien trabaja EN este repo (perfil de harness, kit, tests y doctor). Un companero nuevo usa: bash kit/install.sh && bash kit/doctor.sh
	@[ -f config/profile.yaml ] || { cp config/profile.example.yaml config/profile.yaml; \
	  echo "==> config/profile.yaml creado desde el ejemplo. Editalo: es tuyo y no viaja en el repo."; }
	bash kit/install.sh
	@$(MAKE) --no-print-directory test
	@echo ""
	@echo "==> Suite verde. Ahora el estado de ESTA maquina:"
	bash kit/doctor.sh
	@echo ""
	@echo "==> Harness levantado y verificado."
	@echo "    Un FAIL de doctor.sh es un hallazgo de tu maquina, no del kit: leelo y actua."

# Las suites que se saltan algo lo anotan en SCC_SKIP_LOG; al final se lista, para que un verde con capas
# saltadas no se lea como verde completo. El rc no cambia: un skip no es un fallo.
ifndef SCC_SKIP_LOG
export SCC_SKIP_LOG := $(shell mktemp -u "$${TMPDIR:-/tmp}/scc-skips.XXXXXX")
endif

test: ## Corre las suites de test (NO incluye el eval set: ese cuesta dinero)
	@rm -f "$(SCC_SKIP_LOG)"
	bash kit/test/test_guards.sh
	bash kit/test/test_guards_falsifiability.sh
	bash kit/test/test_guards_corpus.sh
	bash kit/test/test_secret_content_gitleaks.sh
	bash kit/test/test_scan_secrets.sh
	bash kit/test/test_install.sh
	bash kit/test/test_install_settings_merge.sh
	bash kit/test/test_doctor.sh
	bash kit/test/test_install_platform_gate.sh
	bash kit/test/test_install_gitleaks.sh
	bash kit/test/test_install_gitleaks_checksum.sh
	bash kit/test/test_enable_secrets_layer2.sh
	bash kit/test/test_gitattributes.sh
	bash kit/test/test_exec_modes.sh
	bash kit/test/test_optional_hook.sh
	bash kit/test/test_clean_install_resilience.sh
	bash kit/test/test_doctor_base_url.sh
	bash kit/test/test_metrics.sh
	bash kit/test/test_detect_oracle.sh
	bash kit/test/test_auto_spec.sh
	bash kit/test/test_autonomy.sh
	bash kit/test/test_harness_structure.sh
	bash kit/test/test_install_diff_first.sh
	bash kit/test/test_uninstall.sh
	bash kit/test/test_doc_claims.sh
	bash kit/test/test_permisos_efectivos.sh
	bash kit/test/test_evals.sh
	bash kit/test/test_skills.sh
	bash kit/test/test_mod_cockpit.sh
	bash kit/test/test_statusline.sh
	bash kit/test/test_session_start_clear.sh
	bash kit/test/test_nucleo_lib.sh
	bash kit/test/test_nucleo_integridad.sh
	bash kit/test/test_agentes.sh
	bash kit/test/test_nucleo_hooks.sh
	bash kit/test/test_nucleo_nudge.sh
	bash kit/test/test_nucleo_gate.sh
	bash kit/test/test_settings_template.sh
	bash kit/test/test_install_plugins.sh
	bash kit/test/test_claude_md_template.sh
	bash kit/test/test_recall.sh
	bash kit/test/test_scripts_audit.sh
	bash kit/test/test_presupuesto_contexto.sh
	bash kit/test/test_guia.sh
	bash kit/test/test_plugin_esenciales.sh
	bash kit/test/test_sesiones_home.sh
	@if [ -s "$(SCC_SKIP_LOG)" ]; then echo; echo "== make test: verde, pero con capas SALTADAS (no cuentan como verificadas) =="; sort -u "$(SCC_SKIP_LOG)"; fi; rm -f "$(SCC_SKIP_LOG)"

test-cockpit: ## Tests funcionales del cockpit; requiere Claude Code con soporte de mods
	claude plugin test kit/mods/cockpit

# bateria: los cuatro oraculos de cierre, cada uno con su .rc y su .log. Corren todos aunque uno falle; rc != 0 si
# alguno falla. Una herramienta ausente da rc 127 (el shell lo da solo), nunca un SKIP. Los BATERIA_* se pueden
# sustituir (los tests lo hacen con dobles). Alcance de shellcheck: todos los .sh versionados y kit/claude/bin/*.
BATERIA_DIR ?= .claude/estado/informes/$(shell date +%F)-bateria
BATERIA_BASE ?= $(shell git describe --tags --abbrev=0 2>/dev/null)
BATERIA_TEST_CMD ?= $(MAKE) --no-print-directory test
BATERIA_SCAN_CMD ?= bash kit/scan-secrets.sh .
BATERIA_SHELLCHECK ?= shellcheck
BATERIA_GITLEAKS ?= gitleaks

bateria: ## make test + shellcheck + scan-secrets + gitleaks (BATERIA_DIR, BATERIA_BASE), un .rc y un .log cada uno
	@d="$(BATERIA_DIR)"; mkdir -p "$$d"; base="$(BATERIA_BASE)"; \
	$(BATERIA_TEST_CMD) > "$$d/make.log" 2>&1; echo $$? > "$$d/make.rc"; \
	$(BATERIA_SHELLCHECK) -x $$(git ls-files '*.sh' 'kit/claude/bin/*') > "$$d/sc.log" 2>&1; echo $$? > "$$d/sc.rc"; \
	$(BATERIA_SCAN_CMD) > "$$d/scan.log" 2>&1; echo $$? > "$$d/scan.rc"; \
	$(BATERIA_GITLEAKS) git --log-opts="$${base:+$$base..}HEAD" -c kit/claude/.gitleaks.toml . > "$$d/gl.log" 2>&1; echo $$? > "$$d/gl.rc"; \
	r="make=$$(cat "$$d/make.rc") sc=$$(cat "$$d/sc.rc") scan=$$(cat "$$d/scan.rc") gl=$$(cat "$$d/gl.rc")"; \
	echo "$$r" | tee "$$d/resumen.txt"; echo "logs en $$d"; \
	[ "$$r" = "make=0 sc=0 scan=0 gl=0" ]

doctor: ## Verifica una instalacion existente del kit
	bash kit/doctor.sh

mutantes: ## Rompe cada sensor del eval a proposito y exige que la suite se ponga roja (gratis, ~4 min)
	python3 kit/evals/mutantes.py

phoenix: ## Levanta Phoenix en local (interfaz web en :6006). Sin Docker y sin licencia.
	~/.venvs/tools/bin/phoenix serve

phoenix-push: ## Sube runs.jsonl al Phoenix local (necesita 'make phoenix' en otra terminal)
	~/.venvs/tools/bin/python kit/evals/phoenix_push.py

evals-dryrun: ## Ensayo: cuantas llamadas y cuanto costaria, sin gastar nada
	DRYRUN=1 bash kit/evals/run.sh

evals-paid: ## Eval set, LOS DOS BRAZOS: llamadas REALES a la API. CUESTA DINERO. Pide confirmacion.
	@read -p "Esto corre los dos brazos sobre 23 tareas: llamadas reales a la API (cuantas y a que coste: 'make evals-dryrun'). Continuar? [y/N] " ans; \
	[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || { echo "Cancelado."; exit 1; }
	bash kit/evals/run.sh
	ARM=off bash kit/evals/run.sh
	@echo; python3 kit/evals/report.py

evals-ablacion-paid: ## Los 3 brazos de ablacion (E22): quita una pieza cada vez. MAS llamadas reales, sobre las de arriba.
	@read -p "Esto corre 3 brazos mas sobre 23 tareas: llamadas reales a la API (cuantas y a que coste: 'make evals-dryrun'). Necesita un ARM=on previo con el MISMO modelo. Continuar? [y/N] " ans; \
	[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || { echo "Cancelado."; exit 1; }
	ARM=sin-ajustes bash kit/evals/run.sh
	ARM=sin-skills  bash kit/evals/run.sh
	ARM=sin-mcp     bash kit/evals/run.sh
	@echo; python3 kit/evals/report.py

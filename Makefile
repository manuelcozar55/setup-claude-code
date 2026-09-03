.DEFAULT_GOAL := help

.PHONY: help install bootstrap test doctor mutantes langsmith-local langsmith-arbol phoenix phoenix-push evals-dryrun evals-paid evals-ablacion-paid

help: ## Lista los targets disponibles
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*##"}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Instala el kit en CLAUDE_HOME (default $HOME/.claude)
	bash kit/install.sh

bootstrap: ## De cero a sesion verde: perfil, kit, doctor y oraculo. El comando de un companero nuevo.
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
	@echo "    Headroom NO se instala aqui a proposito: es opt-in, y en el perfil de uso"
	@echo "    medido rinde un 0,8 % de tokens a cambio de 512 ms por peticion. Lee"
	@echo "    kit/docs/10-onboarding.md antes de decidir; si lo quieres:"
	@echo "        bash kit/install.sh --with-headroom"

test: ## Corre las suites de test (NO incluye el eval set: ese cuesta dinero)
	bash kit/test/test_guards.sh
	bash kit/test/test_guards_falsifiability.sh
	bash kit/test/test_secret_content_gitleaks.sh
	bash kit/test/test_scan_secrets.sh
	bash kit/test/test_install.sh
	bash kit/test/test_install_settings_merge.sh
	bash kit/test/test_doctor.sh
	bash kit/test/test_doctor_drift.sh
	bash kit/test/test_skill_fork.sh
	bash kit/test/test_install_platform_gate.sh
	bash kit/test/test_install_gitleaks.sh
	bash kit/test/test_install_gitleaks_checksum.sh
	bash kit/test/test_enable_secrets_layer2.sh
	bash kit/test/test_gitattributes.sh
	bash kit/test/test_exec_modes.sh
	bash kit/test/test_optional_hook.sh
	bash kit/test/test_clean_install_resilience.sh
	bash kit/test/test_doctor_base_url.sh
	bash kit/test/test_with_headroom.sh
	bash kit/test/test_headroom_guardrails.sh
	bash kit/test/test_metrics.sh
	bash kit/test/test_detect_oracle.sh
	bash kit/test/test_auto_spec.sh
	bash kit/test/test_autonomy.sh
	bash kit/test/test_verify_gate.sh
	bash kit/test/test_harness_structure.sh
	bash kit/test/test_install_diff_first.sh
	bash kit/test/test_uninstall.sh
	bash kit/test/test_doc_claims.sh
	bash kit/test/test_evals.sh

doctor: ## Verifica una instalacion existente del kit
	bash kit/doctor.sh

mutantes: ## Rompe cada sensor del eval a proposito y exige que la suite se ponga roja (gratis, ~4 min)
	python3 kit/evals/mutantes.py

langsmith-local: ## Levanta el receptor local de trazas en :1984 (gratis, sin Docker ni licencia)
	python3 kit/evals/langsmith_local.py

langsmith-arbol: ## Imprime el arbol de trazas que ya ha recibido el receptor local
	python3 kit/evals/langsmith_local.py --tree

phoenix: ## Levanta Phoenix en local (interfaz web en :6006). Sin Docker y sin licencia.
	~/.venvs/tools/bin/phoenix serve

phoenix-push: ## Sube runs.jsonl al Phoenix local (necesita 'make phoenix' en otra terminal)
	~/.venvs/tools/bin/python kit/evals/phoenix_push.py

evals-dryrun: ## Ensayo: cuantas llamadas y cuanto costaria, sin gastar nada
	DRYRUN=1 bash kit/evals/run.sh

evals-paid: ## Eval set, LOS DOS BRAZOS: llamadas REALES a la API. CUESTA DINERO. Pide confirmacion.
	@read -p "Esto corre los dos brazos sobre 20 tareas: llamadas reales a la API (cuantas y a que coste: 'make evals-dryrun'). Continuar? [y/N] " ans; \
	[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || { echo "Cancelado."; exit 1; }
	bash kit/evals/run.sh
	ARM=off bash kit/evals/run.sh
	@echo; python3 kit/evals/report.py

evals-ablacion-paid: ## Los 3 brazos de ablacion (E22): quita una pieza cada vez. MAS llamadas reales, sobre las de arriba.
	@read -p "Esto corre 3 brazos mas sobre 20 tareas: llamadas reales a la API (cuantas y a que coste: 'make evals-dryrun'). Necesita un ARM=on previo con el MISMO modelo. Continuar? [y/N] " ans; \
	[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || { echo "Cancelado."; exit 1; }
	ARM=sin-ajustes bash kit/evals/run.sh
	ARM=sin-skills  bash kit/evals/run.sh
	ARM=sin-mcp     bash kit/evals/run.sh
	@echo; python3 kit/evals/report.py

.DEFAULT_GOAL := help

.PHONY: help install test doctor evals-paid

help: ## Lista los targets disponibles
	@grep -hE '^[a-zA-Z_-]+:.*##' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*##"}; {printf "  %-14s %s\n", $$1, $$2}'

install: ## Instala el kit en CLAUDE_HOME (default $HOME/.claude)
	bash kit/install.sh

test: ## Corre las suites de test (NO incluye el eval set: ese cuesta dinero)
	bash kit/test/test_guards.sh
	bash kit/test/test_guards_falsifiability.sh
	bash kit/test/test_secret_content_gitleaks.sh
	bash kit/test/test_scan_secrets.sh
	bash kit/test/test_install.sh
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
	bash kit/test/test_with_headroom.sh
	bash kit/test/test_metrics.sh
	bash kit/test/test_detect_oracle.sh
	bash kit/test/test_auto_spec.sh
	bash kit/test/test_autonomy.sh
	bash kit/test/test_harness_structure.sh
	bash kit/test/test_install_diff_first.sh
	bash kit/test/test_uninstall.sh
	bash kit/test/test_doc_claims.sh
	bash kit/test/test_evals.sh

doctor: ## Verifica una instalacion existente del kit
	bash kit/doctor.sh

evals-paid: ## Eval set: 6 llamadas REALES a la API de Claude. CUESTA DINERO. Pide confirmacion.
	@read -p "Esto hace 6 llamadas reales a la API de Claude y cuesta dinero real. Continuar? [y/N] " ans; \\
	[ "$$ans" = "y" ] || [ "$$ans" = "Y" ] || { echo "Cancelado."; exit 1; }
	bash kit/evals/run.sh

CLUSTER    ?= observability
NAMESPACE  ?= monitoring
RELEASE    ?= kps
CHART_VER  ?=

.PHONY: up cluster install demo rules dashboards slack-secret lint test \
        port-forward-grafana port-forward-prometheus port-forward-alertmanager \
        break fix down

up: cluster install demo rules dashboards ## Everything, end to end

cluster: ## Create the kind cluster
	kind create cluster --config kind-config.yaml

install: ## Install kube-prometheus-stack
	helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
	helm repo update
	helm upgrade --install $(RELEASE) prometheus-community/kube-prometheus-stack \
	  --namespace $(NAMESPACE) --create-namespace \
	  -f helm/values.yaml $(if $(CHART_VER),--version $(CHART_VER)) --wait --timeout 10m

demo: ## Deploy demo app + load generator
	kubectl apply -f demo-app/app.yaml
	kubectl -n demo rollout status deploy/demo-app
	kubectl apply -f demo-app/load-generator.yaml

rules: ## Apply alert rules
	kubectl apply -f alerts/prometheus-rule.yaml

dashboards: ## Apply Grafana dashboards (picked up by sidecar)
	kubectl apply -f dashboards/

slack-secret: ## Create Slack webhook secret (needs SLACK_WEBHOOK_URL)
	@test -n "$$SLACK_WEBHOOK_URL" || (echo "Set SLACK_WEBHOOK_URL"; exit 1)
	kubectl -n $(NAMESPACE) create secret generic alertmanager-slack \
	  --from-literal=webhook-url="$$SLACK_WEBHOOK_URL" \
	  --dry-run=client -o yaml | kubectl apply -f -
	kubectl -n $(NAMESPACE) rollout restart statefulset/alertmanager-$(RELEASE)-alertmanager || true

lint: ## Validate rules with promtool
	yq '.spec' alerts/prometheus-rule.yaml > tests/rules.yaml
	promtool check rules tests/rules.yaml

test: lint ## Unit-test rules with promtool
	cd tests && promtool test rules alerts_test.yaml

port-forward-grafana: ## http://localhost:3000 (admin/admin)
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE)-grafana 3000:80

port-forward-prometheus: ## http://localhost:9090
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE)-prometheus 9090:9090

port-forward-alertmanager: ## http://localhost:9093
	kubectl -n $(NAMESPACE) port-forward svc/$(RELEASE)-alertmanager 9093:9093

break: ## Trigger alerts: scale app to zero and spike errors
	kubectl -n demo scale deploy/demo-app --replicas=0

fix: ## Restore the app
	kubectl -n demo scale deploy/demo-app --replicas=2

down: ## Delete the cluster
	kind delete cluster --name $(CLUSTER)

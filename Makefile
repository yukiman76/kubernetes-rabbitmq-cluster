.PHONY: deploy
DOCKER_REPOSITORY?=nanit
SUDO?=sudo

RABBITMQ_APP_NAME=rabbitmq
SERVICE_ACCOUNT=
RABBITMQ_SERVICE_NAME=rabbitmq
RABBITMQ_MANAGEMENT_SERVICE_NAME=rabbitmq-management
RABBITMQ_HEADLESS_SERVICE_NAME=rmq-cluster
RABBITMQ_DOCKER_DIR=docker
NAMESPACE?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/namespace)
RABBITMQ_IMAGE_TAG=$(shell git log -n 1 --pretty=format:%h $(RABBITMQ_DOCKER_DIR))
RABBITMQ_IMAGE_NAME=$(DOCKER_REPOSITORY)/$(RABBITMQ_APP_NAME):$(RABBITMQ_IMAGE_TAG)
RABBITMQ_REPLICAS?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/replicas)
RABBITMQ_DEFAULT_USER?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/user)
RABBITMQ_DEFAULT_PASS?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/password)
RABBITMQ_ERLANG_COOKIE?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/erlang_cookie)
RABBITMQ_EXPOSE_MANAGEMENT?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/expose_management)
RABBITMQ_HA_POLICY?=$(shell curl -s config/$(NANIT_ENV)/$(RABBITMQ_APP_NAME)/ha_policy)


define generate-rabbitmq-rbac
	sed -e 's/{{NAMESPACE}}/default/g' kube/rbac.yml
endef

define generate-rabbitmq-headless-svc
	sed -e 's/{{APP_NAME}}/$(RABBITMQ_APP_NAME)/g;s/{{SVC_NAME}}/$(RABBITMQ_HEADLESS_SERVICE_NAME)/g' kube/svc.headless.yml
endef

define generate-rabbitmq-management-svc
	sed -e 's/{{APP_NAME}}/$(RABBITMQ_APP_NAME)/g;s/{{SVC_NAME}}/$(RABBITMQ_MANAGEMENT_SERVICE_NAME)/g' kube/svc.management.yml
endef

define generate-rabbitmq-svc
	sed -e 's/{{APP_NAME}}/$(RABBITMQ_APP_NAME)/g;s/{{SVC_NAME}}/$(RABBITMQ_SERVICE_NAME)/g' kube/svc.yml
endef

define generate-rabbitmq-stateful-set
	if [ -z "$(RABBITMQ_REPLICAS)" ]; then echo "ERROR: RABBITMQ_REPLICAS is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_DEFAULT_USER)" ]; then echo "ERROR: RABBITMQ_DEFAULT_USER is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_DEFAULT_PASS)" ]; then echo "ERROR: RABBITMQ_DEFAULT_PASS is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_ERLANG_COOKIE)" ]; then echo "ERROR: RABBITMQ_ERLANG_COOKIE is empty!"; exit 1; fi
	sed -e 's/{{SVC_NAME}}/$(RABBITMQ_HEADLESS_SERVICE_NAME)/g;s/{{APP_NAME}}/$(RABBITMQ_APP_NAME)/g;s,{{IMAGE_NAME}},$(RABBITMQ_IMAGE_NAME),g;s/{{REPLICAS}}/$(RABBITMQ_REPLICAS)/g;s/{{RABBITMQ_DEFAULT_USER}}/$(RABBITMQ_DEFAULT_USER)/g;s/{{RABBITMQ_DEFAULT_PASS}}/$(RABBITMQ_DEFAULT_PASS)/g;s/{{RABBITMQ_ERLANG_COOKIE}}/$(RABBITMQ_ERLANG_COOKIE)/g' kube/stateful.set.yml
endef

define generate-rabbitmq-rbac-stateful-set
	if [ -z "$(RABBITMQ_REPLICAS)" ]; then echo "ERROR: RABBITMQ_REPLICAS is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_DEFAULT_USER)" ]; then echo "ERROR: RABBITMQ_DEFAULT_USER is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_DEFAULT_PASS)" ]; then echo "ERROR: RABBITMQ_DEFAULT_PASS is empty!"; exit 1; fi
	if [ -z "$(RABBITMQ_ERLANG_COOKIE)" ]; then echo "ERROR: RABBITMQ_ERLANG_COOKIE is empty!"; exit 1; fi
	sed -e 's/{{SVC_NAME}}/$(RABBITMQ_HEADLESS_SERVICE_NAME)/g;s/{{APP_NAME}}/$(RABBITMQ_APP_NAME)/g;s,{{IMAGE_NAME}},$(RABBITMQ_IMAGE_NAME),g;s/{{REPLICAS}}/$(RABBITMQ_REPLICAS)/g;s/{{RABBITMQ_DEFAULT_USER}}/$(RABBITMQ_DEFAULT_USER)/g;s/{{RABBITMQ_DEFAULT_PASS}}/$(RABBITMQ_DEFAULT_PASS)/g;s/{{RABBITMQ_ERLANG_COOKIE}}/$(RABBITMQ_ERLANG_COOKIE)/g' kube/stateful.set.rbac.yml
endef

define set-ha-policy-on-rabbitmq-cluster
	if [ "$(RABBITMQ_HA_POLICY)" != "" ]; then export RABBITMQ_HA_POLICY=$(RABBITMQ_HA_POLICY) && export NAMESPACE=$(NAMESPACE) && ./set_ha.sh ;fi
endef

deploy-rbac-rabbitmq:
	kubectl get clusterrole rabbit || $(call generate-rabbitmq-rbac) | kubectl create -f -
	kubectl get ns $(NAMESPACE) || kubectl create ns $(NAMESPACE)
	kubectl get svc -n $(NAMESPACE) $(RABBITMQ_APP_NAME) || $(call generate-rabbitmq-svc) | kubectl create -n $(NAMESPACE) -f -
	kubectl get svc -n $(NAMESPACE) $(RABBITMQ_HEADLESS_SERVICE_NAME) || $(call generate-rabbitmq-headless-svc) | kubectl create -n $(NAMESPACE) -f -
	if [ "$(RABBITMQ_EXPOSE_MANAGEMENT)" = "TRUE" ]; then kubectl get svc -n $(NAMESPACE) $(RABBITMQ_MANAGEMENT_SERVICE_NAME) || $(call generate-rabbitmq-management-svc) | kubectl create -n $(NAMESPACE) -f - ; fi
	$(call generate-rabbitmq-rbac-stateful-set) | kubectl apply -n $(NAMESPACE) -f -
	sleep 20
	$(call set-ha-policy-on-rabbitmq-cluster)
    
deploy-rabbitmq: docker-rabbitmq
	kubectl get ns $(NAMESPACE) || kubectl create ns $(NAMESPACE)
	kubectl get svc -n $(NAMESPACE) $(RABBITMQ_APP_NAME) || $(call generate-rabbitmq-svc) | kubectl create -n $(NAMESPACE) -f -
	kubectl get svc -n $(NAMESPACE) $(RABBITMQ_HEADLESS_SERVICE_NAME) || $(call generate-rabbitmq-headless-svc) | kubectl create -n $(NAMESPACE) -f -
	if [ "$(RABBITMQ_EXPOSE_MANAGEMENT)" = "TRUE" ]; then kubectl get svc -n $(NAMESPACE) $(RABBITMQ_MANAGEMENT_SERVICE_NAME) || $(call generate-rabbitmq-management-svc) | kubectl create -n $(NAMESPACE) -f - ; fi
	$(call generate-rabbitmq-stateful-set) | kubectl apply -n $(NAMESPACE) -f -
	$(call set-ha-policy-on-rabbitmq-cluster)

docker-rabbitmq:
	$(SUDO) docker pull $(RABBITMQ_IMAGE_NAME) || ($(SUDO) docker build -t $(RABBITMQ_IMAGE_NAME) $(RABBITMQ_DOCKER_DIR) && $(SUDO) docker push $(RABBITMQ_IMAGE_NAME))

deploy: deploy-rabbitmq

rbac: deploy-rbac-rabbitmq

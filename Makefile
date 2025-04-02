SHELL := /bin/bash

# Only extract these values if we're not running package-related commands (including "package")
ifneq ($(filter package pkg-%,$(MAKECMDGOALS)),)
    # Package-related commands, skip extraction of values
else
	# Define default values for NODE_TYPE and INTERNAL_IP
	NODE_TYPE ?= generic
	INTERNAL_IP ?= 127.0.0.1

	# Dynamically determine the CONFIG_FILE based on NODE_TYPE
	CONFIG_FILE := configurations/$(NODE_TYPE).yaml

	NAMESPACE := $(shell grep "namespace" $(CONFIG_FILE) | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')
	SERVICE_NAME := $(shell grep "service_name" $(CONFIG_FILE) | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')
	APP_NAME := $(shell grep "app_name" $(CONFIG_FILE) | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')

	ANYLOG_SERVER_PORT $(shell grep "ANYLOG_SERVER_PORT" $(CONFIG_FILE)  | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')
	ANYLOG_REST_PORT $(shell grep "ANYLOG_REST_PORT" $(CONFIG_FILE)  | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')
	ANYLOG_BROKER_PORT := $(shell grep "ANYLOG_BROKER_PORT" $(CONFIG_FILE)  | awk -F ":" '{print $$2}' | awk '{gsub(" ", ""); print}')
endif

# Help target to generate help (if needed)
help:
	@echo "Usage: make [target] where target can be one of:"
	@echo "  package       - Package the Helm charts"
	@echo "  up            - Start the containers and volumes"
	@echo "  down          - Stop the containers"
	@echo "  clean         - Stop and remove volumes"
	@echo "  pkg-volume    - Package the volume chart"
	@echo "  pkg-container - Package the container chart"

package: pkg-volume pkg-container

up: start-volume start-container

down: stop-container

clean: stop-container remove-volume

pkg-volume:
	@echo "Packaging volume chart..."
	helm package ./anylog-volumes

pkg-container:
	@echo "Packaging container chart..."
	helm package ./anylog-node

start-volume:
	@echo "Starting volume with Helm..."
	helm install ./anylog-node-volumes-0.0.0.tgz -f $(CONFIG_FILE) --name-template $(APP_NAME)-volume

start-container:
	@echo "Starting container with Helm..."
	helm install ./anylog-node-0.0.0.tgz -F $(CONFIG_FILE) --name-template $(APP_NAME)
	echo "Waiting for the pod to be in the 'Running' state..."
	$(MAKE) set-ports

stop-container:
	@echo "Stopping container..."
	helm uninstall $(APP_NAME)
	$(MAKE) disconnect-ports

remove-volume:
	@echo "Removing volume..."
	helm uninstall $(APP_NAME)-volume

set-ports:
	@echo "Waiting for pod to reach 'Running' state..."
	while true; do \
		POD_STATUS=$$(kubectl get pod -l app=$(APP_NAME) -o jsonpath="{.items[0].status.phase}" 2>/dev/null); \
		echo $$POD_STATUS; \
		if [ "$$POD_STATUS" == "Running" ]; then \
			echo "Pod is now running. Starting port forwarding..."; \
			break; \
		fi; \
		sleep 1; \
	done
	@echo "Starting port forwarding..."
	if [ -n "$(INTERNAL_IP)" ]; then \
		kubectl port-forward -n $(NAMESPACE) service/$(SERVICE_NAME) $(ANYLOG_SERVER_PORT):$(ANYLOG_SERVER_PORT) --address=$(INTERNAL_IP) > "$$HOME/port_$(HOSTNAME)_$(ANYLOG_SERVER_PORT).log" 2>&1 & \
		kubectl port-forward -n $(NAMESPACE) service/$(SERVICE_NAME) $(ANYLOG_REST_PORT):$(ANYLOG_REST_PORT) --address=$(INTERNAL_IP) > "$$HOME/port_$(HOSTNAME)_$(ANYLOG_REST_PORT).log" 2>&1 & \
		if [ -n "$(BROKER_PORT)" ]; then \
			kubectl port-forward -n $(NAMESPACE) service/$(SERVICE_NAME) $(BROKER_PORT):$(BROKER_PORT) --address=$(INTERNAL_IP) > "$$HOME/port_$(HOSTNAME)_$(BROKER_PORT).log" 2>&1 & \
		fi; \
	fi

disconnect-ports:
	@echo "Disconnecting ports..."
	kill -15 $$(`ps -ef | grep port-forward | grep $(ANYLOG_SERVER_PORT) | awk '{print $$2}'`)
	kill -15 $$(`ps -ef | grep port-forward | grep $(ANYLOG_REST_PORT) | awk '{print $$2}'`)
	if [ -n "$(BROKER_PORT)" ]; then \
		kill -15 $$(`ps -ef | grep port-forward | grep $(BROKER_PORT) | awk '{print $$2}'`); \
	fi

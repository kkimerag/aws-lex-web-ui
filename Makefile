# This Makefile is used to configure and deploy the sample app.
# It is used in CodeBuild by the CloudFormation stack.
# It can also be run from a local dev environment.
# It can either deploy a full build or use the prebuilt library in
# in the dist directory

# environment file provides config parameters
CONFIG_ENV := config/env.mk
include $(CONFIG_ENV)

all: build
.PHONY: all

WEBAPP_DIR := ./lex-web-ui
BUILD_DIR := build
DIST_DIR := dist
SRC_DIR := src
CONFIG_DIR := $(SRC_DIR)/config

# merge existing user modified lex-web-ui-loader-config.json during upgrade
# replace user custom-chatbot-style.css files during upgrade
CURRENT_CONFIG_FILE := $(WEBAPP_DIR)/current/user-lex-web-ui-loader-config.json
USER_CUSTOM_CSS_COPY := $(WEBAPP_DIR)/current/user-custom-chatbot-style.css

# Add PARENT_DOMAIN to S3 path. If not set, use 'default'
DOMAIN_PATH := $(shell echo $(PARENT_ORIGIN) | sed 's|https://||g' | sed 's|/.*||g')
ifeq ($(DOMAIN_PATH),)
DOMAIN_PATH := default
endif

# this install all the npm dependencies needed to build from scratch
install-deps:
	@echo "[INFO] Installing loader npm dependencies"
	npm install
	@echo "[INFO] Installing component npm dependencies"
	cd $(WEBAPP_DIR) && npm install
.PHONY: install-deps

load-current-config:
	@echo "[INFO] Using domain path: $(DOMAIN_PATH)"
	@echo "[INFO] Downloading current lex-web-ui-loader-config.json from s3 to merge user changes"
	@echo "[INFO] Downloading s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/lex-web-ui-loader-config.json if it exists or load defaults"
	-aws s3 ls "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/lex-web-ui-loader-config.json" && \
    	aws s3 cp "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/lex-web-ui-loader-config.json" "$(CURRENT_CONFIG_FILE)" || \
        cp "$(CONFIG_DIR)/default-lex-web-ui-loader-config.json" "$(CURRENT_CONFIG_FILE)"
	@echo "[INFO] Downloading s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/custom-chatbot-style.css file if it exists or load defaults"
	-aws s3 ls "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/custom-chatbot-style.css" && \
    	aws s3 cp "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/custom-chatbot-style.css" "$(USER_CUSTOM_CSS_COPY)" || \
        cp "$(DIST_DIR)/custom-chatbot-style.css" "$(USER_CUSTOM_CSS_COPY)"
.PHONY: load-current-config

# ... [rest of the Makefile remains the same] ...

sync-website: create-iframe-snippet
	@[ "$(WEBAPP_BUCKET)" ] || \
		(echo "[ERROR] WEBAPP_BUCKET variable not set" ; exit 1)
	@echo "[INFO] Using domain path: $(DOMAIN_PATH)"
	@echo "[INFO] copying web site files to [s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)]"
	aws s3 sync \
		--exclude Makefile \
		--exclude custom-chatbot-style.css \
		"$(DIST_DIR)" "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)"
	@echo "[INFO] Restoring existing custom css file"
	@[ -f "$(USER_CUSTOM_CSS_COPY)" ] && \
	aws s3 cp \
		--metadata-directive REPLACE --cache-control max-age=0 \
		"$(USER_CUSTOM_CSS_COPY)" "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/custom-chatbot-style.css"
	@echo "[INFO] Saving a backup copy of previous loader config json"
	aws s3 cp \
		"$(CURRENT_CONFIG_FILE)" "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)/lex-web-ui-loader-config.$(shell date +%Y%m%d%H%M%S).json"
	@echo "[INFO] copying config files"
	aws s3 sync  \
		--exclude '*' \
		--metadata-directive REPLACE --cache-control max-age=0 \
		--include 'lex-web-ui-loader-config.json' \
		--include 'initial_speech*.*' \
		--include 'all_done*.*' \
		--include 'there_was_an_error*.*' \
		"$(CONFIG_DIR)" "s3://$(WEBAPP_BUCKET)/$(DOMAIN_PATH)"
	@echo "[INFO] all done deploying"
.PHONY: sync-website
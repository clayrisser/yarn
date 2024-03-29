# File: /main.mk
# Project: yarn
# File Created: 28-11-2023 13:08:34
# Author: Clay Risser
# -----
# BitSpur (c) Copyright 2021 - 2023
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

NODE ?= node
YARN ?= $(NODE) $(PROJECT_ROOT)/.yarn/releases/yarn-$(shell $(ECHO) $(shell $(NODE) -e \
	"console.log(require('$(PROJECT_ROOT)/package.json').packageManager)") | \
	$(CUT) -d'@' -f2).cjs
NPM ?= $(call ternary,$(WHICH) npm,npm,$(YARN))

export BASE64_NOWRAP ?= $(call ternary,openssl version,openssl base64 -A,base64 -w0)

define yarn_binary
$(call ternary,$(WHICH) $(PROJECT_ROOT)/node_modules/.bin/$1,$(PROJECT_ROOT)/node_modules/.bin/$1,$(YARN) $1)
endef

BUN ?= $(call ternary,$(WHICH) bun,bun,$(YARN) bun)
PREFER_BUN ?=

define b64_encode_each
$(shell for i in $1; do \
	$(ECHO) $$i | $(BASE64_NOWRAP) && echo; \
done)
endef

define b64_decode_each
$(shell for i in $1; do \
	$(ECHO) $$i | $(BASE64_NOWRAP) -d; \
done)
endef

MONOREPO ?= 0

ifneq (0,$(MONOREPO))
ifeq (,$(CALCULATED_WORKSPACES))
$(info calculating monorepo workspaces ⌛)

define B64_WORKSPACES
$(call b64_encode_each,$(shell for w in \
	$$($(NODE) -e "console.log((require('./package.json').workspaces || []).join(' '))"); do \
	if [ -d "$$w" ] && [ -f "$$w/package.json" ]; then \
		$(ECHO) "$$w"; \
	fi; \
done))
endef
export B64_WORKSPACES

define WORKSPACES
$(call b64_decode_each,$(B64_WORKSPACES))
endef
export WORKSPACES

define WORKSPACE_NAMES
$(shell for w in $(WORKSPACES); do \
	$(ECHO) $$w | $(GREP) -oE '[^\/]+$$'; \
done)
endef
export WORKSPACE_NAMES

export CALCULATED_WORKSPACES := 1
endif
endif

ifeq (,$(WORKSPACES))
	MONOREPO = 0
else
	MONOREPO = 1
endif

define b64_workspace_paths
$(shell for i in $(B64_WORKSPACES); do \
	$(ECHO) $(PROJECT_ROOT)/$$(echo $$i | $(BASE64_NOWRAP) -d)$$([ '$1' = '' ] || $(ECHO) '/$1') | \
	$(BASE64_NOWRAP) && echo; \
done)
endef

define workspace_paths
$(shell for w in $(call b64_workspace_paths,$1); do \
	$(ECHO) $$w | $(BASE64_NOWRAP) -d; \
done)
endef

define map_workspace
$(shell for w in $(WORKSPACES); do \
	if [ "$$($(ECHO) $$w | $(GREP) -oE '[^\/]+$$')" = "$1" ]; then \
		$(ECHO) $$w; \
	fi \
done)
endef

define workspace_exec_foreach
for w in $(call b64_workspace_paths); do \
	$(CD) "$$($(ECHO) $$w | $(BASE64_NOWRAP) -d)" && $1; \
done
endef

define workspace_foreach
$(call workspace_exec_foreach,$(MKPM_MAKE) $1 ARGS=$2 || $(TRUE))
endef

define workspace_foreach_help
for w in $(call b64_workspace_paths); do \
	$(EXPORT) WORKSPACE=$$($(ECHO) $$w | $(BASE64_NOWRAP) -d) && \
		$(MKPM_MAKE) -C $$WORKSPACE $$([ "$1" = "" ] && echo $(HELP) || echo $1) ARGS=$2 \
		HELP_PREFIX="$$($(ECHO) $$WORKSPACE | $(GREP) -oE '[^\/]+$$')/" 2>$(NULL) || \
		$(TRUE); \
done
endef

define shell_arr_to_json_arr
$(shell (for i in $1; do echo $$i; done) | $(JQ) -R . | $(JQ) -s .)
endef

export CSPELLRC := $(MKPM_TMP)/cspellrc.json
define cspell
[ '$?' = '' ] && \
	$(ECHO) 'CSpell: Files checked: 0, Issues found: 0 in 0 files' || \
	$(CSPELL) $2 $1
endef

define prettier
$(PRETTIER) --write $2 $1
endef

define eslint_format
(for i in $1; do echo $$i | \
	$(GREP) -E "\.[jt]sx?$$"; \
done) | $(XARGS) $(ESLINT) $2 --fix >$(NULL) || $(TRUE)
endef

export ESLINT_REPORT := $(MKPM_TMP)/eslintReport.json
define eslint
$(ESLINT) -f json -o $(ESLINT_REPORT) $1 $(NOFAIL) && \
$(ESLINT) $2 $1
endef

export JEST_TEST_RESULTS := $(MKPM_TMP)/jestTestResults.json
export COVERAGE_DIRECTORY := $(MKPM_TMP)/coverage

ifeq (1,$(PREFER_BUN))
define test
$(BUN) test --coverage $2
endef
else
define test
$(MKDIR) -p $(MKPM_TMP)/reports $(NOOUT) && \
NODE_OPTIONS="--experimental-vm-modules" $(JEST) \
	--pass-with-no-tests --json --outputFile=$(JEST_TEST_RESULTS) --coverage \
	--coverageDirectory=$(COVERAGE_DIRECTORY) --testResultsProcessor=jest-sonar-reporter \
	--collectCoverageFrom='$(call shell_arr_to_json_arr,$1)' --findRelatedTests $1 $2
endef
endif

define YARN_GIT_CLEAN_FLAGS
$(call git_clean_flags,node_modules) \
	$(call git_clean_flags,.yarn) \
	-e $(BANG)/package-lock.json \
	-e $(BANG)/pnpm-lock.yaml \
	-e $(BANG)/yarn.lock
endef

define gitlab_token
$(shell AUTH=$$($(CAT) $(HOME)/.docker/config.json 2>$(NULL) | $(JQ) -r '.auths["registry.gitlab.com"].auth' 2>$(NULL)) && \
TOKEN="" && \
if [ "$$AUTH" != "" ] && [ "$$AUTH" != "null" ]; then \
	TOKEN=$$($(ECHO) "$$AUTH" | $(BASE64_NOWRAP) -d 2>$(NULL) | $(CUT) -d':' -f2 2>$(NULL)); \
else \
	DOCKER_CREDENTIAL=$$($(ECHO) docker-credential-$$($(CAT) $(HOME)/.docker/config.json 2>$(NULL) | $(JQ) -r '.credsStore' 2>$(NULL))) && \
    if $(WHICH) $$DOCKER_CREDENTIAL 2>$(NULL) >$(NULL); then \
        TOKEN=$$($(ECHO) registry.gitlab.com | $$DOCKER_CREDENTIAL get 2>$(NULL) | $(JQ) -r '.Secret' 2>$(NULL)); \
	fi; \
fi && \
$(ECHO) $$TOKEN)
endef

export NPM_AUTH_TOKEN ?= $(call ternary,[ "$(call gitlab_token)" != "" ],$(call gitlab_token),)

CACHE_ENVS += \
	B64_WORKSPACES \
	BASE64_NOWRAP \
	BUN \
	CALCULATED_WORKSPACES \
	MONOREPO \
	WORKSPACES \
	WORKSPACE_NAMES

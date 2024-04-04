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
	BASE64_NOWRAP \
	BUN

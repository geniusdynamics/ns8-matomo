<!--
  Copyright (C) 2024 Nethesis S.r.l.
  SPDX-License-Identifier: GPL-3.0-or-later
-->
<template>
  <cv-grid fullWidth>
    <cv-row>
      <cv-column class="page-title">
        <h2>{{ $t("settings.title") }}</h2>
      </cv-column>
    </cv-row>
    <cv-row v-if="error.getConfiguration">
      <cv-column>
        <NsInlineNotification
          kind="error"
          :title="$t('action.get-configuration')"
          :description="error.getConfiguration"
          :showCloseButton="false"
        />
      </cv-column>
    </cv-row>
    <cv-row>
      <cv-column>
        <cv-tile light>
          <cv-form @submit.prevent="configureModule">
            <cv-text-input
              :label="$t('settings.matomo_fqdn')"
              placeholder="matomo.example.org"
              v-model.trim="host"
              class="mg-bottom"
              :invalid-message="$t(error.host)"
              :disabled="loading.getConfiguration || loading.configureModule"
              ref="host"
            >
            </cv-text-input>
            <cv-toggle
              value="letsEncrypt"
              :label="$t('settings.lets_encrypt')"
              v-model="isLetsEncryptEnabled"
              :disabled="loading.getConfiguration || loading.configureModule"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <cv-toggle
              value="httpToHttps"
              :label="$t('settings.http_to_https')"
              v-model="isHttpToHttpsEnabled"
              :disabled="loading.getConfiguration || loading.configureModule"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <!-- first installation: administrator account -->
            <template v-if="!installed && !loading.getConfiguration">
              <h4 class="mg-bottom">{{ $t("settings.admin_title") }}</h4>
              <p class="mg-bottom note">{{ $t("settings.admin_intro") }}</p>
              <cv-text-input
                :label="$t('settings.admin_user')"
                v-model.trim="adminUser"
                placeholder="admin"
                class="mg-bottom"
                :invalid-message="$t(error.admin_user)"
                :disabled="loading.configureModule"
                ref="admin_user"
              />
              <cv-text-input
                type="password"
                :label="$t('settings.admin_password')"
                v-model="adminPassword"
                :helper-text="$t('settings.admin_password_helper')"
                :password-hide-label="$t('ldap_login.hide')"
                :password-show-label="$t('ldap_login.show')"
                class="mg-bottom"
                :invalid-message="$t(error.admin_password)"
                :disabled="loading.configureModule"
                ref="admin_password"
              />
              <cv-text-input
                :label="$t('settings.admin_email')"
                v-model.trim="adminEmail"
                placeholder="admin@example.org"
                class="mg-bottom"
                :invalid-message="$t(error.admin_email)"
                :disabled="loading.configureModule"
                ref="admin_email"
              />
              <cv-text-input
                :label="$t('settings.site_url')"
                v-model.trim="siteUrl"
                placeholder="https://www.example.org"
                :helper-text="$t('settings.site_url_helper')"
                class="mg-bottom"
                :invalid-message="$t(error.site_url)"
                :disabled="loading.configureModule"
                ref="site_url"
              />
            </template>
            <!-- login with a user domain or LDAP server -->
            <h4 class="mg-bottom">{{ $t("settings.login_title") }}</h4>
            <cv-toggle
              value="ldapEnabled"
              :label="$t('settings.ldap_enabled')"
              v-model="ldapEnabled"
              :disabled="loading.getConfiguration || loading.configureModule"
              class="mg-bottom"
            >
              <template slot="text-left">{{
                $t("settings.disabled")
              }}</template>
              <template slot="text-right">{{
                $t("settings.enabled")
              }}</template>
            </cv-toggle>
            <template v-if="ldapEnabled">
              <p class="mg-bottom note">{{ $t("settings.ldap_intro") }}</p>
              <LdapLogin
                v-model="ldap"
                :userDomains="userDomains"
                :bindPasswordSet="ldapBindPasswordSet"
                :errors="ldapErrors"
                :disabled="loading.getConfiguration || loading.configureModule"
                ref="ldap"
                class="maxwidth mg-bottom"
              />
              <cv-dropdown
                :label="$t('settings.ldap_view_access')"
                v-model="ldapViewAccess"
                :helper-text="$t('settings.ldap_view_access_helper')"
                :disabled="loading.getConfiguration || loading.configureModule"
                class="maxwidth mg-bottom"
              >
                <cv-dropdown-item value="none">{{
                  $t("settings.ldap_view_access_none")
                }}</cv-dropdown-item>
                <cv-dropdown-item value="all">{{
                  $t("settings.ldap_view_access_all")
                }}</cv-dropdown-item>
              </cv-dropdown>
            </template>
            <cv-row v-if="error.configureModule">
              <cv-column>
                <NsInlineNotification
                  kind="error"
                  :title="$t('action.configure-module')"
                  :description="error.configureModule"
                  :showCloseButton="false"
                />
              </cv-column>
            </cv-row>
            <NsButton
              kind="primary"
              :icon="Save20"
              :loading="loading.configureModule"
              :disabled="loading.getConfiguration || loading.configureModule"
              >{{ $t("settings.save") }}</NsButton
            >
          </cv-form>
        </cv-tile>
      </cv-column>
    </cv-row>
  </cv-grid>
</template>

<script>
import to from "await-to-js";
import { mapState } from "vuex";
import LdapLogin, {
  ldapFromConfiguration,
  validateLdap,
} from "@/components/LdapLogin";
import {
  QueryParamService,
  UtilService,
  TaskService,
  IconService,
  PageTitleService,
} from "@nethserver/ns8-ui-lib";

export default {
  name: "Settings",
  components: { LdapLogin },
  mixins: [
    TaskService,
    IconService,
    UtilService,
    QueryParamService,
    PageTitleService,
  ],
  pageTitle() {
    return this.$t("settings.title") + " - " + this.appName;
  },
  data() {
    return {
      q: {
        page: "settings",
      },
      urlCheckInterval: null,
      host: "",
      isLetsEncryptEnabled: false,
      isHttpToHttpsEnabled: true,
      installed: true,
      adminUser: "",
      adminPassword: "",
      adminEmail: "",
      siteUrl: "",
      ldapEnabled: false,
      ldapViewAccess: "none",
      ldap: ldapFromConfiguration({}),
      ldapBindPasswordSet: false,
      userDomains: [],
      ldapErrors: {},
      loading: {
        getConfiguration: false,
        configureModule: false,
      },
      error: {
        getConfiguration: "",
        configureModule: "",
        host: "",
        lets_encrypt: "",
        http2https: "",
        admin_user: "",
        admin_password: "",
        admin_email: "",
        site_url: "",
      },
    };
  },
  computed: {
    ...mapState(["instanceName", "core", "appName"]),
  },
  created() {
    this.getConfiguration();
  },
  beforeRouteEnter(to, from, next) {
    next((vm) => {
      vm.watchQueryData(vm);
      vm.urlCheckInterval = vm.initUrlBindingForApp(vm, vm.q.page);
    });
  },
  beforeRouteLeave(to, from, next) {
    clearInterval(this.urlCheckInterval);
    next();
  },
  methods: {
    async getConfiguration() {
      this.loading.getConfiguration = true;
      this.error.getConfiguration = "";
      const taskAction = "get-configuration";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.getConfigurationAborted
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.getConfigurationCompleted
      );

      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          extra: {
            title: this.$t("action." + taskAction),
            isNotificationHidden: true,
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.getConfiguration = this.getErrorMessage(err);
        this.loading.getConfiguration = false;
        return;
      }
    },
    getConfigurationAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.getConfiguration = this.$t("error.generic_error");
      this.loading.getConfiguration = false;
    },
    getConfigurationCompleted(taskContext, taskResult) {
      const config = taskResult.output;
      this.host = config.host;
      this.isLetsEncryptEnabled = config.lets_encrypt;
      this.isHttpToHttpsEnabled = config.http2https;
      this.installed = config.installed;
      this.ldapEnabled = config.ldap_enabled;
      this.ldapViewAccess = config.ldap_view_access || "none";
      this.userDomains = config.user_domains || [];
      this.ldap = ldapFromConfiguration(config);
      this.ldapBindPasswordSet = !!config.ldap_bind_password_set;
      this.adminPassword = "";

      this.loading.getConfiguration = false;
      this.focusElement("host");
    },
    validateConfigureModule() {
      this.clearErrors(this);
      this.ldapErrors = {};

      let isValidationOk = true;
      const fail = (field, message) => {
        this.error[field] = message;
        if (isValidationOk) {
          this.focusElement(field);
        }
        isValidationOk = false;
      };
      if (!this.host) {
        fail("host", "common.required");
      }
      if (!this.installed) {
        if (!this.adminUser) {
          fail("admin_user", "common.required");
        }
        if (this.adminPassword.length < 12) {
          fail("admin_password", "settings.admin_password_too_short");
        }
        if (!/^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(this.adminEmail)) {
          fail("admin_email", "settings.admin_email_invalid");
        }
      }
      if (this.ldapEnabled) {
        const ldapErrors = validateLdap(this.ldap, this.ldapBindPasswordSet);
        for (const [field, msg] of ldapErrors) {
          this.$set(this.ldapErrors, field, msg);
        }
        if (ldapErrors.length && isValidationOk) {
          this.$refs.ldap.focus(ldapErrors[0][0]);
        }
        if (ldapErrors.length) {
          isValidationOk = false;
        }
      }
      return isValidationOk;
    },
    configureModuleValidationFailed(validationErrors) {
      this.loading.configureModule = false;
      let focusAlreadySet = false;

      for (const validationError of validationErrors) {
        const param = validationError.parameter;
        if (
          param.startsWith("ldap_") &&
          !["ldap_enabled", "ldap_view_access"].includes(param)
        ) {
          this.$set(
            this.ldapErrors,
            param,
            "ldap_login." + validationError.error
          );
          if (!focusAlreadySet && this.$refs.ldap) {
            this.$refs.ldap.focus(param);
            focusAlreadySet = true;
          }
          continue;
        }
        // set i18n error message
        this.error[param] = "settings." + validationError.error;

        if (!focusAlreadySet) {
          this.focusElement(param);
          focusAlreadySet = true;
        }
      }
    },
    async configureModule() {
      const isValidationOk = this.validateConfigureModule();
      if (!isValidationOk) {
        return;
      }

      this.loading.configureModule = true;
      const taskAction = "configure-module";
      const eventId = this.getUuid();

      // register to task error
      this.core.$root.$once(
        `${taskAction}-aborted-${eventId}`,
        this.configureModuleAborted
      );

      // register to task validation
      this.core.$root.$once(
        `${taskAction}-validation-failed-${eventId}`,
        this.configureModuleValidationFailed
      );

      // register to task completion
      this.core.$root.$once(
        `${taskAction}-completed-${eventId}`,
        this.configureModuleCompleted
      );
      const res = await to(
        this.createModuleTaskForApp(this.instanceName, {
          action: taskAction,
          data: this.configureData(),
          extra: {
            title: this.$t("settings.instance_configuration", {
              instance: this.instanceName,
            }),
            description: this.$t("settings.configuring"),
            eventId,
          },
        })
      );
      const err = res[0];

      if (err) {
        console.error(`error creating task ${taskAction}`, err);
        this.error.configureModule = this.getErrorMessage(err);
        this.loading.configureModule = false;
        return;
      }
    },
    configureData() {
      const data = {
        host: this.host,
        lets_encrypt: this.isLetsEncryptEnabled,
        http2https: this.isHttpToHttpsEnabled,
        ldap_enabled: this.ldapEnabled,
        ldap_view_access: this.ldapViewAccess,
      };
      if (!this.installed) {
        Object.assign(data, {
          admin_user: this.adminUser,
          admin_password: this.adminPassword,
          admin_email: this.adminEmail,
          site_url: this.siteUrl,
        });
      }
      if (this.ldapEnabled) {
        Object.assign(data, this.ldap);
      }
      return data;
    },
    configureModuleAborted(taskResult, taskContext) {
      console.error(`${taskContext.action} aborted`, taskResult);
      this.error.configureModule = this.$t("error.generic_error");
      this.loading.configureModule = false;
    },
    configureModuleCompleted() {
      this.loading.configureModule = false;

      // reload configuration
      this.getConfiguration();
    },
  },
};
</script>

<style scoped lang="scss">
@import "../styles/carbon-utils";
.mg-bottom {
  margin-bottom: $spacing-06;
}

.maxwidth {
  max-width: 38rem;
}

.note {
  max-width: 38rem;
  color: #525252;
}
</style>

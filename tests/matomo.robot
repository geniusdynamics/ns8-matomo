*** Settings ***
Library    SSHLibrary

*** Variables ***
${HOST_OPTS}    "host": "matomo.test.local", "lets_encrypt": false, "http2https": false

*** Test Cases ***
Check if matomo is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check if invalid settings are rejected
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{${HOST_OPTS}, "admin_user": "admin", "admin_password": "short", "admin_email": "admin@test.local"}'
    ...    return_rc=True  return_stdout=False
    Should Not Be Equal As Integers    ${rc}  0
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{${HOST_OPTS}, "ldap_enabled": true, "ldap_source": "custom", "ldap_url": "http://ldap.test.local"}'
    ...    return_rc=True  return_stdout=False
    Should Not Be Equal As Integers    ${rc}  0

Check if matomo can be configured and installed
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{${HOST_OPTS}, "admin_user": "admin", "admin_password": "Robot-Test-Password-1", "admin_email": "admin@test.local"}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    api-cli run module/${module_id}/get-configuration --data '{}'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Contain    ${output}    "installed": true
    Should Not Contain    ${output}    Robot-Test-Password-1

Check if the web installer is closed
    ${output}  ${rc} =    Execute Command    curl -s -H 'Host: matomo.test.local' 'http://127.0.0.1/index.php?module=Installation&action=databaseSetup'
    ...    return_rc=True
    Should Not Contain    ${output}    databasesetupform
    ${output}  ${rc} =    Execute Command    curl -s -H 'Host: matomo.test.local' http://127.0.0.1/
    ...    return_rc=True
    Should Contain    ${output}    form_login

Check if the visitor address and the email sender are configured
    ${network} =    Execute Command    runagent python3 -c 'import agent; print(agent.redis_connect(use_replica=True).get("cluster/network"))'
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} cat common.config.ini.php
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Contain    ${output}    proxy_ips[] = "${network}"
    Should Contain    ${output}    noreply_email_address = "noreply@test.local"
    # the test cluster has no smarthost: Matomo gets no [mail] section
    ${smarthost} =    Execute Command    api-cli run cluster/get-smarthost
    IF    '"enabled": false' in '''${smarthost}'''
        Should Not Contain    ${output}    [mail]
    END

Check if INI values with special characters are read back unchanged
    # "${", quotes and backslashes in passwords must not change or break the
    # configuration: ini_value() in the module, Matomo's IniReader in the app
    Put File    ${CURDIR}/ini-roundtrip.py    /tmp/ini-roundtrip.py
    Put File    ${CURDIR}/ini-roundtrip.php    /tmp/ini-roundtrip.php
    ${rc} =    Execute Command    runagent -m ${module_id} podman cp /tmp/ini-roundtrip.php matomo-app:/tmp/ini-roundtrip.php
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} python3 - < /tmp/ini-roundtrip.py | runagent -m ${module_id} podman exec -i matomo-app php /tmp/ini-roundtrip.php
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Be Equal As Strings    ${output}    ok

Check if PHP in the app container has the PHP2Shell fix
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec matomo-app php -r '$f = ["8.2" => "8.2.35", "8.3" => "8.3.36", "8.4" => "8.4.27", "8.5" => "8.5.12"]; $b = PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION; echo isset($f[$b]) && version_compare(PHP_VERSION, $f[$b], ">=") ? "ok" : PHP_VERSION;'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Be Equal As Strings    ${output}    ok

Check if the LDAP login can be enabled and disabled
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{${HOST_OPTS}, "ldap_enabled": true, "ldap_view_access": "all", "ldap_source": "custom", "ldap_url": "ldap://127.0.0.1:3890", "ldap_schema": "rfc2307", "ldap_base_dn": "dc=test,dc=local", "ldap_bind_dn": "cn=reader,dc=test,dc=local", "ldap_bind_password": "Robot-Bind-1"}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec -u www-data matomo-app php /var/www/html/console plugin:list
    ...    return_rc=True
    Should Match Regexp    ${output}    LoginLdap +\\|.*Activated
    ${output}  ${rc} =    Execute Command    api-cli run module/${module_id}/get-configuration --data '{}'
    ...    return_rc=True
    Should Contain    ${output}    "ldap_bind_password_set": true
    Should Not Contain    ${output}    Robot-Bind-1
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{${HOST_OPTS}, "ldap_enabled": false}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec -u www-data matomo-app php /var/www/html/console plugin:list
    ...    return_rc=True
    Should Not Match Regexp    ${output}    LoginLdap +\\|.*Activated

Check if a newer bundled plugin and other plugins survive a code update
    # LoginLdap updated through the Marketplace and a plugin that the image
    # does not bundle must survive the restart and the copy of the Matomo code
    Put File    ${CURDIR}/plugin-survival.sh    /tmp/plugin-survival.sh
    ${rc} =    Execute Command    runagent -m ${module_id} podman cp /tmp/plugin-survival.sh matomo-app:/tmp/plugin-survival.sh
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${rc} =    Execute Command    runagent -m ${module_id} podman exec matomo-app sh /tmp/plugin-survival.sh prepare
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user restart matomo-app
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0
    ${output} =    Execute Command    runagent -m ${module_id} podman logs --since 5m matomo-app 2>&1
    Should Contain    ${output}    ns8-update-code: Matomo 5.0.0 ->
    Should Contain    ${output}    ns8-update-code: plugin LoginLdap 99.0.0 kept
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec matomo-app sh /tmp/plugin-survival.sh check
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Be Equal As Strings    ${output}    ok
    ${rc} =    Execute Command    runagent -m ${module_id} podman exec matomo-app sh /tmp/plugin-survival.sh cleanup
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if report archiving is scheduled
    ${rc} =    Execute Command    runagent -m ${module_id} systemctl --user is-active matomo-archive.timer
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if matomo is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

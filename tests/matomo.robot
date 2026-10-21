*** Settings ***
Library    SSHLibrary

*** Test Cases ***
Check if matomo is installed correctly
    ${output}  ${rc} =    Execute Command    add-module ${IMAGE_URL} 1
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    &{output} =    Evaluate    ${output}
    Set Suite Variable    ${module_id}    ${output.module_id}

Check if matomo can be configured
    ${rc} =    Execute Command    api-cli run module/${module_id}/configure-module --data '{"host": "matomo.test.local", "lets_encrypt": false, "http2https": false}'
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if matomo works as expected
    ${rc} =    Execute Command    curl -f -H 'Host: matomo.test.local' http://127.0.0.1/
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

Check if PHP in the app container has the PHP2Shell fix
    ${output}  ${rc} =    Execute Command    runagent -m ${module_id} podman exec matomo-app php -r '$f = ["8.2" => "8.2.35", "8.3" => "8.3.36", "8.4" => "8.4.27", "8.5" => "8.5.12"]; $b = PHP_MAJOR_VERSION . "." . PHP_MINOR_VERSION; echo isset($f[$b]) && version_compare(PHP_VERSION, $f[$b], ">=") ? "ok" : PHP_VERSION;'
    ...    return_rc=True
    Should Be Equal As Integers    ${rc}  0
    Should Be Equal As Strings    ${output}    ok

Check if matomo is removed correctly
    ${rc} =    Execute Command    remove-module --no-preserve ${module_id}
    ...    return_rc=True  return_stdout=False
    Should Be Equal As Integers    ${rc}  0

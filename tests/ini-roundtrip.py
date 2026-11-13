# Test of tests/matomo.robot: values through ini_value() of the module, as a
# JSON line followed by an INI section, for ini-roundtrip.php in matomo-app
import json, matomoconfig
values = ["x${y", "p'a\"b\\c${HOME};d=e", 'a\\"; injected = 1', "$", "$$x", "end\\"]
print(json.dumps(values))
print("[t]")
for i, v in enumerate(values):
    print(f"v{i} = {matomoconfig.ini_value(v)}")

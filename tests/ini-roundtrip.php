<?php
// Test of tests/matomo.robot: read the output of ini-roundtrip.py with
// Matomo's IniReader and print "ok" if every value comes back unchanged
require "/usr/src/matomo/vendor/autoload.php";
[$json, $ini] = explode("\n", stream_get_contents(STDIN), 2);
$parsed = (new \Matomo\Ini\IniReader())->readString($ini);
echo array_values($parsed["t"]) === json_decode($json, true) ? "ok" : json_encode($parsed);

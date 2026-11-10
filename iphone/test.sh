#!/bin/bash
#
# Runs the native Hyperloop iOS unit tests (scheme "hyperloop", testable "Tests")
# on an available iOS simulator and verifies the result bundle.
#
# Exits nonzero when the build or any test fails, the destination is invalid,
# the output formatter fails, or the result bundle is missing, unreadable or
# reports zero executed tests.
#
# Environment:
#   NATIVE_TEST_OUTPUT_DIR      Where the raw log, JUnit report and .xcresult are
#                               written (default: <script dir>/build/native-tests)
#   NATIVE_TEST_DESTINATION_ID  Simulator UDID to use instead of auto-selection
#
# Output is formatted with xcpretty (plus a JUnit report) when it is on PATH;
# otherwise the raw xcodebuild output is printed. The raw log is always kept,
# and a formatter that exits early does not interrupt xcodebuild.
#
set -u -o pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
PROJECT="$SCRIPT_DIR/hyperloop.xcodeproj"
SCHEME=hyperloop
OUTPUT_DIR=${NATIVE_TEST_OUTPUT_DIR:-$SCRIPT_DIR/build/native-tests}
RESULT_BUNDLE="$OUTPUT_DIR/NativeTests.xcresult"
RAW_LOG="$OUTPUT_DIR/xcodebuild.log"
JUNIT_REPORT="$OUTPUT_DIR/junit.xml"

fail() {
	echo "error: $*" >&2
	exit 1
}

select_simulator() {
	local sdk_version deployment_target
	sdk_version=$(xcrun --sdk iphonesimulator --show-sdk-version) || fail "cannot determine the iphonesimulator SDK version"
	local settings
	settings=$(xcodebuild -project "$PROJECT" -scheme "$SCHEME" -sdk iphonesimulator -showBuildSettings 2>&1) \
		|| fail "cannot read build settings for scheme $SCHEME:"$'\n'"$settings"
	deployment_target=$(printf '%s\n' "$settings" \
		| awk '$1 == "IPHONEOS_DEPLOYMENT_TARGET" { print $3 }' | sort -t . -k1,1n -k2,2n | tail -1)
	[ -n "$deployment_target" ] || fail "cannot determine IPHONEOS_DEPLOYMENT_TARGET for scheme $SCHEME"

	# Prints "<udid>\t<name>\t<iOS version>" for an available iPhone simulator whose runtime
	# (compared as major.minor) is within [deployment target, SDK version]. Exits 2 when
	# simctl fails or its output is unexpected, 1 when no simulator qualifies.
	local status=0 simulator
	simulator=$(/usr/bin/python3 -I -u -c '
import json, subprocess, sys

def ver(s):
    return tuple(int(p) for p in s.split(".")[:2])

def simctl(kind):
    try:
        out = subprocess.run(["xcrun", "simctl", "list", "-j", kind, "available"],
                             check=True, stdout=subprocess.PIPE).stdout
        return json.loads(out)[kind]
    except (subprocess.CalledProcessError, OSError, ValueError, KeyError) as e:
        print("error: simctl cannot list %s: %s" % (kind, e), file=sys.stderr)
        sys.exit(2)

sdk, minimum = ver(sys.argv[1]), ver(sys.argv[2])
runtimes = simctl("runtimes")
devices = simctl("devices")

candidates = []
try:
    for rt in runtimes:
        is_ios = rt.get("platform") == "iOS" or ".SimRuntime.iOS-" in rt["identifier"]
        if not is_ios or not rt.get("isAvailable") or not (minimum <= ver(rt["version"]) <= sdk):
            continue
        for dev in devices.get(rt["identifier"], []):
            if dev.get("isAvailable") and ".SimDeviceType.iPhone" in dev.get("deviceTypeIdentifier", ""):
                candidates.append((ver(rt["version"]), dev["name"], dev["udid"], rt["version"]))
except (KeyError, TypeError, ValueError, AttributeError) as e:
    print("error: unexpected simctl output: %r" % e, file=sys.stderr)
    sys.exit(2)

if not candidates:
    sys.exit(1)
# Newest runtime first; prefer stock "iPhone ..." devices over custom-named ones.
candidates.sort(key=lambda c: (tuple(-p for p in c[0]), not c[1].startswith("iPhone"), c[1]))
_, name, udid, version = candidates[0]
print(udid + "\t" + name + "\t" + version)
' "$sdk_version" "$deployment_target") || status=$?
	case $status in
	0) printf '%s\n' "$simulator" ;;
	2) exit 1 ;;
	*) fail "no available iPhone simulator with iOS >= $deployment_target and <= $sdk_version (SDK); create one with 'xcrun simctl create'" ;;
	esac
}

# Verifies the result bundle: readable, at least one executed test, no failures.
check_results() {
	[ -d "$RESULT_BUNDLE" ] || { echo "error: result bundle missing: $RESULT_BUNDLE" >&2; return 1; }

	local summary
	summary=$(xcrun xcresulttool get test-results summary --path "$RESULT_BUNDLE" --compact) \
		|| { echo "error: cannot read test summary from $RESULT_BUNDLE" >&2; return 1; }

	/usr/bin/python3 -I -u -c '
import json, sys

try:
    s = json.load(sys.stdin)
    passed, failed = int(s["passedTests"]), int(s["failedTests"])
    skipped, expected = int(s["skippedTests"]), int(s["expectedFailures"])
    total, result = int(s["totalTestCount"]), s["result"]
except (ValueError, KeyError, TypeError) as e:
    print("error: unexpected test summary format: %r" % e, file=sys.stderr)
    sys.exit(1)

executed = passed + failed + expected
print("Native tests: %d total, %d executed, %d passed, %d failed, %d skipped, %d expected failures (result: %s)"
      % (total, executed, passed, failed, skipped, expected, result))
for f in s.get("testFailures", []):
    print("  FAILED %s: %s" % (f.get("testIdentifierString", "?"), f.get("failureText", "")))

if executed == 0:
    print("error: no tests were executed", file=sys.stderr)
    sys.exit(1)
if failed > 0:
    print("error: %d test(s) failed" % failed, file=sys.stderr)
    sys.exit(1)
if result != "Passed":
    print("error: test result is \"%s\", expected \"Passed\"" % result, file=sys.stderr)
    sys.exit(1)
' <<<"$summary"
}

command -v xcodebuild >/dev/null || fail "xcodebuild not found"
xcrun xcresulttool get test-results summary --help >/dev/null 2>&1 \
	|| fail "xcresulttool get test-results is not available in the selected Xcode ($(xcode-select -p)); Xcode 16 or newer is required"

if [ -n "${NATIVE_TEST_DESTINATION_ID:-}" ]; then
	DESTINATION_ID=$NATIVE_TEST_DESTINATION_ID
	echo "Using simulator $DESTINATION_ID (NATIVE_TEST_DESTINATION_ID)"
else
	SIMULATOR=$(select_simulator) || exit 1
	DESTINATION_ID=$(printf '%s' "$SIMULATOR" | cut -f1)
	echo "Using simulator $(printf '%s' "$SIMULATOR" | cut -f2) (iOS $(printf '%s' "$SIMULATOR" | cut -f3), $DESTINATION_ID)"
fi

mkdir -p "$OUTPUT_DIR" || fail "cannot create $OUTPUT_DIR"
rm -rf "$RESULT_BUNDLE" "$RAW_LOG" "$JUNIT_REPORT"

XCODEBUILD=(xcodebuild
	-project "$PROJECT"
	-scheme "$SCHEME"
	-sdk iphonesimulator
	-destination "id=$DESTINATION_ID"
	-configuration Debug
	-resultBundlePath "$RESULT_BUNDLE"
	GCC_PREPROCESSOR_DEFINITIONS='USE_JSCORE_FRAMEWORK=1'
	test)

if command -v xcpretty >/dev/null; then
	FORMATTER=(xcpretty -r junit --output "$JUNIT_REPORT")
else
	echo "warning: xcpretty not found; printing raw xcodebuild output (no JUnit report)" >&2
	FORMATTER=(cat)
fi

# Drain whatever the formatter leaves unread so tee and xcodebuild never see SIGPIPE.
format_output() {
	local status=0
	"${FORMATTER[@]}" || status=$?
	cat >/dev/null
	return "$status"
}

"${XCODEBUILD[@]}" 2>&1 | tee "$RAW_LOG" | format_output
STATUS=("${PIPESTATUS[@]}")
XCODEBUILD_STATUS=${STATUS[0]}
TEE_STATUS=${STATUS[1]}
FORMATTER_STATUS=${STATUS[2]}
[ "$TEE_STATUS" -eq 0 ] || echo "error: writing $RAW_LOG failed with status $TEE_STATUS" >&2
[ "$FORMATTER_STATUS" -eq 0 ] || echo "error: ${FORMATTER[0]} failed with status $FORMATTER_STATUS" >&2

[ "$XCODEBUILD_STATUS" -eq 0 ] || echo "error: xcodebuild test failed with status $XCODEBUILD_STATUS (log: $RAW_LOG)" >&2

check_results
RESULTS_STATUS=$?

echo "Raw log: $RAW_LOG"
echo "Result bundle: $RESULT_BUNDLE"

if [ "$XCODEBUILD_STATUS" -ne 0 ]; then
	exit "$XCODEBUILD_STATUS"
fi
if [ "$TEE_STATUS" -ne 0 ] || [ "$FORMATTER_STATUS" -ne 0 ] || [ "$RESULTS_STATUS" -ne 0 ]; then
	exit 1
fi
exit 0

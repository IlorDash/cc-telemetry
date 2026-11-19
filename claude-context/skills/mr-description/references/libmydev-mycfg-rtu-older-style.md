## Jira tickets

This MR closes the following tickets:

- **PROJ-354** — Add MYCFG XML configuration file import support. Adds parsing
  and conversion of MYCFG XML files into both `device_config_t` and
  device-config JSON, gated behind the `MYCFG_SUPPORT` build flag (disabled by
  default).

- **PROJ-355 / PROJ-356 / PROJ-357** — MYCFG device support in the RTU API:
  `mydev_convert_local_mycfg_to_json()`, `mydev_find_dev_rtu_mycfg()`, and
  MYCFG device support in `mydev_rtu_is_online()`.

- **PROJ-412** — Fix `FirmwareVersion` and `HasPasswd` not being imported from
  device config JSON: both had uninitialized/incorrect values after
  `mydev_read_all_device_config_parameters_json_string()`. They are now imported
  correctly. `fw_ver` and `has_passwd` were also added to
  `TestImportDevConfigFromJSON` (values taken from
  `unit-tests/test-files/test-device-config.json`) to verify the fix.

- **PROJ-475** — Cyrillic text handling fixes across string conversion, password
  hashing and logging.

## New features

- **MYCFG XML configuration support (opt-in).** Parsing and conversion of
  MYCFG XML files into both `device_config_t` and device-config JSON.
  Implemented as a two-stage pipeline: a SAX/expat parser into a flat node array,
  then type-specific converters. Supported parameter types: Float, Uinteger,
  Integer, Enumeration, String. Missing default enum entries are normalized
  during parsing so both consumers see a consistent entries list. Gated behind
  the `MYCFG_SUPPORT` build flag; uses `expat`, chosen over libxml2 for its
  smaller footprint on the OpenWRT target.

- **Local MYCFG → JSON conversion.** Added
  `mydev_convert_local_mycfg_to_json()` to convert a local MYCFG file to
  device-config JSON.

- **MYCFG device discovery over RTU.** Added `mydev_find_dev_rtu_mycfg()`,
  which reads the `AutoDiscoverDeviceOption` and `VersionInfoOption` parameters,
  connects over the given serial settings, and verifies the device by comparing
  the read name against the MYCFG default value. MYCFG files carry no factory
  number, so that field is left empty.

- **MYCFG online check.** `mydev_rtu_is_online()` now supports MYCFG devices
  via a new `mycfg_online_check_option_t`, comparing the `OnlineCheckOption`
  parameter value instead of a factory number.

- **`UID` field added to the device-config JSON schema.** Each parameter now
  carries a `UID` field (hex string), sourced from the `UniqueId` modificator or
  the parameter's ordinal number, intended for later use in modifying parameter
  modificator values.

- **Modbus RTU serial-parameter validation.** Added `are_valid_serial_params()`
  to validate serial port name (Linux and Windows forms), baud rate, parity, data
  bits, stop bits, and slave ID before connecting; `mydev_find_dev_rtu()` now
  rejects invalid parameters up front. `mydev_rtu_get_id()` also validates the
  serial port and slave ID.

- **libmodbus debug output follows the library log level.** Setting
  `LOG_DEBUG` now enables libmodbus's own debug output, so the raw Modbus frames
  appear alongside library logs without a separate switch.

- **Version suffixes.** The version is now a `VERSION_CORE` / `VERSION_SUFFIX`
  pair in the Makefile, producing versions such as `1.2.0-proj-475`. The suffix
  is free-form and reaches `mydev_version()` and the Windows `ProductVersion`
  string; suffixed Windows builds are marked `VS_FF_PRERELEASE`. A
  `check-release-version` target fails when a suffix is set, run in CI for merge
  requests targeting the default branch so a local marker cannot land on main.

- **Linux and Windows builds with `MYCFG_SUPPORT=1`,** including a static
  `expat` build added to the Windows (mingw) builder image.

## Bug fixes

- **`FirmwareVersion` and `HasPasswd` not imported from JSON** (PROJ-412) — both
  device-config JSON fields are now read correctly.
- **Cyrillic strings written back incorrectly** — `convert_string_back()` called
  the decode path where it should have encoded, corrupting non-ASCII strings on
  write. Tests added for Cyrillic round-trips over both RTU and TCP.
- **Cyrillic passwords rejected** — passwords are now encoded before hashing;
  `password-handler` also had an incorrect `decode_text_with_encoding()` call.
- **Missing NULL checks after `decode_text_with_encoding()`** — the function
  returns NULL on failure, and several call sites used the result unchecked.
- **Parameters with Modbus register address `0x0` were treated as non-existent** —
  address `0x0` is valid and is used by DEV_A to store the device name.
  Existence is now determined by register *size* alone.
  `mydev_read_device_config_parameter_json()` returns an error for parameters
  with no Modbus register, and all existence checks across the library were
  unified on `parameter_value_reg_exists()`.
- **`modbus_close()` / `modbus_free()` on error paths** — several functions
  leaked or double-freed the context; `connect_to_dev_rtu()`,
  `fast_connect_to_dev_tcp()` and `connect_to_dev_tcp()` call sites were
  refactored and `modbus_set_response_timeout()`'s return value is now checked.
- **`mydev_tcp_is_online()` connection loop** — the retry counter was not being
  decremented correctly in the connect helper; fixed, and the online check now
  uses the faster `fast_connect_to_dev_tcp()` path (appropriate for a periodic
  check).
- **`mydev-rtu` MYCFG default name retrieval and comparison** was incorrect.
- **Linked list** — added missing NULL-argument checks in `ll_remove_node()` and
  `ll_remove_list()`, tightened `ll_store_data()` validation (rejects zero size),
  and corrected error codes / log messages.
- **Missing `#pragma once`** added to `device-config-parameters-json.h` and
  `json-helper.h`.
- **Docs/header mismatches** — corrected `mydev_find_dev_rtu` /
  `mydev_find_dev_rtu_mycfg` signatures in docs and headers.
- **`mycfg_online_check_option_t`** — corrected the type name in code and docs
  (it is a typedef).
- **CI shipped a dangling `libmydev.so` symlink** — the artifact contained the
  link but not its target.

## Refactoring

- **container-system:** removed `enum_converter` from `node_raw_val_converter_t`;
  it is only required by `create_enum_value_node()` and not needed for read/write
  handling of enum values, so it was removed from `node_raw_val_converter` and
  the device-config JSON. Enum descriptor construction moved into `node.c`.
- **Encoding helpers moved to a new `encodings-handler` module** out of
  `node-val-converters`, so `crypto-helper` no longer pulls in container-system
  headers.
- Refactored the device-config parameter JSON module so parameter properties are
  added/extracted in one place.
- Added a `const` modifier to `str_to_node_val_desired_view()` to support
  MYCFG.
- Renamed MYCFG handler files and functions for readability; the JSON handler
  now returns a JSON string rather than a `cJSON *`.
- mydev-rtu: removed useless defines.

## Documentation

- Documented the new MYCFG API (`mydev_convert_local_mycfg_to_json()`,
  `mydev_find_dev_rtu_mycfg()`, `mycfg_online_check_option_t`).
- Fixed the `DEVICE_CONFIG_ENUM` description after merge.
- Various device-config JSON schema doc updates for the new `UID` field and the
  changed parameter field ordering.

## Tests

- Added MYCFG test fixtures (`DEV_B.mycfg`, `DEV_C.mycfg`,
  `DEV_A.mycfg`) and conversion / discovery / online-check tests.
- Added device-config JSON import checks for `fw_ver` and `has_passwd` in
  `TestImportDevConfigFromJSON`.
- Added connection-failure tests for `connect_to_dev_rtu()`,
  `fast_connect_to_dev_tcp()` and `connect_to_dev_tcp()`.
- Added Cyrillic string conversion tests over RTU and TCP, and
  `TestMyDevReadOneDeviceConfigParameterJSON_WithModbusRegAddrZero`.
- `mock.c` now supports the `modbus_set_debug()` call with a flag check.
- **unit-tests:** fixed copy-paste log messages in the Algorithm-info checker
  (Group/Number/Version were all reporting "Name").

## CI / build

- Setup Linux and Windows build jobs with `MYCFG_SUPPORT=1`; added a static
  `expat` build to the Windows builder image.
- New `check` stage running `make check-release-version` for merge requests
  targeting the default branch. Build jobs `need` it optionally, so branch
  pipelines are unaffected.
- Linux artifact path widened to `build/libmydev.so*` so the versioned file and
  its symlink are both archived.

## Compatibility notes

- **New public API and struct:** `mydev_find_dev_rtu_mycfg()`,
  `mydev_convert_local_mycfg_to_json()`, and the `mycfg_online_check_option_t`
  field in `mydev_rtu_t`. These are only active when built with `MYCFG_SUPPORT`.
- **`device_config_read_param_reg()` replaced** by
  `device_config_read_param_reg_value()`; `parameter_value_reg_exists()` is now
  public. Callers of the old function need updating.
- **Encoding helpers moved** from `container-system/node-val-converters.h` to the
  new `encodings-handler.h`. Direct includers of the old header must switch.
- **`mydev_read_device_config_parameter_json()` now returns an error** for
  parameters without a Modbus register, where it previously returned a result.
- **Device-config JSON schema change:** parameters now include a `UID` field,
  remove EnumConverter field, the field order within parameter objects changed.
  Consumers parsing this JSON should treat it as key-based, not order-based.
- **Build:** MYCFG support requires linking against `expat` and building with
  `MYCFG_SUPPORT=1`; it is off by default, so existing builds are unaffected
  unless the flag is enabled.
- **Debug logging is louder:** `LOG_DEBUG` now also enables libmodbus debug
  output.

## New features

- **MYCFG device discovery over TCP.** Added `mydev_find_dev_tcp_mycfg()`.
  The lookup compares `AutoDiscoverDeviceOption` with its default value of
  any supported type, not only String, and fills the name, firmware version
  and online check option of `mydev_info_t`. To share it with RTU, the
  transport-independent lookup and online check moved from `mydev-rtu.c` to
  `mydev.c`, so `mydev_tcp_is_online()` now handles MYCFG devices too.

- **Per-parameter Modbus functions.** Every parameter used to be read with
  Read Holding Registers and written with Write Multiple Registers, so devices
  that use coils (e.g. a Modbus TCP relay) could be neither
  read nor switched. Parameters now carry their own read function (Read Coils,
  Discrete Inputs, Holding Registers, Input Registers) and write function
  (Write Single Coil, Single Register, Multiple Coils, Multiple Registers),
  parsed from `ModbusReadCommand` / `ModbusWriteCommand` of the MYCFG file.
  A missing command makes the parameter read-only or write-only. PRG file
  devices keep the defaults (0x03 / 0x10).

- **Write-only parameters stay "not written".** A write-only parameter cannot
  be read back, but its enum `Selected` and string `Value` were filled from
  the default, so a UI showed a value that was never written and applying a
  saved config resent it (e.g. a toggle command). Now they are `null` until
  the first write, like numeric values; enum `Entries` and `Default` stay
  filled. Applying a config skips an enum without a selected entry, and
  writing one fails before any Modbus traffic.

- **Read selected parameters.** Added
  `mydev_read_selected_device_config_parameters_tcp()` / `_rtu()`: read only
  the given parameters over one connection straight into the cached config.
  An unknown parameter or one with `NONE_ACCESS` fails the call before
  connecting.

- **Per-parameter read errors.** A single register the device rejects (e.g.
  illegal data address) used to fail the whole read. Now a Modbus exception
  or an unconvertible answer is recorded as a read error of that parameter,
  which keeps its cached value, and the read goes on. Connection errors
  (timeout, socket error, bad CRC, gateway exceptions) still abort with
  `-ERR_MODBUS`. The errors are returned as
  `{"read_errors": [{"type", "name", "addr", "suffix", "message"}, ...]}`.

## Bug fixes

- **Hidden parameters were polled** — reading all parameters now skips
  `NONE_ACCESS` and `WRITE_ACCESS` parameters.
- **`convert_node_raw_val()` corrupted the cached value on failure** — it
  freed the old value before converting; the value is now replaced only on
  success.
- **Enum value matching no entry** was silently ignored; it now fails the
  config read and the single-parameter read.
- **MYCFG lookup defects:** `mydev_find_dev_rtu_mycfg()` did not validate
  the serial parameters and dereferenced a NULL ID; `mycfg_get_device_info()`
  and `xml_node_to_parameter()` leaked memory on error paths.
- **Memory leaks** in `mydev_read_all_device_config_parameters_json_string()`
  (whole config tree on a failed read),
  `device_config_param_import_from_json_string()` and two `realloc()` failure
  paths of the converters.
- **`DATE` export** no longer adds an empty `"Dates"` array next to
  `"DateTimes"`.

## Compatibility notes

- **Exported signature change:**
  `mydev_read_all_device_config_parameters_json_tcp()` / `_rtu()` take a new
  `char **read_errors_json` before `res`; `NULL` keeps the old strict
  behaviour.
- **Struct layout changes (ABI break):** `mycfg_online_check_option_t` and
  `mydev_rtu_t.online_check_option` are removed in favour of
  `mydev_info_t.online_check_option`; `struct node_modbus_desc` gains
  `read_func` / `write_func`.
- **New API:** `mydev_convert_local_mycfg_to_device_config()` (config of a
  found MYCFG device, used by mydev-manager) and
  `mydev_are_device_config_parameters_equal()` (moved from mydev-manager).
- **Device-config JSON:** new optional `ModbusDesc` keys `ReadFunc` /
  `WriteFunc`, written only when not default, so the JSON of PRG devices and
  existing saved configs is unchanged; `Selected` and string `Value` may be
  `null`.
- **Behaviour:** reading all parameters no longer reads `NONE_ACCESS` /
  `WRITE_ACCESS` parameters, and a rejected parameter no longer fails the
  read when `read_errors_json` is passed.

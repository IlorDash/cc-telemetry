## New features

- **MYCFG devices over Modbus TCP (opt-in).** New ubus methods, available
  only when built with `MYCFG_SUPPORT=1`:
  - `find_devs_tcp_mycfg` — `ipaddr`, `mask`, `port`, `path`,
    `scan_session_token`; same scan session and reply as `find_devs_tcp`, but
    devices are recognised by the MYCFG file at `path`
    (`mydev_find_dev_tcp_mycfg()`);
  - `add_dev_tcp_mycfg` — `ipaddr`, `path`; the device config is converted
    from the local MYCFG file instead of being read from the device, and its
    header carries the found device info (name, firmware version, ID), so it
    shows up in the saved config and in `display_config`.

  Internally `mydev_manager_find_devs_tcp()` and `mydev_manager_add_dev_tcp()`
  take an optional `mycfg_path` (`NULL` keeps the PRG file flow). The online
  check of added MYCFG devices uses their `OnlineCheckOption`.

- **MYCFG templates installed on the device.** New `mycfg-templates/`
  folder with a Modbus TCP relay description. With
  `MYCFG_SUPPORT=1`, `make install` puts its `*.mycfg` files into
  `$(DATADIR)/mydev-manager/mycfg-templates`
  (`/usr/share/mydev-manager/mycfg-templates` by default); `DATADIR` and
  `MYCFG_TEMPLATES_DIR` can be overridden, `uninstall` removes the folder.

- **`read_selected_parameters_tcp` / `read_selected_parameters_rtu`.** Read
  back only the given parameters, e.g. after a write, instead of polling the
  whole device with `read_all_parameters_xxx`. They take the same arguments as
  `write_parameter_xxx`, but `param_json` may hold several parameters of
  several types. The parameters are read straight into the cached config and
  the reply is the whole config, as from `read_all_parameters_xxx`. The call
  fails as a whole, before any Modbus traffic, for a parameter that is not in
  the config or has `NONE_ACCESS`, and for a device that does not respond.

- **`read_errors` in read replies.** `read_all_parameters_xxx` and
  `read_selected_parameters_xxx` no longer fail when a single parameter
  cannot be read. On success the reply carries `"error": 0`, a `read_errors`
  array (empty when everything was read) and the whole config:

  ```json
  {
    "error": 0,
    "read_errors": [
      { "type": "Uints", "name": "...", "addr": "0x10", "suffix": "", "message": "..." }
    ],
    ...config...
  }
  ```

  A parameter listed in `read_errors` keeps its cached value. The call still
  fails as a whole when the device does not answer at all. `save_config_xxx`
  keeps reading strictly.

## Bug fixes

- **First write of a write-only parameter returned an error** —
  `update_parameter_value()` rejected any parameter whose stored value is
  `NULL`, which is exactly a write-only numeric/string parameter that was not
  written yet. The value reached the device, but `write_parameter` replied
  with an error and the value was not stored for `read_all_parameters` /
  `display_config`. The `NULL` check now applies to enums only.
- **Dangling enum label after `write_parameter`** — the selected entry was
  copied from the request, whose entries are freed right after the update.
  `selected` now points to the stored entry with the same value; a request
  without a selected entry or with a value not among the stored entries is
  rejected.
- **`read_all_parameters_xxx` leaked `config_json` on every call** — the reply
  is now built in `build_read_parameters_reply()`, which frees it.
- **`read_all_parameters_xxx` passed a NULL `ipaddr` / `ser_port`** to the
  manager when the argument was missing; they now return
  `UBUS_STATUS_INVALID_ARGUMENT`.

## CI / build

- `MYCFG_SUPPORT ?= 0` in the Makefile; `MYCFG_SUPPORT=1` adds
  `-DMYCFG_SUPPORT` and installs the MYCFG templates.
- `coverage` and `clean-coverage` targets added to `unit-tests/Makefile`
  (same as in libmydev), so coverage of `mydev-manager.c` and the database
  can be collected; the command is documented in the README:

  ```bash
  ./cpputest/docker/run.sh make -f ../unit-tests/Makefile CPPUTEST_USE_GCOV=Y clean clean-coverage coverage
  ```

## Compatibility notes

- **Requires libmydev 1.3.0** (changed signatures of the read functions,
  `mydev_info_t` layout). Bump both together.
- **ubus reply change:** `read_all_parameters_xxx` replies now contain a
  `read_errors` array next to the config, and a partially failed read is a
  success with entries in `read_errors`. Clients must check it to know which
  values were not refreshed.
- **Behaviour change:** `read_all_parameters_xxx` no longer reads hidden
  (`NONE_ACCESS`) and write-only (`WRITE_ACCESS`) parameters; they keep their
  cached value.
- **Behaviour change:** `write_parameter_xxx` for an enum rejects a value that
  is not among the stored entries.
- **Missing argument:** `read_all_parameters_xxx` without `ipaddr` /
  `ser_port` returns `UBUS_STATUS_INVALID_ARGUMENT`.
- **Build:** the MYCFG methods and templates exist only with
  `MYCFG_SUPPORT=1` (libmydev must be built with it too); the default build
  is unchanged. The Yocto recipe is not changed in this MR.

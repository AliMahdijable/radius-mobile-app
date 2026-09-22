# Cisco monitoring

The Devices detail screen supports Cisco over **SSH** and explicitly selected **Telnet**. Choose the transport and its management port in the device form, then store the device credentials through the existing credentials flow. Monitoring requires `devices.monitor`; editing the device requires `devices.manage`.

- SSH normally uses port 22; Telnet normally uses port 23.
- Telnet is unencrypted. Prefer SSH where the device supports it.
- The account needs permission to read `show` commands.
- The app does not silently switch from SSH to Telnet.
- The Cisco panel reads system and interface information. It does not configure ports, VLANs, or reboot the switch.
- Bulk model detection includes Cisco, uses the configured transport, and shares the conservative concurrency limit used for SSH devices.
- Missing measurements remain unavailable, rather than being reported as zero.

Images are bundled in `assets/devices-images/` and use the existing `DeviceImage` resolver and image picker. Exact product identifiers and known Catalyst family names are supported. Family pictures illustrate the product family rather than every port-count variant. Image provenance is recorded in `cisco-images.md`.

# V5 Port Map (Tahera Workflow)

This map is for fast PROS uploads after USB/port changes.

## Logical Port Roles (V5 Brain)
- **System Port**: Use this for `pros upload` (program/firmware channel).
- **User Port**: Use this for runtime serial/user communication.
- **Cortex Port**: Not used for V5.

## Last Known Device Mapping
Last successful upload session:
- System Port: `/dev/cu.usbmodem11101`
- User Port: `/dev/cu.usbmodem11103`
- Program uploaded: `Tahera` to slot `1`

Note: The numeric suffixes (`11101`, `11103`, etc.) can change after reconnect/reboot. Always rescan before upload.

## Fast Rescan + Upload
1. Scan ports:
   - `pros lsusb`
2. Pick the listed **V5 System Port**.
3. Upload Tahera:
   - `pros upload . /dev/cu.usbmodemXXXXX --name Tahera --after run`

## If Upload Fails on the First Port
- If handshake fails on one port, retry using the other listed V5 port.
- In the last session, upload failed on the user port and succeeded on the system port.

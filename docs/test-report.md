# Scanner device test report

Codex@M4 checked recordings from a physical iPhone 13 Pro Max on November 24, 2026. The device recordings predate the 30 fps default change in `75e718f`.

| Test | Result |
| --- | --- |
| T2 · 30-second clips at 60 and 30 fps | Pending. All eight readable clips matched decoded RGB frames to depth PNG counts exactly (79–205 frames per clip). The longest clip was about 9 seconds. A ninth folder had unreadable RGB video and no depth PNGs. Its stop conditions are unknown. |
| T3 · IMU and five consecutive stops | All nine IMU CSV files had valid numeric rows with seven columns. Five consecutive crash-free stops have not been observed. |
| T4 · Bluetooth recording | Passed per Allen. The remote started and stopped recording, the button changed shape, and saved RGB video played back. |
| T5 · Music during recording | Pending. |
| T6 · Distortion output | No `distortion/` folder appeared in any of the nine inspected folders. |

Allen requested 30 fps as the default. Existing FPS preferences are preserved, and 60 fps remains selectable. Allen confirmed 30 fps worked on the phone. That observation could reflect an existing saved preference, so the first-launch default remains unverified on the device.

No writer drop count was captured. A match between RGB and depth file counts checks alignment of saved frames and cannot measure dropped frames. The writer log counts rejected RGB appends and writer readiness timeouts. It does not count frames skipped before they reached the writer.

## Unreadable recording follow-up

The ninth folder contained a zero-byte `rgb.mp4`, a header-only `odometry.csv` (zero data rows), zero depth PNGs, and two valid IMU data rows. This is consistent with an attempt that never saved an RGB frame. The files do not establish why it stopped. Whether it appeared in the recording list, showed an error alert, or followed a screen lock is still unknown. The folder was kept for investigation.

Subsequent builds log separate counts for frames skipped because the encoding queue was full and frames rejected by the RGB writer. These counters exclude intentional frame-rate subsampling.

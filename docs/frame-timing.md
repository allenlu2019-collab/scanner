# Scanner frame timing comparison

Codex@M4 compared three recordings using consecutive ARKit timestamps in each export's `odometry.csv`. Each plotted gap is placed at the elapsed capture time of the later frame. The dashed reference is one frame interval at 30 fps.

![Adjacent saved frame gaps versus elapsed time](frame-timing.png)

| Export | App | Saved samples/s from ARKit timestamps | Gaps around 67 ms | Decoded RGB / depth PNGs |
| --- | --- | ---: | ---: | ---: |
| `0163437466.zip` | Original, as reported by Allen | 29.93 | 1 | 946 / 947 |
| `5bcd3f9f1d.zip` | Modified | 21.18 | 257 | 619 / 619 |
| `4ee8b8c860.zip` | Modified | 22.47 | 181 | 570 / 570 |

Gap counts use timestamps rounded to the nearest 16.667 ms. The original MP4 reports 947 frames in stream metadata, while ffprobe emitted 946 decoded frames. Both modified exports had contiguous depth indices matching the decoded RGB counts. All three use 1920 × 1440 HEVC Main at roughly 9.4 Mbps and 256 × 192 16-bit depth PNGs.

The repeated gaps appear in the capture timestamps, which explains the lower saved cadence even though all three MP4s report a nominal 30 fps. The exports cannot determine where samples were skipped. The three-frame queue limit predates the fork. Potential contributors include queue saturation, RGB writer backpressure, and fewer ARKit callbacks while preview rendering is active. The synthetic MP4 timestamps are a separate source of timing error when callback cadence varies.

**Feedback requested from Claude Code:** Review which pipeline changes could explain this regression and suggest the smallest instrumentation or controlled experiment to isolate it. A proposed comparison is two 30 fps recordings of the same scene on the same phone, one with each preview mode, collecting the queue-full and writer-drop counters alongside incoming ARKit callback timing. No root cause has been confirmed.

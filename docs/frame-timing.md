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

## RGB versus depth preview follow-up

Both exports report a nominal 30 fps. The preview labels are tentative because the exports do not record the active preview mode.

| Export | Tentative preview | Capture span | Saved samples/s | Gaps around 67 ms | Decoded RGB / depth PNGs / odometry rows |
| --- | --- | ---: | ---: | ---: | ---: |
| `e18044d4f1.zip` | Depth | 29.26 s | 25.29 | 129 | 741 / 741 / 741 |
| `c5309b33a9.zip` | RGB | 29.64 s | 26.11 | 108 | 775 / 775 / 775 |

Depth indices were contiguous in both runs. The 95th percentile capture gap was about 66.69 ms in each. Both fell short of sustained 30 fps. If the labels are correct, RGB preview was slightly faster in this pair, so the comparison does not support RGB preview as the main cause. No per-frame timing CSV or console drop counters were available for these runs, and the source of the missing frames remains unconfirmed.

## Instrumented experiment and upstream baseline

The untouched upstream v1.4 build (`ec3e1dc`) saved 667 odometry samples in 31.06 s, or 21.44 samples/s. Most gaps were near 50 ms (471 of 666). It wrote 667 depth PNGs, and ffprobe decoded 666 RGB frames. The upstream run demonstrates that the modified app's changes are not required to reproduce uneven timing. The older export labeled original averaged 29.93 samples/s, but its exact app version is unknown.

The modified build's `3af9be24ab` recording saved 754 samples in 30.98 s, or 24.31 samples/s. Its exported `stats.json` confirms the 30 fps setting and depth preview, with **163 queue-full drops and zero RGB writer drops**. This locates the recorded drops before the writer. A writer that eventually accepts every frame could still spend time waiting, so zero writer drops does not rule out writer latency.

The signed build succeeded and exported the counters on a physical iPhone 13 Pro Max. The stats file records the selected FPS, preview mode (including mixed), saved frames, and both drop counters. These counters omit intentional FPS subsampling and cannot count frames ARKit never delivered.

### Next experiment

1. Add debug-only, in-memory timing measurements. Record incoming ARKit timestamp gaps and callback arrival gaps, preview CPU time, queue wait, RGB writer wait and append time, depth PNG time, confidence PNG time, and remaining metadata time. Write the diagnostics once at finalization so instrumentation adds no file writes per frame.
2. Repeat three 30-second runs at 30 fps on the same iPhone and scene, with depth preview held constant, the phone allowed to cool between runs, and the same signing/build configuration. Report saved FPS, both drop counters, and median and 95th-percentile times per stage. Repeat one run with diagnostics disabled to check their overhead.
3. Change the measured bottleneck first. If PNG work and RGB writing jointly saturate the serial queue, test overlapping them behind the existing bounded admission limit. Preserve RGB/depth/odometry frame numbering, keep each writer serial, and finish both paths before releasing the frame slot. Keep queue capacity fixed in this comparison so it is clear what helped. If callbacks are already slow before admission, investigate capture delivery and preview timing before changing the encoders.
4. Repeat the same runs after the change. Aim for at least 29.5 saved samples/s and zero queue and writer drops in each run, with matching decoded RGB, depth PNG, and odometry counts. Report any incoming ARKit gaps separately. Evaluate using actual capture timestamps for the MP4 as a separate change to playback timing.

**Feedback requested from Claude Code:** Does this instrumentation isolate the stage that saturates the queue? Please review the proposed overlap for frame ordering, ARFrame lifetime, and finalization risks, and suggest any simpler experiment before we change the encoder.

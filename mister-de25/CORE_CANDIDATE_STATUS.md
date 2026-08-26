# Platform V2 core candidate status

This table records the install gate for the first expanded Platform V2 core
pack. `load-pass` means the complete RBF was accepted by the guarded runtime
loader on the physical DE25-Nano, the FPGA returned to `operating`, and Menu
recovery succeeded. It does not mean BIOS, cartridge, video, input, and audio
behavior have all passed.

| Core | Artifact | SHA-256 | Worst setup | ALMs | M20Ks | Hardware |
| --- | --- | --- | ---: | ---: | ---: | --- |
| ao486 | `artifacts/ao486-v2/AO486_v2.rbf` | `c56757c5109359c46ae484a8de74bed513dde8ced5bfc891277b0518a2feb6ca` | +0.337 ns | 79% | 98% | pending |
| IBM PC/XT | `artifacts/pcxt-v2/PCXT_v2.rbf` | `a20268c5bd3ad04c36fca4c88b965a073cc1644f84124c918e0c2c494c5d32b6` | +0.245 ns | 58% | 36% | pending |
| Sega Master System / Game Gear | `artifacts/sms-v2/SMS_v2.rbf` | `09e7c277addd60a6d300ccb863f66dff35c343b52222a070e17e155a422c70a2` | +0.893 ns | 68% | 68% | pending |
| Atari 7800 / 2600 | `artifacts/atari7800-v2/Atari7800_v2.rbf` | `6013be37c79c8d924405b6f2bbd459c98eaf4bedd4e83f901ef81eeb0799ea7f` | +0.551 ns | 59% | 49% | load-pass |
| Atari Jaguar | `artifacts/jaguar-v2/Jaguar_v2.rbf` | `aebd924e5d4e0832d1b5588bd6191b9a6dfbe66e7d90e5528475e1b959a6efcc` | +0.070 ns | 74% | 39% | load-pass |
| PlayStation | `artifacts/psx-v2/PSX_v2_ntsc_bringup.rbf` | `09630e3f1f858b2ea2465cba1b9ac5e26bfed1a236521d07a8f8291848f80aad` | +0.477 ns | 95% | 72% | load-pass |
| Nintendo 64 | `artifacts/n64-v2/N64_v2_ntsc_bringup.rbf` | `ffb8d80374def7b4fa82daf3bc9602ed16bedda9cbd181232fd260c0128cf60d` | +0.859 ns | 93% | 46% | pending |
| Sega Saturn LIGHT | `artifacts/saturn-v2/Saturn_v2_ntsc_light_bringup.rbf` | `6cce06085296b1aa6b6bbc99dc33d846b914c59df3c0c3fdefed70a2db1a5406` | +0.051 ns | 97% | 74% | pending |

All eight builds report:

- successful Agilex 5 fitting and assembly;
- zero failing setup and hold endpoints;
- zero unconstrained paths;
- an exact `FDCDD4C99876BAE3D17BB5B0AF4A4C7B7D55B2CE17D05C535A5BF69DD7DE930B`
  HPS I/O compatibility hash match with Menu V2;
- an RBF whose SHA-256 matches its checked sidecar.

The first content-validation order is PC/XT, SMS/Game Gear, ao486, N64, then
Saturn. Atari 7800, Jaguar, and PlayStation already passed guarded loading but
still need content tests. Jaguar and Saturn have positive but narrow setup
margin, so they must retain automatic Menu recovery during early testing.

The N64, PSX, and Saturn artifacts are fixed-NTSC bring-up images. PAL and
runtime video-clock switching remain later acceptance gates. ao486's GUS path
must be tested at a supported 30, 56.25, 90, or 100 MHz CPU-clock profile; the
upstream 15 MHz GF1 mode is not supported by the current Agilex clock path.

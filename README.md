
# Stray Scanner App

The goal of this app, is to allow easy access to raw RGB-D video datasets recorded using LiDAR enabled iOS devices. The app can be downloaded for free [on the iOS App Store](https://apps.apple.com/us/app/stray-scanner/id1557051662).

<img src="images/screenshot.jpg" style="width: 250px" alt="Stray Scanner RGB-D scanning view">

## Usage

Documentation can be found under the [docs](docs/) directory. The document [docs/format.md](docs/format.md) describes the data format and conventions used in the app.

New installations default to 30 fps. Tap the FPS button to change the rate. On the recording screen, tap the live image to switch between RGB and depth. On iOS 17.2 or later, the iPhone volume buttons and compatible Bluetooth shutter remotes can start and stop recording. Remotes that send Enter or Space can also toggle recording, including on older supported iOS versions. Saved scans open in the RGB video player and play automatically.

## Related projects

- [StrayVisualizer](https://github.com/kekeblom/StrayVisualizer): a project to visualize the raw data collected by the app
- [MATLAB Scripts](https://github.com/PyojinKim/StrayScannerVisualizer): a set of tools to work with the data format in Matlab
- [Autolabel](https://github.com/ethz-asl/autolabel): an interactive volumetric labeling tool

## Contributing

Contributions are welcome. To contribute, simply open a pull request.

Some ideas for improvements include:
- Better scan viewer
- Better ways to organize scans, e.g. through tags
- Recording other modalities, such as audio, Wifi or GPS
- Direct upload to cloud services or S3


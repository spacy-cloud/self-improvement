# Android app icon

The launcher uses the green gradient and white rising arrow already shown in
`WelcomeStep._AppMark`. The mark uses the light-theme colors `#20B65C` and
`#0E8540` and Flutter's `Icons.trending_up_rounded` glyph (U+F0254).

- `app-icon.png`: 1024 px reference mark with the onboarding proportions.
- Android density PNGs: 48, 72, 96, 144 and 192 px fallbacks.
- Android API 26+: separate gradient background and transparent foreground;
  Android applies the launcher's shape. No baked-in external shadow.
- Android API 33+: the same arrow supplies the monochrome layer for themed icons.

The arrow is derived from Google Material Icons, distributed with the Flutter
SDK's MaterialIcons-Regular.otf. Licensed under Creative Commons Attribution
4.0 International; see `MaterialIcons-LICENSE.txt` and
https://creativecommons.org/licenses/by/4.0/ . The color treatment and launcher
composition follow this project's existing onboarding mark. The artwork can be
recreated by rendering this glyph on a centered 52/96-em square, adding a
horizontal gradient and a 28/96 corner radius. The adaptive foreground uses
39/108-em inside the 108 dp canvas, preserving the onboarding proportions
within Android's central 72 dp mask.

After changing launcher resources, rebuild the APK and install the update;
Flutter hot reload does not update Android launcher resources. iOS launcher
assets have not been changed as part of this Android fix.

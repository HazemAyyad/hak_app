# Splash logo

The splash uses `assets/branding/haq_splash_logo.png`, a transparent foreground
extracted from the supplied `شعار التطبيق.png` with the built-in ImageGen tool.
The white strokes were changed to navy for the existing ivory splash background.
The launcher icon keeps its blue tile. Android and iOS launch images use the same
transparent splash artwork; iOS launch images are resized to 160/320/480 pixels.
The splash plays `assets/animations/haq_splash.riv` with the Rive runtime. Its
source is `tool/haq_splash_rive/scene.rml`: the transparent mark gently fades in,
rises 12 points and settles without bouncing. A warm radial glow and seven
translucent dawn rays appear behind its crown, then fade. A single narrow,
screen-blended copy of the logo sweeps across the original through an animated
clipping window; the light stays on the mark instead of drawing a rectangle.

Flutter fades/slides in the localized tagline in two phrases, synchronized with
the Rive entrance: the first begins at 720ms, the second at 1152ms, and both are
fully readable by 1560ms. The existing translated sentence is split at its first
comma, without changing translations. The entrance finishes at 2500ms. Reduced
motion and loading failure show the static logo and whole tagline immediately.
Startup remains bounded if the renderer cannot load.

Android 12+ uses `drawable-nodpi/haq_launch_logo_android12.png`: a 1152px
transparent canvas with the 640px source centered inside it, so the whole mark
stays inside the system's circular mask. Padding is baked into the PNG because
an XML layer-list still clipped the bitmap on the connected device.
See the [Android splash dimensions](https://developer.android.com/develop/ui/views/launch/splash-screen#dimensions).
The earlier direct bitmap was visibly clipped on the connected Android 13 phone.
The padded PNG and the moving Rive entrance were then verified on the same
Xiaomi 2201117SI device with a recorded cold start through to the home screen.
The debug APK was installed as an update, preserving app data.
The later dawn/rays/light-sweep revision was verified in Flutter captures and
startup tests; the phone was disconnected during that revision's validation.

The adhan preview and native Android adhan/reminder activity use
`assets/branding/haq_logo_light.png` directly on the dark photo, without a tile
or circular plate. This is the white-and-turquoise transparent variant prepared
with the built-in ImageGen tool.

Regenerate launcher icons with `tool/generate_branding_icons.ps1`. It prepares
an opaque navy-backed `haq_app_icon_ios.png` for `image_path_ios` before running
the generator. This avoids the incorrect alpha blending in
`flutter_launcher_icons` 0.14.4 that otherwise produces a green iOS background.

Generation prompt (transparent background enabled):

```text
Use case: background-extraction. Edit target: attached Haq application logo. Produce a precise clean transparent PNG logo asset for the application's ivory splash screen. Completely REMOVE the entire rounded blue square tile, every blue/navy background area inside and outside the arch and lettering, all background waves, all dark cast shadows, and outer margins. Keep ONLY the foreground calligraphic mark: the pointed mosque-like arch, the Arabic حق lettering and its two diamond dots, the HAK Latin letters and silver crossing swoosh, and the turquoise leaf/swoosh beneath. Preserve the exact letter shapes, positioning, proportions and composition of the input, do not redesign, do not change the Latin text, do not add any star, text, badge or decoration. For legibility on an ivory splash, convert only the originally white arch, Arabic lettering and white lower parts of HAK to solid deep navy #102A43, preserve teal portions of HAK and the turquoise leaf gradient and the silver crossing swoosh. Smooth crisp antialiased edges. True transparent alpha everywhere other than the logo strokes, including holes and spaces within the letters. No square or plate behind the mark, no checkerboard drawn into the image. Center the isolated mark on a square transparent canvas, with modest 8% padding. Output a production quality transparent logo.
```

Adhan logo prompt (transparent background enabled):

```text
Use case: precise-object-edit. Edit target: this transparent Haq logo. Create a light version for the app's dark adhan screen. Change ONLY the navy foreground strokes to white #FFFFFF: the pointed arch, Arabic حق calligraphy and its two diamond dots, and navy lower portions of the HAK Latin letters. Preserve the turquoise upper HAK letter portions, silver crossing swoosh and turquoise leaf gradient. Preserve the exact shapes, text, spacing, composition, scale, square canvas and margins of the input. Keep true transparent alpha everywhere else, including all holes and gaps. No background, no blue tile, no circle, no plate, no shadow, no glow, no added words, no new shapes. Clean crisp antialiased edges. This is only recoloring the existing foreground for visibility on a dark photo, not a redesign.
```

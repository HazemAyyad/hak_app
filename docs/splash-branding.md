# Splash logo

The splash uses `assets/branding/haq_splash_logo.png`, a transparent foreground
extracted from the supplied `شعار التطبيق.png` with the built-in ImageGen tool.
The white strokes were changed to navy for the existing ivory splash background.
The launcher icon keeps its blue tile. Android and iOS launch images use the same
transparent splash artwork; iOS launch images are resized to 160/320/480 pixels.
The splash currently uses Flutter opacity/scale animation, not the old Rive file.

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